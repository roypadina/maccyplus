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
  /// Folder → open its own Finder window; file → open the parent and select it.
  /// The sandbox has no read access to arbitrary paths, so Launch Services refuses
  /// to open folders (-54); Finder is asked directly via Apple Events instead
  /// (entitlement: temporary-exception.apple-events → com.apple.finder). Revealing
  /// needs no file access, so it doubles as the fallback.
  static var reveal: (URL) -> Void = { url in
    if url.hasDirectoryPath, openViaFinder(url) { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  /// Opens a path with its default app. Launch Services handles files; folders
  /// need Finder (Launch Services answers -54 for a directory the sandbox cannot
  /// read). Finder is the fallback, but it can only open a *folder* for us — it
  /// refuses a file it got no sandbox extension for ("does not have permission
  /// to open …").
  static var openFile: (URL) -> Void = { url in
    if !url.hasDirectoryPath, NSWorkspace.shared.open(url) { return }
    if openViaFinder(url) { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  /// Asks Finder to open `url`: a file launches in its default app, a folder
  /// opens its own window.
  private static func openViaFinder(_ url: URL) -> Bool {
    let quoted = url.path
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    let source = """
      tell application "Finder"
        open POSIX file "\(quoted)"
        activate
      end tell
      """
    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)
    return error == nil
  }
}

// MARK: - Condition providers

/// Matches when the clipboard value is classified as the specified ValueKind.
struct KindCondition: ConditionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.kind",
    name: "Value kind",
    description: "Matches when the copied item is a specific type — URL, email, phone number, file path, color, image, or text.",
    longHelp: "Choose a kind from the picker. The rule matches when the clipboard item belongs to that kind. One item can be several kinds at once — a web address is both a URL and text, so it matches either.",
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
    // The editor's picker shows "URL" until another kind is picked and saves nothing, so unset = URL.
    let kindString = params["kind"]?.stringValue ?? ValueKind.url.rawValue
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
    description: "Matches when the copied text matches a regular expression pattern you provide.",
    longHelp: "Enter a regular expression in the Pattern field. The rule matches when the clipboard text fits the pattern anywhere in the text. Use ^ at the start and $ at the end of your pattern to require the whole text to match. An empty or invalid pattern never matches.",
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
    description: "Matches when the copied text contains the words you type — uppercase/lowercase doesn't matter.",
    longHelp: "Type any text in the Text field; the rule matches whenever the clipboard contains it, ignoring uppercase and lowercase differences. Leave it empty and it never matches.",
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
    description: "Matches when the text was copied from a specific app on your Mac.",
    longHelp: "Pick the app from the Application field (or type its identifier). The rule matches only when you copied the text while that app was in the foreground. If no app is selected, the rule never matches.",
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

/// Matches when the copied path exists on disk and is a file (or a folder).
struct PathTypeCondition: ConditionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.pathType",
    name: "Path type",
    description: "Matches when the copied local path is a file, or when it is a folder.",
    longHelp: "Pick File or Folder. The path is looked up on disk, so a path that does not exist matches neither. Pair it with the file path kind condition to split one rule into a file rule and a folder rule — for example open files in their app, but open folders in Finder.",
    kind: .condition,
    engine: .native,
    params: [
      ParamSpec(
        key: "type",
        label: "Path type",
        kind: .pathType,
        placeholder: PathType.file.rawValue
      )
    ],
    capabilities: [],
    source: .builtin
  )

  func evaluate(_ input: PluginInput, params: JSONValue) throws -> Bool {
    guard let raw = params["type"]?.stringValue else {
      throw BuiltinProviderError.missingParam("type")
    }
    guard let wanted = PathType(rawValue: raw) else {
      throw BuiltinProviderError.invalidParam("type", value: raw)
    }
    guard let url = RevealInFinderProvider.resolveFileURL(from: input) else { return false }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return false
    }
    return isDirectory.boolValue == (wanted == .folder)
  }
}

// MARK: - Action providers

