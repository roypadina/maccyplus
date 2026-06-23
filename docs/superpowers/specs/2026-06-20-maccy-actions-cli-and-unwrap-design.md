# Maccy Actions: Unwrap soft-wrapped commands + agent-driven CLI control

Date: 2026-06-20
Branch: `maccy-actions`
Bundle id: `com.royp.MaccyActions`

## Summary

Two features layered onto the existing rules/actions framework (`Maccy/Actions/`):

1. **Unwrap soft-wrapped commands** — a new `unwrap` transform that strips terminal
   soft-wrap line breaks from a copied command so it pastes as a single ready-to-use
   line. Fires automatically when a copy from a terminal app shows the char-wrap
   signature, and can be bound to a per-action keyboard shortcut.
2. **Agent-driven CLI control + skill** — a headless CLI mode in the Maccy binary that
   gives full CRUD over rules, the terminal-app list, and per-action shortcuts (JSON in/out),
   plus a repo skill teaching other agents how to use it. No GUI, no recompile.

These share one domain, so they ship together; the skill's worked example creates the
unwrap rule via the CLI, dogfooding both.

## Background (current architecture — verbatim facts)

- Rules persist in `Defaults[.actionRules]: [ActionRule]` (sindresorhus `Defaults`,
  JSON-serialized in UserDefaults under key `actionRules`). Default = `ActionRule.presets`.
- `RuleCondition` enum: `.kind(ValueKind)`, `.regex(String)`, `.contains(String)`,
  `.sourceApp(String)`. Currently uses Swift-synthesized Codable.
- `ActionConfig` struct: `id`, `type: ActionType`, `appBundleID?`, `searchTemplate?`,
  `transform: TransformKind?`, `shortcutName?`. Named fields → already clean JSON.
- `ActionType`: openURL, openInApp, webSearch, transform, runShortcut.
- `TransformKind`: trim, uppercase, lowercase, stripFormatting.
- `ActionEngine` (`@MainActor @Observable`): `rules` is computed `{ Defaults[.actionRules] }`;
  `matches()` evaluates conditions; `handleNewCopy()` auto-runs the first matching
  `autoRunDefault` rule's first action; echo-loop guarded via `lastAutoOutput`/`noteAutoOutput`.
- Global shortcut `runDefaultAction` (sindresorhus `KeyboardShortcuts`, no default binding)
  → `runDefaultActionForCurrent()`. Registered in `AppDelegate.applicationWillFinishLaunching`
  (`KeyboardShortcuts.onKeyDown(for: .runDefaultAction)`). Other shortcut names
  (popup/pin/delete/togglePreview) live in
  `Extensions/KeyboardShortcuts.Name+Shortcuts.swift`.
- App entry: `MaccyApp` is a SwiftUI `@main` App with `MenuBarExtra`; `AppDelegate`
  via `@NSApplicationDelegateAdaptor`. `applicationWillFinishLaunching` parses
  `CommandLine.arguments` (only checks `enable-testing` today). No URL-scheme handling.
- Build: `Maccy.xcodeproj`, scheme `Maccy`, macOS app. Builds in seconds.

## Three independent trigger paths (final, non-overlapping)

1. **Auto-run** — `autoRunDefault` rules fire on copy, gated by rule matching.
2. **Global default shortcut** — existing `runDefaultAction`; runs the default action of the
   highest-priority matching rule for the most-recent clip. **Kept as-is.**
3. **Per-action shortcut** — runs one specific action unconditionally (no rule matching,
   no priority, no auto-run gate). Press → build that exact action → run on the most-recent
   clip (beep only if there is no value).

---

## Feature 1 — Unwrap

### 1a. `TextUnwrap` helper (new file `Maccy/Actions/TextUnwrap.swift`)

Shared by the `.softWrapped` condition and the `.unwrap` transform.

