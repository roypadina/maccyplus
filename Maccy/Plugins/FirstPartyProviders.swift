import Defaults
import Foundation

// MARK: - Condition providers

/// Evaluates whether the clipboard text shows a fixed-width soft-wrap signature.
/// Wraps `TextUnwrap.isSoftWrapped(_:)` byte-for-byte.
@MainActor
struct SoftWrapCondition: ConditionProvider {
  let descriptor = ProviderDescriptor(
    id: "com.maccay.soft-wrap",
    name: "Soft-wrapped text",
    description: "Matches when the text looks like a terminal's fixed-width line wrap (all lines same length ≥ 40, last line shorter).",
    longHelp: "Uses the same heuristic as the built-in Unwrap action: every line except the last must share the same character count L ≥ 40, and the last line must be non-empty and no longer than L. Designed for auto-unwrapping pasted terminal commands.",
    kind: .condition,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func evaluate(_ input: PluginInput, params: JSONValue) throws -> Bool {
    TextUnwrap.isSoftWrapped(input.string)
  }
}

/// Evaluates whether the clipboard source app is a known terminal emulator.
/// Reads `Defaults[.terminalAppBundleIDs]` so user customisations are respected.
@MainActor
struct TerminalSourceCondition: ConditionProvider {
  let descriptor = ProviderDescriptor(
    id: "com.maccay.terminal-source",
    name: "Terminal source",
    description: "Matches when the text was copied from a terminal emulator (configurable list of bundle IDs in Settings → Actions → Terminal apps).",
    longHelp: "Checks the source app bundle ID against the persisted terminal-app list (Defaults key `terminalAppBundleIDs`). Defaults include Terminal, iTerm2, Warp, kitty, Alacritty, WezTerm, Ghostty, and VS Code. The list is user-editable via `maccay rules terminals`.",
    kind: .condition,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func evaluate(_ input: PluginInput, params: JSONValue) throws -> Bool {
    guard let app = input.sourceAppBundleID else { return false }
    return Defaults[.terminalAppBundleIDs].contains(app)
  }
}

// MARK: - Transform action providers

/// Removes leading and trailing whitespace and newlines.
@MainActor
struct TrimAction: ActionProvider {
  let descriptor = ProviderDescriptor(
    id: "com.maccay.trim",
    name: "Trim whitespace",
    description: "Removes leading and trailing whitespace and newlines from the clipboard text.",
    longHelp: nil,
    kind: .action,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard !input.string.isEmpty else { throw ActionError.noValue }
    return .replace(input.string.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

/// Converts all characters to uppercase.
@MainActor
struct UppercaseAction: ActionProvider {
  let descriptor = ProviderDescriptor(
    id: "com.maccay.uppercase",
    name: "UPPERCASE",
    description: "Converts the clipboard text to uppercase.",
    longHelp: nil,
    kind: .action,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard !input.string.isEmpty else { throw ActionError.noValue }
    return .replace(input.string.uppercased())
  }
}

/// Converts all characters to lowercase.
@MainActor
struct LowercaseAction: ActionProvider {
  let descriptor = ProviderDescriptor(
    id: "com.maccay.lowercase",
    name: "lowercase",
    description: "Converts the clipboard text to lowercase.",
    longHelp: nil,
    kind: .action,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard !input.string.isEmpty else { throw ActionError.noValue }
    return .replace(input.string.lowercased())
  }
}

/// Returns the plain-string representation (already stripped of rich formatting
/// by the time `PluginInput.string` is populated from `ValueClassifier.primaryString`).
@MainActor
struct StripFormattingAction: ActionProvider {
  let descriptor = ProviderDescriptor(
    id: "com.maccay.strip-formatting",
    name: "Strip formatting",
    description: "Strips rich text formatting from the clipboard, leaving only plain text.",
    longHelp: "The clipboard string passed to the provider is already the plain-text representation extracted from HTML/RTF by Maccy's history engine. Replacing the clipboard with this value effectively strips all rich formatting.",
    kind: .action,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard !input.string.isEmpty else { throw ActionError.noValue }
    // input.string is already the plain-string representation; re-copying it strips formatting.
    return .replace(input.string)
  }
}

/// Joins soft-wrapped lines into a single line via `TextUnwrap.unwrap(_:)`.
@MainActor
struct UnwrapAction: ActionProvider {
  let descriptor = ProviderDescriptor(
    id: "com.maccay.unwrap",
    name: "Unwrap (join wrapped lines)",
    description: "Joins soft-wrapped terminal output into a single line. Detects fixed-width wraps and collapses all newlines; otherwise joins lines with spaces.",
    longHelp: "Uses `TextUnwrap.unwrap`: if the text passes the soft-wrap heuristic (all interior lines same length ≥ 40), newlines are deleted exactly, reconstructing the original one-liner. Otherwise each newline boundary (plus surrounding whitespace) is collapsed to a single space.",
    kind: .action,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard !input.string.isEmpty else { throw ActionError.noValue }
    return .replace(TextUnwrap.unwrap(input.string))
  }
}

/// Re-maps text between US-QWERTY and Israeli SI-1452 keyboard layouts.
@MainActor
struct FixKeyboardLayoutAction: ActionProvider {
  let descriptor = ProviderDescriptor(
    id: "com.maccay.fix-keyboard-layout",
    name: "Fix keyboard layout (EN ⇄ HE)",
    description: "Corrects text typed in the wrong keyboard layout by re-mapping between US-QWERTY and Israeli SI-1452. Direction is auto-detected by script count.",
    longHelp: "Counts Hebrew scalars (U+0590–U+05FF) vs Latin letters. If Hebrew > Latin the HE→EN table is applied; otherwise the EN→HE table is applied (including on ties and all-Latin input). Unmapped characters pass through unchanged. Bracket pairs that differ between LTR and RTL contexts are also swapped.",
    kind: .action,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard !input.string.isEmpty else { throw ActionError.noValue }
    return .replace(KeyboardLayoutFixer.fix(input.string))
  }
}

// MARK: - Registration

/// Registers all first-party providers into the given registry.
/// Called at boot time by `ActionEngine` (after A5 lands).
enum FirstPartyProviders {
  @MainActor
  static func registerFirstParty(into registry: ProviderRegistry) {
    registry.register(condition: SoftWrapCondition())
    registry.register(condition: TerminalSourceCondition())
    registry.register(action: TrimAction())
    registry.register(action: UppercaseAction())
    registry.register(action: LowercaseAction())
    registry.register(action: StripFormattingAction())
    registry.register(action: UnwrapAction())
    registry.register(action: FixKeyboardLayoutAction())
  }
}
