import XCTest
@testable import Maccy

@MainActor
final class BuiltinProvidersTests: XCTestCase {

  private var originalOpen: ((URL) -> Void)!
  private var originalOpenInApp: ((URL, URL) -> Void)!

  override func setUp() async throws {
    try await super.setUp()
    originalOpen = BuiltinLaunch.open
    originalOpenInApp = BuiltinLaunch.openInApp
    ProviderRegistry.shared.reset()
    BuiltinProviders.registerBuiltins(into: ProviderRegistry.shared)
  }

  override func tearDown() async throws {
    BuiltinLaunch.open = originalOpen
    BuiltinLaunch.openInApp = originalOpenInApp
    try await super.tearDown()
  }

  // MARK: - Registry population

  func testRegisterBuiltinsPopulatesConditions() {
    let ids = ProviderRegistry.shared
      .descriptors(kind: .condition)
      .map(\.id)
    XCTAssertTrue(ids.contains("builtin.kind"))
    XCTAssertTrue(ids.contains("builtin.regex"))
    XCTAssertTrue(ids.contains("builtin.contains"))
    XCTAssertTrue(ids.contains("builtin.sourceApp"))
    XCTAssertTrue(ids.contains("builtin.pathType"))
  }

  func testRegisterBuiltinsPopulatesActions() {
    let ids = ProviderRegistry.shared
      .descriptors(kind: .action)
      .map(\.id)
    XCTAssertTrue(ids.contains("builtin.openURL"))
    XCTAssertTrue(ids.contains("builtin.openInApp"))
    XCTAssertTrue(ids.contains("builtin.webSearch"))
    XCTAssertTrue(ids.contains("builtin.revealInFinder"))
    XCTAssertTrue(ids.contains("builtin.openFile"))
    XCTAssertTrue(ids.contains("builtin.runShortcut"))
    XCTAssertTrue(ids.contains("builtin.ntfy"))
  }

  func testDescriptorsAreSortedByName() {
    let names = ProviderRegistry.shared.descriptors().map(\.name)
    XCTAssertEqual(names, names.sorted())
  }

  func testAllDescriptorsHaveNativeEngine() {
    for d in ProviderRegistry.shared.descriptors() {
      XCTAssertEqual(d.engine, .native, "Provider \(d.id) should have engine .native")
    }
  }

  func testAllDescriptorsAreBuiltinSource() {
    for d in ProviderRegistry.shared.descriptors() {
      XCTAssertEqual(d.source, .builtin, "Provider \(d.id) should have source .builtin")
    }
  }

  func testAllDescriptorsAreVerified() {
    for d in ProviderRegistry.shared.descriptors() {
      XCTAssertTrue(d.isVerified, "Provider \(d.id) should be verified")
    }
  }

  func testDescriptionsAreShorterThan121Chars() {
    for d in ProviderRegistry.shared.descriptors() {
      XCTAssertLessThanOrEqual(
        d.description.count, 120,
        "Provider \(d.id) description is \(d.description.count) chars (max 120)"
      )
    }
  }

  func testAllDescriptorsHaveEmptyCapabilities() {
    for d in ProviderRegistry.shared.descriptors() {
      XCTAssertTrue(
        d.capabilities.isEmpty,
        "Builtin provider \(d.id) should declare no capabilities"
      )
    }
  }

  // MARK: - KindCondition

  func testKindConditionDescriptor() {
    let d = ProviderRegistry.shared.condition("builtin.kind")!.descriptor
    XCTAssertEqual(d.id, "builtin.kind")
    XCTAssertEqual(d.kind, .condition)
    XCTAssertEqual(d.params.count, 1)
    XCTAssertEqual(d.params[0].key, "kind")
    XCTAssertEqual(d.params[0].kind, .valueKind)
  }