```swift
import Foundation

enum TextUnwrap {
  /// Minimum wrap width. Guards the weak 2-line case: a long first line + short
  /// remainder only counts as wrapped if the first line is near a real wrap width.
  static let minWrapWidth = 40

  /// True when the text shows a fixed-width char-wrap signature: every line except
  /// the last has the same length L >= minWrapWidth, and the last line is non-empty
  /// and no longer than L. This is the conservative gate for auto-firing.
  static func isSoftWrapped(_ text: String) -> Bool {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var lines = normalized.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() } // trailing newline
    guard lines.count >= 2 else { return false }
    let widths = Set(lines.dropLast().map { $0.count })
    guard widths.count == 1, let l = widths.first, l >= minWrapWidth else { return false }
    guard let last = lines.last, !last.isEmpty, last.count <= l else { return false }
    return true
  }

  /// Join a wrapped command into one line.
  /// - Char-wrap signature → delete newlines (exact reconstruction, no spurious spaces).
  /// - Otherwise → collapse each newline run (+ surrounding whitespace) to one space.
  static func unwrap(_ text: String) -> String {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let result: String
    if isSoftWrapped(normalized) {
      result = normalized.replacingOccurrences(of: "\n", with: "")
    } else {
      result = normalized
        .components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .joined(separator: " ")
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
```

### 1b. `TransformKind.unwrap`

Add `case unwrap` to `TransformKind` with `label = "Unwrap (join wrapped lines)"`.
In `TransformAction.run`, add the case:

```swift
case .unwrap: result = TextUnwrap.unwrap(value)
```

`value` is `ValueClassifier.primaryString(of: item)` (trimmed ends, internal newlines
preserved) — correct for unwrap. Keep the existing `noteAutoOutput(result)` +
`Clipboard.shared.copy(result)`.

### 1c. New conditions `.softWrapped`, `.terminalSource`

Add both cases to `RuleCondition` (see Feature 2c for the Codable form). Update `id`:
- `.softWrapped` → `"softWrapped"`
- `.terminalSource` → `"terminalSource"`

In `ActionEngine.matches`:
```swift
case .softWrapped:
  return TextUnwrap.isSoftWrapped(text)
case .terminalSource:
  return app.map { Defaults[.terminalAppBundleIDs].contains($0) } ?? false
```

### 1d. Editable terminal-app list

New file `Maccy/Actions/TerminalApps.swift`:
```swift
enum TerminalApps {
  static let defaults: [String] = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "dev.warp.Warp-Stable",
    "net.kovidgoyal.kitty",
    "org.alacritty",
    "com.github.wez.wezterm",
    "com.mitchellh.ghostty",
    "com.microsoft.VSCode",
  ]
}
```
New Defaults key (next to `actionRules`):
```swift
static let terminalAppBundleIDs = Key<[String]>("terminalAppBundleIDs", default: TerminalApps.defaults)
```
Editable from GUI (Feature 1 GUI) and CLI (`terminals` subcommand).

### 1e. Preset rule

Append to `ActionRule.presets`:
```swift
ActionRule(
  name: "Unwrap terminal command",
  matchMode: .all,
  conditions: [.terminalSource, .softWrapped],
  actions: [ActionConfig(type: .transform, transform: .unwrap)],
  autoRunDefault: true
)
```

---

## Feature 1.5 — Per-action shortcuts

- New field on `ActionConfig`: `var shortcut: String?` — a human spec, e.g. `"cmd+shift+u"`.
  Source of truth lives in the rule (so export/import and CLI carry it).
- New `Maccy/Actions/ShortcutSpec.swift`: `parse(_ String) -> KeyboardShortcuts.Shortcut?`
  and `format(_ KeyboardShortcuts.Shortcut) -> String`. Grammar: `+`-joined tokens;
  modifiers `cmd|command|⌘`, `shift|⇧`, `opt|option|alt|⌥`, `ctrl|control|⌃`; final token is
  the key (letter, digit, or named key like `space`, `return`, `delete`, `f1`…). Case-insensitive.
- `ActionEngine.registerShortcuts()` (new): the single place that wires all hotkeys.
  Call `KeyboardShortcuts.removeAllHandlers()` then re-register:
  - the global `runDefaultAction` handler (preserve existing behavior),
  - for each action across all rules that has a non-nil `shortcut`: derive
    `KeyboardShortcuts.Name("action_\(config.id.uuidString)")`, `setShortcut(parsed, for: name)`,
    and `onKeyDown(for: name) { ActionEngine.shared.runSpecificActionForCurrent(config) }`.
