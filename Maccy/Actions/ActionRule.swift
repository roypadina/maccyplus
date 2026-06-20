import AppKit
import Defaults
import Foundation

// What an action does. `sendToAndroid` is reserved for the future clipboard-sync
// feature and is hidden/disabled in v1.
enum ActionType: String, Codable, CaseIterable, Identifiable {
  case openURL
  case openInApp
  case webSearch
  case transform
  case runShortcut
  case sendToAndroid

  var id: String { rawValue }

  var label: String {
    switch self {
    case .openURL: return "Open as URL"
    case .openInApp: return "Open in app"
    case .webSearch: return "Web search"
    case .transform: return "Transform text"
    case .runShortcut: return "Run Shortcut"
    case .sendToAndroid: return "Send to Android"
    }
  }

  var systemImage: String {
    switch self {
    case .openURL: return "safari"
    case .openInApp: return "app.badge"
    case .webSearch: return "magnifyingglass"
    case .transform: return "textformat"
    case .runShortcut: return "wand.and.stars"
    case .sendToAndroid: return "iphone"
    }
  }

  var isAvailable: Bool { true }

  static var available: [ActionType] { allCases.filter(\.isAvailable) }
}

enum TransformKind: String, Codable, CaseIterable, Identifiable {
  case trim
  case uppercase
  case lowercase
  case stripFormatting
  case unwrap

  var id: String { rawValue }

  var label: String {
    switch self {
    case .trim: return "Trim whitespace"
    case .uppercase: return "UPPERCASE"
    case .lowercase: return "lowercase"
    case .stripFormatting: return "Strip formatting"
    case .unwrap: return "Unwrap (join wrapped lines)"
    }
  }
}

// A single condition tested against a clipboard value. A rule ANDs/ORs several.
enum RuleCondition: Codable, Identifiable, Hashable {
  case kind(ValueKind)
  case regex(String)
  case contains(String)
  case sourceApp(String) // bundle identifier
  case softWrapped
  case terminalSource

  var id: String {
    switch self {
    case .kind(let value): return "kind:\(value.rawValue)"
    case .regex(let value): return "regex:\(value)"
    case .contains(let value): return "contains:\(value)"
    case .sourceApp(let value): return "app:\(value)"
    case .softWrapped: return "softWrapped"
    case .terminalSource: return "terminalSource"
    }
  }

  // Tagged JSON form, so conditions are agent-authorable: {"type":…, "value":…}.
  // The decoder also accepts the legacy Swift-synthesized form ({"kind":{"_0":"url"}})
  // so existing stored rules survive the Codable change — Defaults decodes arrays
  // element-by-element and silently drops any element that fails, so a hard failure
  // would lose the user's rules rather than fall back to presets.
  private enum CodingKeys: String, CodingKey {
    case type, value
  }