/// Opens the clipboard text as a URL in the default browser or associated app.
struct OpenURLProvider: ActionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.openURL",
    name: "Open as URL",
    description: "Opens the copied text as a link. Web addresses open in your browser; email addresses open in your mail app.",
    longHelp: "No setup needed. If the copied text already looks like a link it opens as-is. Text that looks like an email address opens your mail app. Anything else is treated as a web address. Fails if the text cannot be turned into a valid link.",
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
    description: "Opens the copied text or file in a specific app you choose. Works with links and file paths.",
    longHelp: "Pick the app from the Application field. When the rule fires, the copied content is sent directly to that app — file paths open as files, links open as links. Fails if the chosen app is not installed on your Mac.",
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
    description: "Searches the web for the copied text. Uses Google by default; swap in any search engine URL.",
    longHelp: "The copied text is inserted into the Search URL at the {query} placeholder and the result opens in your browser. The default is a Google search. To use a different search engine, replace the URL with that engine's search URL and put {query} where the search terms go. Fails if the clipboard is empty.",
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

/// Reveals a copied local path in Finder: folders open, files get selected in their folder.
struct RevealInFinderProvider: ActionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.revealInFinder",
    name: "Reveal in Finder",
    description: "Shows the copied local path in Finder. Folders open; files are selected inside their folder.",
    longHelp: "No setup needed. Works with copied files and with plain-text paths such as /Users/me/Documents or ~/Downloads/report.pdf. A folder path opens that folder in Finder; a file path opens the containing folder with the file selected. Fails if the text is not a local path.",
    kind: .action,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  /// The real user home, even inside the app sandbox (where `NSHomeDirectory()`
  /// points at the container).
  static let realHome: String = {
    if let dir = getpwuid(getuid())?.pointee.pw_dir { return String(cString: dir) }
    return NSHomeDirectory()
  }()

  /// Copied file URLs win; otherwise the text must be an absolute, `~`-prefixed
  /// or `file://` path. Returns `nil` for anything else (URLs, plain text).
  static func resolveFileURL(from input: PluginInput) -> URL? {
    if let url = input.fileURLs.first { return url }
    var path = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: path), url.isFileURL { return url }
    if path == "~" || path.hasPrefix("~/") { path = realHome + path.dropFirst() }
    guard path.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: path)
  }

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard let url = RevealInFinderProvider.resolveFileURL(from: input) else {
      throw ActionError.noValue
    }
    await MainActor.run { BuiltinLaunch.reveal(url) }
    return .sideEffect
  }
}

/// Opens a copied local path with its default app; folders open in Finder.
struct OpenFileProvider: ActionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.openFile",
    name: "Open file",
    description: "Opens the copied local path with its default app. Folder paths open in Finder.",
    longHelp: "No setup needed. Works with copied files and with plain-text paths such as /var/log/system.log or ~/Downloads/report.pdf. The file opens in whichever app macOS normally uses for it; a folder path opens that folder in Finder. Fails if the text is not a local path.",
    kind: .action,
    engine: .native,
    params: [],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    guard let url = RevealInFinderProvider.resolveFileURL(from: input) else {
      throw ActionError.noValue
    }
    await MainActor.run { BuiltinLaunch.openFile(url) }
    return .sideEffect
  }
}

/// Runs a named Apple Shortcut with the clipboard text as input.
struct RunShortcutProvider: ActionProvider {

