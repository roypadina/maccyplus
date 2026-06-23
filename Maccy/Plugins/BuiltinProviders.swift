import AppKit
import Defaults
import Foundation

// MARK: - Launch seam

/// Injectable launch seam so unit tests can capture launches instead of performing them.
@MainActor enum BuiltinLaunch {
  static var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
  static var openInApp: (_ fileOrURL: URL, _ appURL: URL) -> Void = { fileOrURL, appURL in
    _ = try? NSWorkspace.shared.open(
      [fileOrURL],
      withApplicationAt: appURL,
      configuration: NSWorkspace.OpenConfiguration()
    )
  }
}

// MARK: - Condition providers

/// Matches when the clipboard value is classified as the specified ValueKind.
struct KindCondition: ConditionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.kind",
    name: "Value kind",
    description: "Matches when the clipboard value is the given kind: URL, email, phone, file path, color hex, image, or plain text.",
    longHelp: "Uses NSDataDetector and content inspection to classify the clipboard value. Select the kind from the picker. A single item can match multiple kinds — for example, a URL also matches 'text'.",
    kind: .condition,
    engine: .native,
    params: [
      ParamSpec(
        key: "kind",
        label: "Kind",
        kind: .valueKind,
        placeholder: "url"
      )
    ],
    capabilities: [],
    source: .builtin
  )

  func evaluate(_ input: PluginInput, params: JSONValue) throws -> Bool {
    guard let kindString = params["kind"]?.stringValue else {
      throw BuiltinProviderError.missingParam("kind")
    }
    guard let kind = ValueKind(rawValue: kindString) else {
      throw BuiltinProviderError.invalidParam("kind", value: kindString)
    }
    return input.kinds.contains(kind)
  }
}

/// Matches when the clipboard text matches a regular expression pattern.
struct RegexCondition: ConditionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.regex",
    name: "Regex match",
    description: "Matches when the clipboard text matches the given regular expression (ICU, case-sensitive).",
    longHelp: "Uses NSRegularExpression (ICU syntax). An empty or invalid pattern never matches. The match is applied to the full text — use anchors (^ $) to constrain position.",
    kind: .condition,
    engine: .native,
    params: [
      ParamSpec(
        key: "pattern",
        label: "Pattern",
        kind: .text,
        placeholder: "^https?://"
      )
    ],
    capabilities: [],
    source: .builtin
  )

  func evaluate(_ input: PluginInput, params: JSONValue) throws -> Bool {
    guard let pattern = params["pattern"]?.stringValue, !pattern.isEmpty else {
      return false
    }
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return false
    }
    let range = NSRange(input.string.startIndex..., in: input.string)
    return regex.firstMatch(in: input.string, range: range) != nil
  }
}

/// Matches when the clipboard text contains a substring (case-insensitive).
struct ContainsCondition: ConditionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.contains",
    name: "Contains text",
    description: "Matches when the clipboard text contains the given substring (case-insensitive, locale-aware).",
    longHelp: "Uses localizedCaseInsensitiveContains. An empty needle never matches.",
    kind: .condition,
    engine: .native,
    params: [
      ParamSpec(
        key: "needle",
        label: "Text",
        kind: .text,
        placeholder: "search term"
      )
    ],
    capabilities: [],
    source: .builtin
  )

  func evaluate(_ input: PluginInput, params: JSONValue) throws -> Bool {
    guard let needle = params["needle"]?.stringValue, !needle.isEmpty else {
      return false
    }
    return input.string.localizedCaseInsensitiveContains(needle)
  }
}

/// Matches when the clipboard was copied from the specified application (by bundle ID).
struct SourceAppCondition: ConditionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.sourceApp",
    name: "Source application",
    description: "Matches when the clipboard was copied from the application with the given bundle identifier.",
    longHelp: "Compares the bundle ID of the frontmost app at copy time. A missing or empty bundle ID never matches. Use the bundle identifier exactly as it appears in the app's Info.plist.",
    kind: .condition,
    engine: .native,
    params: [
      ParamSpec(
        key: "bundleID",
        label: "Bundle ID",
        kind: .bundleID,
        placeholder: "com.apple.Safari"
      )
    ],
    capabilities: [],
    source: .builtin
  )

  func evaluate(_ input: PluginInput, params: JSONValue) throws -> Bool {
    guard let bundleID = params["bundleID"]?.stringValue, !bundleID.isEmpty else {
      return false
    }
    return input.sourceAppBundleID == bundleID
  }
}

// MARK: - Action providers

/// Opens the clipboard text as a URL in the default browser or associated app.
struct OpenURLProvider: ActionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.openURL",
    name: "Open as URL",
    description: "Opens the clipboard text as a URL. Bare text gets https://, emails get mailto:. No parameters required.",
    longHelp: "Builds an openable URL from the clipboard text: if a scheme is already present it is used as-is; text containing '@' becomes a mailto: URL; otherwise https:// is prepended. Fails if the text contains spaces or cannot form a valid URL.",
    kind: .action,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard let url = makeURL(from: input.string) else {
      throw ActionError.invalidURL
    }
    BuiltinLaunch.open(url)
    return .sideEffect
  }
}