  func testKindConditionMatchesURL() throws {
    let provider = ProviderRegistry.shared.condition("builtin.kind")!
    let input = PluginInput(
      string: "https://example.com",
      kinds: [.url, .text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(input, params: .object(["kind": .string("url")]))
    XCTAssertTrue(result)
  }

  func testKindConditionNoMatchForWrongKind() throws {
    let provider = ProviderRegistry.shared.condition("builtin.kind")!
    let input = PluginInput(
      string: "hello world",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(input, params: .object(["kind": .string("url")]))
    XCTAssertFalse(result)
  }

  func testKindConditionMissingParamThrows() {
    let provider = ProviderRegistry.shared.condition("builtin.kind")!
    let input = PluginInput(
      string: "x",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    XCTAssertThrowsError(try provider.evaluate(input, params: .object([:])))
  }

  func testKindConditionUnknownKindThrows() {
    let provider = ProviderRegistry.shared.condition("builtin.kind")!
    let input = PluginInput(
      string: "x",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    XCTAssertThrowsError(
      try provider.evaluate(input, params: .object(["kind": .string("notARealKind")]))
    )
  }

  // MARK: - RegexCondition

  func testRegexConditionDescriptor() {
    let d = ProviderRegistry.shared.condition("builtin.regex")!.descriptor
    XCTAssertEqual(d.id, "builtin.regex")
    XCTAssertEqual(d.kind, .condition)
    XCTAssertEqual(d.params.count, 1)
    XCTAssertEqual(d.params[0].key, "pattern")
    XCTAssertEqual(d.params[0].kind, .text)
  }

  func testRegexConditionMatches() throws {
    let provider = ProviderRegistry.shared.condition("builtin.regex")!
    let input = PluginInput(
      string: "hello world",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(
      input,
      params: .object(["pattern": .string("^hello")])
    )
    XCTAssertTrue(result)
  }

  func testRegexConditionNoMatch() throws {
    let provider = ProviderRegistry.shared.condition("builtin.regex")!
    let input = PluginInput(
      string: "hello world",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(
      input,
      params: .object(["pattern": .string("^goodbye")])
    )
    XCTAssertFalse(result)
  }

  func testRegexConditionEmptyPatternReturnsFalse() throws {
    let provider = ProviderRegistry.shared.condition("builtin.regex")!
    let input = PluginInput(
      string: "hello",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(input, params: .object(["pattern": .string("")]))
    XCTAssertFalse(result)
  }

  func testRegexConditionInvalidPatternReturnsFalse() throws {
    let provider = ProviderRegistry.shared.condition("builtin.regex")!
    let input = PluginInput(
      string: "hello",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    // "[" is an invalid regex pattern
    let result = try provider.evaluate(input, params: .object(["pattern": .string("[")]))
    XCTAssertFalse(result)
  }

  func testRegexConditionMissingPatternReturnsFalse() throws {
    let provider = ProviderRegistry.shared.condition("builtin.regex")!
    let input = PluginInput(
      string: "hello",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(input, params: .object([:]))
    XCTAssertFalse(result)
  }

  // MARK: - ContainsCondition

  func testContainsConditionDescriptor() {
    let d = ProviderRegistry.shared.condition("builtin.contains")!.descriptor
    XCTAssertEqual(d.id, "builtin.contains")
    XCTAssertEqual(d.kind, .condition)
    XCTAssertEqual(d.params.count, 1)
    XCTAssertEqual(d.params[0].key, "needle")
    XCTAssertEqual(d.params[0].kind, .text)
  }

  func testContainsConditionMatches() throws {
    let provider = ProviderRegistry.shared.condition("builtin.contains")!
    let input = PluginInput(
      string: "Hello World",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    // case-insensitive per the existing engine
    let result = try provider.evaluate(
      input,
      params: .object(["needle": .string("world")])
    )
    XCTAssertTrue(result)
  }

  func testContainsConditionNoMatch() throws {
    let provider = ProviderRegistry.shared.condition("builtin.contains")!
    let input = PluginInput(
      string: "Hello World",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(
      input,
      params: .object(["needle": .string("goodbye")])
    )
    XCTAssertFalse(result)
  }

  func testContainsConditionEmptyNeedleReturnsFalse() throws {
    let provider = ProviderRegistry.shared.condition("builtin.contains")!
    let input = PluginInput(
      string: "hello",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(input, params: .object(["needle": .string("")]))
    XCTAssertFalse(result)
  }

  func testContainsConditionMissingNeedleReturnsFalse() throws {
    let provider = ProviderRegistry.shared.condition("builtin.contains")!
    let input = PluginInput(
      string: "hello",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(input, params: .object([:]))
    XCTAssertFalse(result)
  }

  // MARK: - SourceAppCondition

  func testSourceAppConditionDescriptor() {
    let d = ProviderRegistry.shared.condition("builtin.sourceApp")!.descriptor
    XCTAssertEqual(d.id, "builtin.sourceApp")
    XCTAssertEqual(d.kind, .condition)
    XCTAssertEqual(d.params.count, 1)
    XCTAssertEqual(d.params[0].key, "bundleID")
    XCTAssertEqual(d.params[0].kind, .bundleID)
  }

  func testSourceAppConditionMatchesExactBundle() throws {
    let provider = ProviderRegistry.shared.condition("builtin.sourceApp")!
    let input = PluginInput(
      string: "text",
      kinds: [.text],
      sourceAppBundleID: "com.apple.Safari",
      fileURLs: []
    )
    let result = try provider.evaluate(
      input,
      params: .object(["bundleID": .string("com.apple.Safari")])
    )
    XCTAssertTrue(result)
  }

  func testSourceAppConditionNoMatchDifferentBundle() throws {
    let provider = ProviderRegistry.shared.condition("builtin.sourceApp")!
    let input = PluginInput(
      string: "text",
      kinds: [.text],
      sourceAppBundleID: "com.apple.Safari",
      fileURLs: []
    )
    let result = try provider.evaluate(
      input,
      params: .object(["bundleID": .string("com.apple.Chrome")])
    )
    XCTAssertFalse(result)
  }

  func testSourceAppConditionNoMatchNilSource() throws {
    let provider = ProviderRegistry.shared.condition("builtin.sourceApp")!
    let input = PluginInput(
      string: "text",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let result = try provider.evaluate(
      input,
      params: .object(["bundleID": .string("com.apple.Safari")])
    )
    XCTAssertFalse(result)
  }

  func testSourceAppConditionMissingParamReturnsFalse() throws {
    let provider = ProviderRegistry.shared.condition("builtin.sourceApp")!
    let input = PluginInput(
      string: "text",
      kinds: [.text],
      sourceAppBundleID: "com.apple.Safari",
      fileURLs: []
    )
    let result = try provider.evaluate(input, params: .object([:]))
    XCTAssertFalse(result)
  }

  // MARK: - OpenURLProvider

  func testOpenURLDescriptor() {
    let d = ProviderRegistry.shared.action("builtin.openURL")!.descriptor
    XCTAssertEqual(d.id, "builtin.openURL")
    XCTAssertEqual(d.kind, .action)
    XCTAssertTrue(d.params.isEmpty)
  }

  func testOpenURLReturnsSideEffect() async throws {
    var capturedURL: URL?
    BuiltinLaunch.open = { capturedURL = $0 }
    let provider = ProviderRegistry.shared.action("builtin.openURL")!
    let input = PluginInput(
      string: "https://example.com",
      kinds: [.url, .text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let outcome = try await provider.run(input, params: .emptyObject)
    XCTAssertEqual(outcome, .sideEffect)
    XCTAssertEqual(capturedURL, URL(string: "https://example.com"))
  }

  func testOpenURLThrowsForNonURL() async {
    let provider = ProviderRegistry.shared.action("builtin.openURL")!
    let input = PluginInput(
      string: "not a url at all with spaces",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    do {
      _ = try await provider.run(input, params: .emptyObject)
      XCTFail("Expected throw for invalid URL")
    } catch {
      // Any error is acceptable; the point is it throws
    }
  }

  // MARK: - OpenInAppProvider

  func testOpenInAppDescriptor() {
    let d = ProviderRegistry.shared.action("builtin.openInApp")!.descriptor
    XCTAssertEqual(d.id, "builtin.openInApp")
    XCTAssertEqual(d.kind, .action)
    XCTAssertEqual(d.params.count, 1)
    XCTAssertEqual(d.params[0].key, "bundleID")
    XCTAssertEqual(d.params[0].kind, .bundleID)
  }

  // MARK: - WebSearchProvider

  func testWebSearchDescriptor() {
    let d = ProviderRegistry.shared.action("builtin.webSearch")!.descriptor
    XCTAssertEqual(d.id, "builtin.webSearch")
    XCTAssertEqual(d.kind, .action)
    XCTAssertEqual(d.params.count, 1)
    XCTAssertEqual(d.params[0].key, "template")
    XCTAssertEqual(d.params[0].kind, .text)
  }

  func testWebSearchReturnsSideEffect() async throws {
    var capturedURL: URL?
    BuiltinLaunch.open = { capturedURL = $0 }
    let provider = ProviderRegistry.shared.action("builtin.webSearch")!
    let input = PluginInput(
      string: "swift programming",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let outcome = try await provider.run(
      input,
      params: .object(["template": .string("https://example.com/search?q={query}")])
    )
    XCTAssertEqual(outcome, .sideEffect)
    XCTAssertNotNil(capturedURL)
    XCTAssertTrue(
      capturedURL!.absoluteString.contains("swift") ||
      capturedURL!.absoluteString.contains("swift%20programming")
    )
  }

  func testWebSearchThrowsForEmptyString() async {
    let provider = ProviderRegistry.shared.action("builtin.webSearch")!
    let input = PluginInput(
      string: "",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    do {
      _ = try await provider.run(
        input,
        params: .object(["template": .string("https://example.com/search?q={query}")])
      )
      XCTFail("Expected throw for empty input")
    } catch {
      // expected
    }
  }

  func testBuildSearchURLSubstitutesQuery() {
    let url = WebSearchProvider.buildSearchURL(
      template: "https://example.com/search?q={query}",
      query: "hello world"
    )
    XCTAssertNotNil(url)
    XCTAssertTrue(
      url!.absoluteString.contains("hello%20world") ||
      url!.absoluteString.contains("hello+world")
    )
  }

  func testBuildSearchURLReturnsNilForBadTemplate() {
    let url = WebSearchProvider.buildSearchURL(
      template: "not a url {query}",
      query: "test"
    )
    XCTAssertNil(url)
  }

  // MARK: - RunShortcutProvider

  func testRunShortcutDescriptor() {
    let d = ProviderRegistry.shared.action("builtin.runShortcut")!.descriptor
    XCTAssertEqual(d.id, "builtin.runShortcut")
    XCTAssertEqual(d.kind, .action)
    XCTAssertEqual(d.params.count, 1)
    XCTAssertEqual(d.params[0].key, "shortcutName")
    XCTAssertEqual(d.params[0].kind, .text)
  }

  func testRunShortcutReturnsSideEffect() async throws {
    var capturedURL: URL?
    BuiltinLaunch.open = { capturedURL = $0 }
    let provider = ProviderRegistry.shared.action("builtin.runShortcut")!
    let input = PluginInput(
      string: "some text",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    let outcome = try await provider.run(
      input,
      params: .object(["shortcutName": .string("My Shortcut")])
    )
    XCTAssertEqual(outcome, .sideEffect)
    XCTAssertNotNil(capturedURL)
    XCTAssertEqual(capturedURL!.scheme, "shortcuts")
    XCTAssertTrue(capturedURL!.absoluteString.contains("My%20Shortcut") ||
                  capturedURL!.absoluteString.contains("My+Shortcut") ||
                  capturedURL!.absoluteString.contains("My Shortcut"))
  }

  func testRunShortcutThrowsForMissingName() async {
    let provider = ProviderRegistry.shared.action("builtin.runShortcut")!
    let input = PluginInput(
      string: "some text",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    do {
      _ = try await provider.run(input, params: .object([:]))
      XCTFail("Expected throw for missing shortcut name")
    } catch {
      // expected
    }
  }

  func testRunShortcutThrowsForEmptyName() async {
    let provider = ProviderRegistry.shared.action("builtin.runShortcut")!
    let input = PluginInput(
      string: "some text",
      kinds: [.text],
      sourceAppBundleID: nil,
      fileURLs: []
    )
    do {
      _ = try await provider.run(input, params: .object(["shortcutName": .string("")]))
      XCTFail("Expected throw for empty shortcut name")
    } catch {
      // expected
    }
  }

  // MARK: - RevealInFinderProvider

  private func textInput(_ string: String, fileURLs: [URL] = []) -> PluginInput {
    PluginInput(string: string, kinds: [.filePath, .text], sourceAppBundleID: nil, fileURLs: fileURLs)
  }

  func testRevealInFinderResolvesTildeToRealHome() {
    let url = RevealInFinderProvider.resolveFileURL(from: textInput("  ~/Library/  \n"))
    XCTAssertEqual(url?.path, RevealInFinderProvider.realHome + "/Library")
    XCTAssertTrue(url?.hasDirectoryPath ?? false)
  }

  func testRevealInFinderResolvesAbsoluteFileAndFileScheme() {
    XCTAssertEqual(RevealInFinderProvider.resolveFileURL(from: textInput("/etc/hosts"))?.path, "/etc/hosts")
    XCTAssertEqual(
      RevealInFinderProvider.resolveFileURL(from: textInput("file:///etc/hosts"))?.path, "/etc/hosts")
  }

  func testRevealInFinderPrefersCopiedFileURLs() {
    let copied = URL(fileURLWithPath: "/tmp")
    XCTAssertEqual(RevealInFinderProvider.resolveFileURL(from: textInput("ignored", fileURLs: [copied])), copied)
  }

  func testRevealInFinderRejectsNonPaths() {
    XCTAssertNil(RevealInFinderProvider.resolveFileURL(from: textInput("https://example.com/a/b")))
    XCTAssertNil(RevealInFinderProvider.resolveFileURL(from: textInput("just some text")))
    XCTAssertNil(RevealInFinderProvider.resolveFileURL(from: textInput("")))
  }

  func testRevealInFinderRunsThroughSeamAndThrowsOnNonPath() async throws {
    let provider = ProviderRegistry.shared.action("builtin.revealInFinder")!
    let original = BuiltinLaunch.reveal
    defer { BuiltinLaunch.reveal = original }
    var revealed: URL?
    BuiltinLaunch.reveal = { revealed = $0 }

    let outcome = try await provider.run(textInput("~/Downloads/report.pdf"), params: .emptyObject)
    XCTAssertEqual(outcome, .sideEffect)
    XCTAssertEqual(revealed?.path, RevealInFinderProvider.realHome + "/Downloads/report.pdf")

    do {
      _ = try await provider.run(textInput("not a path"), params: .emptyObject)
      XCTFail("Expected throw for non-path text")
    } catch {
      // expected
    }
  }

  func testOpenFileRunsThroughSeamAndThrowsOnNonPath() async throws {
    let provider = ProviderRegistry.shared.action("builtin.openFile")!
    let original = BuiltinLaunch.openFile
    defer { BuiltinLaunch.openFile = original }
    var opened: URL?
    BuiltinLaunch.openFile = { opened = $0 }

    let outcome = try await provider.run(textInput("~/Downloads/report.pdf"), params: .emptyObject)
    XCTAssertEqual(outcome, .sideEffect)
    XCTAssertEqual(opened?.path, RevealInFinderProvider.realHome + "/Downloads/report.pdf")

    do {
      _ = try await provider.run(textInput("not a path"), params: .emptyObject)
      XCTFail("Expected throw for non-path text")
    } catch {
      // expected
    }
  }

  // MARK: - Path type condition

  func testPathTypeConditionMatchesFileAndFolder() throws {
    let condition = ProviderRegistry.shared.condition("builtin.pathType")!
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("maccy-pathtype-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("note.txt")
    try "hi".write(to: file, atomically: true, encoding: .utf8)

    let fileParams = JSONValue.object(["type": .string("file")])
    let folderParams = JSONValue.object(["type": .string("folder")])

    XCTAssertTrue(try condition.evaluate(textInput(file.path), params: fileParams))
    XCTAssertFalse(try condition.evaluate(textInput(file.path), params: folderParams))
    XCTAssertTrue(try condition.evaluate(textInput(dir.path), params: folderParams))
    XCTAssertFalse(try condition.evaluate(textInput(dir.path), params: fileParams))
  }

  func testPathTypeConditionRejectsMissingPathsAndBadParams() {
    let condition = ProviderRegistry.shared.condition("builtin.pathType")!
    let fileParams = JSONValue.object(["type": .string("file")])

    XCTAssertFalse(try condition.evaluate(textInput("/no/such/path/here"), params: fileParams))
    XCTAssertFalse(try condition.evaluate(textInput("just some text"), params: fileParams))
    XCTAssertThrowsError(try condition.evaluate(textInput("/tmp"), params: .emptyObject))
    XCTAssertThrowsError(
      try condition.evaluate(textInput("/tmp"), params: .object(["type": .string("socket")])))
  }

  // MARK: - Send to ntfy

  private func ntfyParams(_ values: [String: String]) -> JSONValue {
    .object(values.mapValues { .string($0) })
  }

  func testNtfyTextPostsToNtfyShByDefault() throws {
    let requests = try NtfyProvider.requests(for: textInput("hello"), params: ntfyParams(["topic": "alerts"]))

    XCTAssertEqual(requests.count, 1)
    let (request, file) = try XCTUnwrap(requests.first)
    XCTAssertEqual(request.url?.absoluteString, "https://ntfy.sh/alerts")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.httpBody, Data("hello".utf8))
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(file)
  }

  func testNtfySelfHostedWithBasicAuthAndTitle() throws {
    let params = ntfyParams([
      "server": " https://ntfy.example.com/base/ ", "topic": "clips",
      "title": "C++ & more", "tags": "warning,clip", "username": "roy", "password": "p:ss"
    ])
    let (request, _) = try XCTUnwrap(try NtfyProvider.requests(for: textInput("x"), params: params).first)

    XCTAssertEqual(request.url?.absoluteString, "https://ntfy.example.com/base/clips?title=C%2B%2B%20%26%20more&tags=warning,clip")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                   "Basic " + Data("roy:p:ss".utf8).base64EncodedString())
  }

  func testNtfyPasswordWithoutUsernameIsBearerToken() throws {
    let params = ntfyParams(["topic": "t", "password": "tk_abc"])
    let (request, _) = try XCTUnwrap(try NtfyProvider.requests(for: textInput("x"), params: params).first)

    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tk_abc")
  }

  func testNtfyServerWithoutSchemeDefaultsToHTTPS() throws {
    let params = ntfyParams(["server": "ntfy.example.com", "topic": "t"])
    let (request, _) = try XCTUnwrap(try NtfyProvider.requests(for: textInput("x"), params: params).first)

    XCTAssertEqual(request.url?.absoluteString, "https://ntfy.example.com/t")
  }

  func testNtfyKeychainReferenceResolvesThroughSecretStore() throws {
    let account = "test-\(UUID().uuidString)"
    SecretStore.write("tk_secret", account: account)
    defer { SecretStore.write("", account: account) }

    let params = ntfyParams(["topic": "t", "password": SecretStore.prefix + account])
    let (request, _) = try XCTUnwrap(try NtfyProvider.requests(for: textInput("x"), params: params).first)

    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tk_secret")
  }

  func testSecretStoreParsesSecurityOutput() {
    XCTAssertEqual(SecretStore.password("password: \"tk_abc\"\n"), "tk_abc")
    XCTAssertEqual(SecretStore.password("password: \"deadbeef\"\n"), "deadbeef")  // hex-looking text stays text
    XCTAssertEqual(SecretStore.password("password: \"a\"b c\"\n"), "a\"b c")
    XCTAssertEqual(SecretStore.password("password: 0xD7A9D79CD795D79D \n"), "שלום")
    XCTAssertNil(SecretStore.password("security: SecKeychainSearchCopyNext: not found\n"))
  }

  func testNtfyFilesAreUploadedOneMessageEach() throws {
    let files = [URL(fileURLWithPath: "/tmp/a report.pdf"), URL(fileURLWithPath: "/tmp/b.png")]
    let requests = try NtfyProvider.requests(
      for: textInput("/tmp/a report.pdf", fileURLs: files), params: ntfyParams(["topic": "t"]))

    XCTAssertEqual(requests.map(\.0.httpMethod), ["PUT", "PUT"])
    XCTAssertEqual(requests.map(\.0.url?.absoluteString),
                   ["https://ntfy.sh/t?filename=a%20report.pdf", "https://ntfy.sh/t?filename=b.png"])
    XCTAssertEqual(requests.map(\.1), files)
  }

  func testNtfyImageIsUploadedAsPNG() throws {
    let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
      NSColor.red.setFill()
      rect.fill()
      return true
    }
    var input = textInput("")
    input.imageData = { image.tiffRepresentation }

    let (request, file) = try XCTUnwrap(try NtfyProvider.requests(for: input, params: ntfyParams(["topic": "t"])).first)

    XCTAssertEqual(request.httpMethod, "PUT")
    XCTAssertEqual(request.url?.absoluteString, "https://ntfy.sh/t?filename=clipboard.png")
    XCTAssertEqual(request.httpBody?.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    XCTAssertNil(file)
  }

  func testNtfyRejectsMissingTopicBadServerAndEmptyClip() {
    XCTAssertThrowsError(try NtfyProvider.requests(for: textInput("x"), params: ntfyParams([:])))
    XCTAssertThrowsError(try NtfyProvider.requests(
      for: textInput("x"), params: ntfyParams(["topic": "t", "server": "ftp://host"])))
    XCTAssertThrowsError(try NtfyProvider.requests(for: textInput(""), params: ntfyParams(["topic": "t"])))
  }

  func testNtfyRunFailsOnHTTPErrorStatus() async {
    let originalSend = NtfyProvider.send
    defer { NtfyProvider.send = originalSend }
    var sent: [URLRequest] = []
    NtfyProvider.send = { request, _ in
      sent.append(request)
      return 403
    }

    do {
      _ = try await NtfyProvider().run(textInput("x"), params: ntfyParams(["topic": "t"]))
      XCTFail("expected an error")
    } catch {}
    XCTAssertEqual(sent.count, 1)
  }

  // MARK: - ProviderSource verified flag

  func testBuiltinSourceIsVerified() {
    XCTAssertTrue(ProviderSource.builtin.isVerified)
  }
}