  let descriptor = ProviderDescriptor(
    id: "builtin.runShortcut",
    name: "Run Shortcut",
    description: "Runs one of your Shortcuts (from the Shortcuts app), passing the copied text to it.",
    longHelp: "Type the exact name of the shortcut in the Shortcut name field — it must already exist in your Shortcuts app. The copied text is handed to the shortcut as its input. The clipboard itself is left unchanged after the shortcut runs.",
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

/// Publishes the clip to an ntfy topic on ntfy.sh or a self-hosted server: copied
/// files and images go as attachments (one message each), anything else as text.
struct NtfyProvider: ActionProvider {

  /// Sends one request and returns the HTTP status; a file URL is streamed as the body.
  /// Swapped in tests.
  static var send: (URLRequest, URL?) async throws -> Int = { request, file in
    let response = if let file {
      try await URLSession.shared.upload(for: request, fromFile: file).1
    } else {
      try await URLSession.shared.data(for: request).1
    }
    return (response as? HTTPURLResponse)?.statusCode ?? 0
  }

  let descriptor = ProviderDescriptor(
    id: "builtin.ntfy",
    name: "Send to ntfy",
    description: "Sends the copied text, file or image to an ntfy topic, on ntfy.sh or your own server.",
    longHelp: "Fill in the topic. Leave the server empty for ntfy.sh, or enter your own server's address. Title and tags are optional; tags are comma-separated, and emoji names such as warning or tada show as emoji. For a protected topic enter a username and password, or leave the username empty and put an access token (tk_…) in the password field. The password is kept in your Keychain. Copied files and images arrive as attachments, one message each; ntfy.sh accepts files up to 15 MB.",
    kind: .action,
    engine: .native,
    params: [
      ParamSpec(key: "server", label: "Server", kind: .text, placeholder: "Server (empty = https://ntfy.sh)"),
      ParamSpec(key: "topic", label: "Topic", kind: .text, placeholder: "Topic"),
      ParamSpec(key: "title", label: "Title", kind: .text, placeholder: "Title (optional)"),
      ParamSpec(key: "tags", label: "Tags", kind: .text, placeholder: "Tags, comma-separated (optional)"),
      ParamSpec(key: "username", label: "Username", kind: .text, placeholder: "Username (optional)"),
      ParamSpec(key: "password", label: "Password", kind: .secret, placeholder: "Password or token (optional)")
    ],
    capabilities: [],
    source: .builtin
  )

  func run(_ input: PluginInput, params: JSONValue) async throws -> ActionOutcome {
    do {
      for (request, file) in try Self.requests(for: input, params: params) {
        let status = try await Self.send(request, file)
        guard (200..<300).contains(status) else {
          throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "the server answered HTTP \(status)"])
        }
      }
    } catch {
      Notifier.notify(body: "Not sent to ntfy: \(error.localizedDescription)", sound: nil)
      throw error
    }
    Notifier.notify(body: "Sent to ntfy", sound: nil)
    return .sideEffect
  }

