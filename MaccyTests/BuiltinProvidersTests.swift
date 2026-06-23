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
  }

  func testRegisterBuiltinsPopulatesActions() {
    let ids = ProviderRegistry.shared
      .descriptors(kind: .action)
      .map(\.id)
    XCTAssertTrue(ids.contains("builtin.openURL"))
    XCTAssertTrue(ids.contains("builtin.openInApp"))
    XCTAssertTrue(ids.contains("builtin.webSearch"))
    XCTAssertTrue(ids.contains("builtin.runShortcut"))
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

  // MARK: - ProviderSource verified flag

  func testBuiltinSourceIsVerified() {
    XCTAssertTrue(ProviderSource.builtin.isVerified)
  }
}
