import AppKit
import Defaults
import Foundation
import KeyboardShortcuts
import Observation

extension Defaults.Keys {
  static let actionRules = Key<[ActionRule]>("actionRules", default: ActionRule.presets)
  static let terminalAppBundleIDs = Key<[String]>("terminalAppBundleIDs", default: TerminalApps.defaults)
}

extension KeyboardShortcuts.Name {
  // No default binding to avoid colliding with other apps; user assigns it.
  static let runDefaultAction = Self("runDefaultAction")
}

// Evaluates rules against clipboard items and runs the resulting actions.
// Rules are read live from `Defaults` so the settings UI can edit them directly.
@MainActor
@Observable
final class ActionEngine {
  static let shared = ActionEngine()

  // Last value produced by an auto-run transform, used to swallow the clipboard
  // poller's echo so auto-run doesn't loop forever.
  private var lastAutoOutput: String?

  // Per-action shortcut Names we've already wired an onKeyDown handler for.
  // The handler re-resolves the config by id at fire time, so it survives rule
  // edits/reloads without re-registering (which would clobber other handlers).
  private var registeredActionShortcutNames = Set<String>()

  private init() {}

  var rules: [ActionRule] { Defaults[.actionRules] }

  // MARK: Matching

  func matchingRules(for item: HistoryItem) -> [ActionRule] {
    let kinds = ValueClassifier.kinds(of: item)
    let text = ValueClassifier.primaryString(of: item)
    let app = item.application
    return rules.filter { $0.enabled && matches($0, kinds: kinds, text: text, app: app) }
  }

  private func matches(_ rule: ActionRule, kinds: Set<ValueKind>, text: String, app: String?) -> Bool {
    guard !rule.conditions.isEmpty else { return false }

    let results = rule.conditions.map { condition -> Bool in
      switch condition {
      case .kind(let kind):
        return kinds.contains(kind)
      case .sourceApp(let bundle):
        return app == bundle
      case .contains(let needle):
        return !needle.isEmpty && text.localizedCaseInsensitiveContains(needle)
      case .regex(let pattern):
        guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else {
          return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
      case .softWrapped:
        return TextUnwrap.isSoftWrapped(text)
      case .terminalSource:
        return app.map { Defaults[.terminalAppBundleIDs].contains($0) } ?? false
      }
    }

    return rule.matchMode == .all ? !results.contains(false) : results.contains(true)
  }

  // MARK: Resolution

  // All runnable actions for an item, in rule order then action order, deduped.
  // The first element is the default action.
  func resolvedActions(for item: HistoryItem) -> [ClipboardAction] {
    var seen = Set<String>()
    var result: [ClipboardAction] = []
    for rule in matchingRules(for: item) {
      for config in rule.actions {
        guard let action = ActionFactory.make(config), action.canRun(on: item) else { continue }
        if seen.insert(action.id).inserted {
          result.append(action)
        }
      }
    }
    return result
  }

  func defaultAction(for item: HistoryItem) -> ClipboardAction? {
    resolvedActions(for: item).first
  }

  // MARK: Running

  func run(_ action: ClipboardAction, on item: HistoryItem) {
    Task {
      do {
        try await action.run(on: item)
      } catch {
        NSSound.beep()
      }
    }
  }

  func runDefault(for item: HistoryItem) {
    guard let action = defaultAction(for: item) else {
      NSSound.beep()
      return
    }
    run(action, on: item)
  }

  // Global-shortcut entry point: run the default action on the most recent item.
  func runDefaultActionForCurrent() {
    guard let item = History.shared.unpinnedItems.first?.item ?? History.shared.all.first?.item else {
      NSSound.beep()
      return
    }
    runDefault(for: item)
  }

  // MARK: Per-action shortcuts

  // Wire (or rewire) the per-action hotkeys from the current rules. Safe to call
  // repeatedly: each Name's handler is registered once and re-resolves its config
  // at fire time, while `setShortcut` is updated to reflect the latest binding.
  // Never calls `removeAllHandlers()` (that would clobber popup/pin/etc.).
  func registerShortcuts() {
    for rule in Defaults[.actionRules] {
      for config in rule.actions {
        let name = KeyboardShortcuts.Name("action_\(config.id.uuidString)")
        if let spec = config.shortcut, let parsed = ShortcutSpec.parse(spec) {
          KeyboardShortcuts.setShortcut(parsed, for: name)
        } else {
          KeyboardShortcuts.setShortcut(nil, for: name)
        }
        if registeredActionShortcutNames.insert(name.rawValue).inserted {
          let actionID = config.id
          KeyboardShortcuts.onKeyDown(for: name) {
            ActionEngine.shared.runSpecificActionForCurrent(actionID: actionID)
          }
        }
      }
    }
  }

  // Re-read rules from disk after a headless CLI process mutated them, then
  // rewire shortcuts. `CFPreferencesAppSynchronize` defeats the in-memory
  // UserDefaults cache so `rules` (computed from `Defaults`) sees the fresh
  // value on the next copy automatically.
  func reloadRules() {
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    registerShortcuts()
  }

  // Per-action-shortcut entry point: run one specific action unconditionally on
  // the most recent item. No rule matching, no priority, no auto-run gate.
  func runSpecificActionForCurrent(actionID: UUID) {
    guard let config = Defaults[.actionRules].flatMap(\.actions).first(where: { $0.id == actionID }),
          let action = ActionFactory.make(config),
          let item = History.shared.unpinnedItems.first?.item ?? History.shared.all.first?.item,
          action.canRun(on: item) else {
      NSSound.beep()
      return
    }
    run(action, on: item)
  }

  // MARK: Auto-run (called from Clipboard.onNewCopy)

  func handleNewCopy(_ item: HistoryItem) {
    // Skip anything Maccy itself put on the clipboard (e.g. selecting an item to
    // paste it). Without this, pasting a URL would auto-open it and steal focus
    // from the paste target instead of pasting.
    guard !item.fromMaccy else { return }

    let text = ValueClassifier.primaryString(of: item)

    // Swallow the echo of a value we just produced via an auto transform
    // (Clipboard.copy(string) doesn't set the fromMaccy marker).
    if let last = lastAutoOutput, last == text {
      lastAutoOutput = nil
      return
    }

    for rule in matchingRules(for: item) where rule.autoRunDefault {
      guard let config = rule.actions.first,
            let action = ActionFactory.make(config),
            action.canRun(on: item) else { continue }
      run(action, on: item)
      break // only the first matching auto-run rule
    }
  }

  func noteAutoOutput(_ value: String) {
    lastAutoOutput = value
  }
}