  // Legacy synthesized layout: {"<caseName>": {"_0": <associated value>}}.
  private enum LegacyKey: String, CodingKey {
    case kind, regex, contains, sourceApp
  }
  private enum LegacyAssoc: String, CodingKey {
    case _0
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let type = try? container.decode(String.self, forKey: .type) {
      switch type {
      case "kind": self = .kind(try container.decode(ValueKind.self, forKey: .value))
      case "regex": self = .regex(try container.decode(String.self, forKey: .value))
      case "contains": self = .contains(try container.decode(String.self, forKey: .value))
      case "sourceApp": self = .sourceApp(try container.decode(String.self, forKey: .value))
      case "softWrapped": self = .softWrapped
      case "terminalSource": self = .terminalSource
      default:
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: "Unknown condition type: \(type)"
          )
        )
      }
      return
    }

    // Fall back to the legacy synthesized form.
    let legacy = try decoder.container(keyedBy: LegacyKey.self)
    if let assoc = try? legacy.nestedContainer(keyedBy: LegacyAssoc.self, forKey: .kind) {
      self = .kind(try assoc.decode(ValueKind.self, forKey: ._0))
    } else if let assoc = try? legacy.nestedContainer(keyedBy: LegacyAssoc.self, forKey: .regex) {
      self = .regex(try assoc.decode(String.self, forKey: ._0))
    } else if let assoc = try? legacy.nestedContainer(keyedBy: LegacyAssoc.self, forKey: .contains) {
      self = .contains(try assoc.decode(String.self, forKey: ._0))
    } else if let assoc = try? legacy.nestedContainer(keyedBy: LegacyAssoc.self, forKey: .sourceApp) {
      self = .sourceApp(try assoc.decode(String.self, forKey: ._0))
    } else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unrecognized RuleCondition payload"
        )
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .kind(let value):
      try container.encode("kind", forKey: .type)
      try container.encode(value, forKey: .value)
    case .regex(let value):
      try container.encode("regex", forKey: .type)
      try container.encode(value, forKey: .value)
    case .contains(let value):
      try container.encode("contains", forKey: .type)
      try container.encode(value, forKey: .value)
    case .sourceApp(let value):
      try container.encode("sourceApp", forKey: .type)
      try container.encode(value, forKey: .value)
    case .softWrapped:
      try container.encode("softWrapped", forKey: .type)
    case .terminalSource:
      try container.encode("terminalSource", forKey: .type)
    }
  }
}

enum MatchMode: String, Codable, CaseIterable, Identifiable {
  case all // AND
  case any // OR

  var id: String { rawValue }
  var label: String { self == .all ? "Match ALL conditions" : "Match ANY condition" }
}

// Persisted configuration for one action within a rule.
struct ActionConfig: Codable, Identifiable, Hashable {
  var id: UUID = UUID()
  var type: ActionType = .openURL
  var appBundleID: String?      // openInApp
  var searchTemplate: String?   // webSearch, e.g. https://www.google.com/search?q={query}
  var transform: TransformKind? // transform
  var shortcutName: String?     // runShortcut
  var shortcut: String?         // per-action keyboard shortcut, e.g. "cmd+shift+u"

  var title: String {
    switch type {
    case .openInApp:
      return appBundleID.map { "Open in \(Self.appName(for: $0))" } ?? "Open in app"
    case .transform:
      return transform?.label ?? "Transform text"
    case .runShortcut:
      return shortcutName.map { "Run “\($0)”" } ?? "Run Shortcut"
    default:
      return type.label
    }
  }

  static func appName(for bundleID: String) -> String {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      return url.deletingPathExtension().lastPathComponent
    }
    return bundleID
  }
}

// A user-defined rule: when its conditions match, its (ordered) actions become
// available. The first action is the default.
struct ActionRule: Codable, Identifiable, Hashable, Defaults.Serializable {
  var id: UUID = UUID()
  var name: String = "New rule"
  var enabled: Bool = true
  var matchMode: MatchMode = .all
  var conditions: [RuleCondition] = []
  var actions: [ActionConfig] = []
  var autoRunDefault: Bool = false

  static let presets: [ActionRule] = [
    ActionRule(
      name: "Open links",
      conditions: [.kind(.url)],
      actions: [
        ActionConfig(type: .openURL),
        ActionConfig(type: .webSearch, searchTemplate: WebSearchTemplate.google)
      ]
    ),
    ActionRule(
      name: "Email address",
      conditions: [.kind(.email)],
      actions: [ActionConfig(type: .openURL)]
    ),
    ActionRule(
      name: "Search selected text",
      conditions: [.kind(.text)],
      actions: [ActionConfig(type: .webSearch, searchTemplate: WebSearchTemplate.google)]
    ),
    ActionRule(
      name: "Unwrap terminal command",
      matchMode: .all,
      conditions: [.terminalSource, .softWrapped],
      actions: [ActionConfig(type: .transform, transform: .unwrap)],
      autoRunDefault: true
    )
  ]
}

enum WebSearchTemplate {
  static let google = "https://www.google.com/search?q={query}"
}