/// Opens the clipboard content in a specific application identified by bundle ID.
struct OpenInAppProvider: ActionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.openInApp",
    name: "Open in app",
    description: "Opens the clipboard content in the application with the given bundle ID. Works with URLs and file paths.",
    longHelp: "Resolves the application URL via NSWorkspace. If the clipboard contains file URLs they are opened directly; otherwise the text is converted to a URL and passed to the app. Fails if the application is not installed.",
    kind: .action,
    engine: .native,
    params: [
      ParamSpec(
        key: "bundleID",
        label: "Application",
        kind: .bundleID,
        placeholder: "com.apple.Safari"
      )
    ],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard let bundleID = params["bundleID"]?.stringValue, !bundleID.isEmpty else {
      throw ActionError.missingApp
    }
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      throw ActionError.missingApp
    }
    let urls: [URL]
    if !input.fileURLs.isEmpty {
      urls = input.fileURLs
    } else if let url = makeURL(from: input.string) {
      urls = [url]
    } else {
      throw ActionError.noValue
    }
    for url in urls {
      BuiltinLaunch.openInApp(url, appURL)
    }
    return .sideEffect
  }
}

/// Performs a web search for the clipboard text using a configurable URL template.
struct WebSearchProvider: ActionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.webSearch",
    name: "Web search",
    description: "Searches the clipboard text using a URL template. Use {query} as the placeholder for the percent-encoded search term.",
    longHelp: "Percent-encodes the clipboard text and substitutes it into the template at {query}, then opens the resulting URL. The default template is Google search. Fails if the clipboard text is empty.",
    kind: .action,
    engine: .native,
    params: [
      ParamSpec(
        key: "template",
        label: "Search URL",
        kind: .text,
        placeholder: WebSearchTemplate.google
      )
    ],
    capabilities: [],
    source: .builtin
  )

  /// Builds the final search URL by percent-encoding `query` and substituting
  /// it into `template` at the `{query}` placeholder. Returns `nil` when the
  /// resulting string cannot be parsed as a URL with a scheme.
  static func buildSearchURL(template: String, query: String) -> URL? {
    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    let urlString = template.replacingOccurrences(of: "{query}", with: encoded)
    guard let url = URL(string: urlString), url.scheme != nil else { return nil }
    return url
  }

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard !input.string.isEmpty else { throw ActionError.noValue }
    let template = params["template"]?.stringValue ?? WebSearchTemplate.google
    guard let url = WebSearchProvider.buildSearchURL(template: template, query: input.string) else {
      throw ActionError.invalidURL
    }
    BuiltinLaunch.open(url)
    return .sideEffect
  }
}

/// Runs a named Apple Shortcut with the clipboard text as input.
struct RunShortcutProvider: ActionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.runShortcut",
    name: "Run Shortcut",
    description: "Runs the named shortcut from Shortcuts.app, passing the clipboard text as plain-text input.",
    longHelp: "Opens the shortcuts://run-shortcut URL with the shortcut name and clipboard text. The shortcut must exist in Shortcuts.app. The clipboard is not modified by this action.",
    kind: .action,
    engine: .native,
    params: [
      ParamSpec(
        key: "shortcutName",
        label: "Shortcut name",
        kind: .text,
        placeholder: "My Shortcut"
      )
    ],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard let name = params["shortcutName"]?.stringValue, !name.isEmpty else {
      throw ActionError.missingShortcut
    }
    var components = URLComponents()
    components.scheme = "shortcuts"
    components.host = "run-shortcut"
    components.queryItems = [
      URLQueryItem(name: "name", value: name),
      URLQueryItem(name: "input", value: "text"),
      URLQueryItem(name: "text", value: input.string)
    ]
    guard let url = components.url else { throw ActionError.missingShortcut }
    BuiltinLaunch.open(url)
    return .sideEffect
  }
}

// MARK: - Registration

enum BuiltinProviders {
  /// Registers all eight built-in native providers into `registry`.
  /// Call once at boot (from `ActionEngine.init`) before any rule evaluation.
  @MainActor
  static func registerBuiltins(into registry: ProviderRegistry) {
    registry.register(condition: KindCondition())
    registry.register(condition: RegexCondition())
    registry.register(condition: ContainsCondition())
    registry.register(condition: SourceAppCondition())
    registry.register(action: OpenURLProvider())
    registry.register(action: OpenInAppProvider())
    registry.register(action: WebSearchProvider())
    registry.register(action: RunShortcutProvider())
  }
}

// MARK: - Internal errors

enum BuiltinProviderError: Error, Equatable {
  case missingParam(String)
  case invalidParam(String, value: String)
}