- `ActionEngine.runSpecificActionForCurrent(_ config: ActionConfig)` (new): build the action
  via `ActionFactory.make(config)`, take the most-recent clip
  (`History.shared.unpinnedItems.first?.item ?? History.shared.all.first?.item`), and run it —
  **no rule matching**. Beep if no action or no value.
- Call `registerShortcuts()` from `AppDelegate.applicationWillFinishLaunching` (after the
  existing `runDefaultAction` wiring is moved into it) and from `reloadRules()` (Feature 2b).
- GUI: a `KeyboardShortcuts.Recorder(for:)` per action in the rule editor; on change, mirror
  the recorded value back into `ActionConfig.shortcut` (via `ShortcutSpec.format`) and re-run
  `registerShortcuts()`.

---

## Feature 2 — CLI control surface + skill

### 2a. Headless CLI mode

Replace `@main` on `MaccyApp` with `Maccy/main.swift`:
```swift
import Foundation

let args = CommandLine.arguments
if args.count > 1, ["rules", "terminals"].contains(args[1]) {
  exit(ActionsCLI.run(Array(args.dropFirst())))
}
MaccyApp.main()
```
Remove `@main` from `MaccyApp` (keep the struct + `static func main()` available — a
SwiftUI `App` gets `main()` automatically). Runs as a short-lived second process of the
same bundle; reads/writes the shared `Defaults` domain; never starts the GUI.

`Maccy/Actions/ActionsCLI.swift` — `enum ActionsCLI { static func run(_ args: [String]) -> Int32 }`:

```
Maccy rules list                         # JSON array of all rules
Maccy rules get <id>                     # one rule JSON
Maccy rules add   (--json '…' | --file f | stdin)   # create; prints new id
Maccy rules update <id> (--json '…' | --file f | stdin)
Maccy rules remove <id>
Maccy rules move <id> <index>            # reorder (priority = order)
Maccy rules enable <id> | disable <id>
Maccy rules import (--file f | stdin)    # replace ALL rules
Maccy rules export                       # all rules JSON (== list, stable)
Maccy rules describe                     # live schema catalog (see below)
Maccy terminals list | add <bundleid> | remove <bundleid> | reset
```

Rules:
- All output is JSON (pretty) to stdout; errors to stderr; exit 0 ok / non-zero on error.
- **Validate before write**: decode the rule; enforce per-type required fields
  (`transform` set when `type==transform`; `appBundleID` for openInApp; `searchTemplate` for
  webSearch; `shortcutName` for runShortcut; `shortcut` parses if present); reject regex that
  won't compile. On invalid input, print the reason to stderr and exit 1 without mutating.
- `add` accepts a rule without `id` (generate) and with partial fields (defaults applied).
- `describe` emits a catalog object: `valueKinds` (ValueKind.allCases), `actionTypes`
  (ActionType.allCases + required fields per type), `transformKinds`, `matchModes`,
  `conditionTypes` (the tagged forms + which carry a `value`), `shortcutGrammar`,
  `defaultTerminalApps`. Built from the live enums so it cannot drift from code.
- After any mutation, post the live-reload notification (2b).

### 2b. Live reload (cross-process — primary risk, verify live)

- Shared constant (e.g. in `ActionsCLI.swift` or a small `Notifications.swift`):
  `let rulesChangedNotification = "com.royp.MaccyActions.rulesChanged"`.
- CLI, after a successful mutation:
  `DistributedNotificationCenter.default().postNotificationName(.init(rulesChangedNotification), object: nil, deliverImmediately: true)`.
- GUI (`AppDelegate.applicationWillFinishLaunching`): observe it on
  `DistributedNotificationCenter.default()` → on `@MainActor`, call
  `ActionEngine.shared.reloadRules()`.
- `ActionEngine.reloadRules()`:
  `CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)` to defeat the in-memory
  UserDefaults cache, then `registerShortcuts()`, then nudge any Observable state so open
  SwiftUI views refresh. Because `rules` is computed from `Defaults`, auto-run picks up the
  fresh value on the next copy automatically.