  /// Builds the publish requests; the URL is set only for file uploads.
  static func requests(for input: PluginInput, params: JSONValue) throws -> [(URLRequest, URL?)] {
    func param(_ key: String) -> String {
      (params[key]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let topic = param("topic")
    guard !topic.isEmpty else { throw BuiltinProviderError.missingParam("topic") }
    var server = param("server").isEmpty ? "https://ntfy.sh" : param("server")
    if !server.contains("://") { server = "https://" + server }
    guard var base = URLComponents(string: server),
          ["http", "https"].contains(base.scheme?.lowercased() ?? ""),
          base.host?.isEmpty == false else {
      throw BuiltinProviderError.invalidParam("server", value: server)
    }
    var path = base.path
    while path.hasSuffix("/") { path.removeLast() }
    base.path = path + "/" + topic

    let username = param("username")
    let secret = SecretStore.resolve(params["password"]?.stringValue) ?? ""
    let authorization: String? = if !username.isEmpty {
      "Basic " + Data("\(username):\(secret)".utf8).base64EncodedString()
    } else if !secret.isEmpty {
      "Bearer \(secret)"
    } else {
      nil
    }
    let title = param("title")
    let tags = param("tags")

    func request(filename: String?) throws -> URLRequest {
      var components = base
      var items: [URLQueryItem] = []
      if !title.isEmpty { items.append(URLQueryItem(name: "title", value: title)) }
      if !tags.isEmpty { items.append(URLQueryItem(name: "tags", value: tags)) }
      if let filename { items.append(URLQueryItem(name: "filename", value: filename)) }
      components.queryItems = items.isEmpty ? nil : items
      // URLComponents leaves "+" alone, but the server would read it as a space.
      components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
      guard let url = components.url else { throw BuiltinProviderError.invalidParam("topic", value: topic) }
      var request = URLRequest(url: url)
      request.httpMethod = filename == nil ? "POST" : "PUT"
      request.setValue(authorization, forHTTPHeaderField: "Authorization")
      return request
    }

    if !input.fileURLs.isEmpty {
      return try input.fileURLs.map { (try request(filename: $0.lastPathComponent), $0) }
    }
    if let image = input.imageData() {
      var upload = try request(filename: "clipboard.png")
      upload.httpBody = NSBitmapImageRep(data: image)?.representation(using: .png, properties: [:]) ?? image
      return [(upload, nil)]
    }
    guard !input.string.isEmpty else { throw ActionError.noValue }
    var message = try request(filename: nil)
    message.httpBody = Data(input.string.utf8)
    return [(message, nil)]
  }
}

// MARK: - Secrets

/// Keychain store for `.secret` params: the rule keeps only a `keychain:<uuid>`
/// reference, so passwords never land in the prefs plist.
/// Items are created, read and deleted by Apple-signed `/usr/bin/security`, never `SecItemAdd`: with no
/// Team ID an item this app creates is tied to this build's cdhash, so every rebuild would ask for the
/// login password. A CLI-made item trusts the CLI (partition `apple-tool:`), so every build reads it silently.
// shortcut: deleting an action leaves its Keychain item behind; delete it with the action if they pile up.
enum SecretStore {
  static let prefix = "keychain:"
  private static let service = "MaccyPlus action secrets"

  /// A `keychain:` reference reads the Keychain; any other value (e.g. set via the CLI) is used as-is.
  static func resolve(_ value: String?) -> String? {
    guard let value, value.hasPrefix(prefix) else { return value }
    return read(account: String(value.dropFirst(prefix.count)))
  }

  static func read(account: String) -> String? {
    security(["find-generic-password", "-s", service, "-a", account, "-g"]).flatMap(password)
  }

  /// Replaces the stored secret; an empty one just deletes it.
  static func write(_ secret: String, account: String) {
    guard !secret.isEmpty else {
      _ = security(["delete-generic-password", "-s", service, "-a", account])
      return
    }
    // Secret goes in as hex on stdin, never argv: other users' `ps` can read argv.
    // shortcut: `security -i` truncates lines past ~4 KB (a ~2 KB secret); fine for passwords and tokens.
    let hex = Data(secret.utf8).map { String(format: "%02x", $0) }.joined()
    _ = security(["-i"], stdin: "add-generic-password -U -s \"\(service)\" -a \"\(account)\" -X \(hex)\n")
  }

  /// The `-g` stderr line: `password: "text"` when printable, `password: 0xHEX` otherwise.
  static func password(_ stderr: String) -> String? {
    guard let line = stderr.split(separator: "\n").last(where: { $0.hasPrefix("password: ") }) else { return nil }
    let value = line.dropFirst("password: ".count)
    if value.hasPrefix("0x") {
      let hex = Array(value.dropFirst(2).prefix(while: \.isHexDigit))
      guard hex.count % 2 == 0 else { return nil }
      let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { UInt8(String(hex[$0..<$0 + 2]), radix: 16) }
      return String(decoding: bytes, as: UTF8.self)
    }
    guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return nil }
    return String(value.dropFirst().dropLast())
  }

  /// Runs `/usr/bin/security`; its stderr on exit 0, nil otherwise (44 = not found).
  private static func security(_ args: [String], stdin: String? = nil) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = args
    let stderr = Pipe(), input = Pipe()
    process.standardError = stderr
    process.standardOutput = FileHandle.nullDevice
    if stdin != nil { process.standardInput = input }
    // Not `waitUntilExit()`: it spins the main run loop, and the Settings SecureField binding calls this
    // mid SwiftUI update, so the nested layout pass crashed AttributeGraph (abort in AG::Graph::value_set).
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    do { try process.run() } catch { return nil }
    if let stdin {
      input.fileHandleForWriting.write(Data(stdin.utf8))
      try? input.fileHandleForWriting.close()
    }
    let data = stderr.fileHandleForReading.readDataToEndOfFile()
    exited.wait()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
  }
}

// MARK: - Registration

enum BuiltinProviders {
  /// Registers all twelve built-in native providers into `registry`.
  /// Call once at boot (from `ActionEngine.init`) before any rule evaluation.
  @MainActor
  static func registerBuiltins(into registry: ProviderRegistry) {
    registry.register(condition: KindCondition())
    registry.register(condition: RegexCondition())
    registry.register(condition: ContainsCondition())
    registry.register(condition: SourceAppCondition())
    registry.register(condition: PathTypeCondition())
    registry.register(action: OpenURLProvider())
    registry.register(action: OpenInAppProvider())
    registry.register(action: WebSearchProvider())
    registry.register(action: RevealInFinderProvider())
    registry.register(action: OpenFileProvider())
    registry.register(action: RunShortcutProvider())
    registry.register(action: NtfyProvider())
  }
}

// MARK: - Internal errors

enum BuiltinProviderError: Error, Equatable {
  case missingParam(String)
  case invalidParam(String, value: String)
}

extension BuiltinProviderError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .missingParam(let key): "\(key) is empty"
    case .invalidParam(let key, let value): "\(key) \"\(value)\" is not valid"
    }
  }
}