- If the GUI is not running, the change is on disk and is read on next launch.
- **VERIFY:** with the GUI running, `Maccy rules add …` from a terminal, then confirm the
  engine sees it (new rule auto-runs / per-action shortcut becomes live). If
  `CFPreferencesAppSynchronize` proves insufficient, fall back to re-reading via the
  `Defaults` API after a forced suite re-init, or have `reloadRules()` assign
  `Defaults[.actionRules] = Defaults[.actionRules]`. Settle this empirically.

### 2c. Clean `RuleCondition` Codable

Custom Codable so conditions are agent-authorable. Encoded form is tagged:
```json
{"type":"kind","value":"url"}
{"type":"regex","value":"^npm "}
{"type":"contains","value":"docker"}
{"type":"sourceApp","value":"com.apple.Terminal"}
{"type":"softWrapped"}
{"type":"terminalSource"}
```
Encoder writes this; decoder reads this. **Legacy tolerance is not required**: old
synthesized-format data that fails to decode makes the `Defaults` library fall back to the
default (`presets`) — acceptable on this dev branch. (Document this; do not crash.)

### 2d. Skill (`.claude/skills/maccy-actions/SKILL.md` — repo has no `.claude/` yet)

Frontmatter `name` + `description` with triggers (configure/create/edit Maccy rules or
actions, build a Maccy action, set up an auto-transform, add a per-action shortcut, etc.).
Body teaches agents:
- locate the binary (bundle id `com.royp.MaccyActions`; resolve the app path via
  `mdfind "kMDItemCFBundleIdentifier == 'com.royp.MaccyActions'"` →
  `<app>/Contents/MacOS/Maccy`), and that the GUI auto-reloads after CLI writes;
- the JSON schema for rules / conditions / actions / shortcuts, sourced from
  `Maccy rules describe` (tell agents to run it for the live catalog);
- every command with copy-paste examples;
- validation rules and exit-code behavior;
- recipes: create the unwrap rule end-to-end; add a regex/contains rule; assign a per-action
  shortcut; manage the terminal-app list.

---

## Implementation plan (phased; build after each; commit per phase)

**Phase 1 — Core model + engine.** `TextUnwrap.swift`, `TerminalApps.swift`,
`RuleCondition` tagged Codable + `.softWrapped`/`.terminalSource` (+ `id`), `TransformKind.unwrap`
+ `TransformAction` case, `ActionConfig.shortcut`, `Defaults[.terminalAppBundleIDs]`,
`ActionEngine.matches` cases, preset rule. Verify: `build_macos` green.

**Phase 2 — Shortcuts runtime.** `ShortcutSpec.swift`, `ActionEngine.registerShortcuts()` +
`runSpecificActionForCurrent()`, move global `runDefaultAction` wiring into
`registerShortcuts()`, call it from `AppDelegate`. Verify: build green.

**Phase 3 — CLI mode + live reload.** `main.swift` (+ drop `@main`), `ActionsCLI.swift`
(all subcommands, validation, describe), distributed-notification post + observer,
`ActionEngine.reloadRules()`. Verify: build green; run `rules list/describe/add/remove`
and `terminals` from a terminal; live-reload test against the running GUI.

**Phase 4 — GUI.** `ActionsSettingsPane`/`RuleEditor`: condition rows for `.softWrapped`
(static) and `.terminalSource` (static + link to terminal list), per-action shortcut
recorder, terminal-app list editor (add/remove). Verify: build green; launch + eyeball.

**Phase 5 — Skill.** Write `.claude/skills/maccy-actions/SKILL.md`. Verify: content review +
the `describe` output it references actually matches.

**Phase 6 — Dogfood + final.** Confirm the unwrap preset works end-to-end (auto-run on a
wrapped terminal copy; per-action shortcut), and that creating an equivalent rule via the CLI
behaves identically. Final clean build + launch.

## Risks / decisions

- **Cross-process live reload (2b)** is the main unknown — verified live in Phase 3, not assumed.
- **`L >= 40`** hardcoded; can be exposed later.
- **Word-wrap terminals** won't auto-trigger (signature is char-wrap); the per-action shortcut
  handles them via the space-join branch.
- **Condition Codable change** resets any pre-existing non-tagged stored rules to presets on
  first run (dev branch only; acceptable).
- Per-action shortcut lives on `ActionConfig` (per-action, as requested), not per-rule.
- Global `runDefaultAction` shortcut is preserved; per-action shortcuts are independent.
