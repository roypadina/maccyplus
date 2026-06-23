import XCTest
@testable import Maccy

@MainActor
final class FirstPartyProvidersTests: XCTestCase {

  // MARK: - Helpers

  private func input(
    _ string: String,
    sourceApp: String? = nil
  ) -> PluginInput {
    PluginInput(string: string, kinds: [], sourceAppBundleID: sourceApp, fileURLs: [])
  }

  // A wrapped input: two lines of width >= 40, last line shorter.
  private var wrappedInput: PluginInput {
    let line = String(repeating: "a", count: 42)
    let text = line + "\n" + "hello"
    return input(text)
  }

  private var notWrappedInput: PluginInput {
    input("short\nlines\nhere")
  }

  // MARK: - SoftWrapCondition

  func testSoftWrapTrueForWrappedText() throws {
    let provider = SoftWrapCondition()
    XCTAssertTrue(try provider.evaluate(wrappedInput, params: .emptyObject))
  }

  func testSoftWrapFalseForShortLines() throws {
    let provider = SoftWrapCondition()
    XCTAssertFalse(try provider.evaluate(notWrappedInput, params: .emptyObject))
  }

  func testSoftWrapDescriptor() {
    let d = SoftWrapCondition().descriptor
    XCTAssertEqual(d.id, "com.maccay.soft-wrap")
    XCTAssertEqual(d.kind, .condition)
    XCTAssertEqual(d.engine, .native)
    XCTAssertEqual(d.source, .builtin)
    XCTAssertTrue(d.params.isEmpty)
  }

  // MARK: - TerminalSourceCondition

  func testTerminalSourceTrueForKnownApp() throws {
    let provider = TerminalSourceCondition()
    // "com.apple.Terminal" is in TerminalApps.defaults
    let inp = input("anything", sourceApp: "com.apple.Terminal")
    XCTAssertTrue(try provider.evaluate(inp, params: .emptyObject))
  }

  func testTerminalSourceFalseForUnknownApp() throws {
    let provider = TerminalSourceCondition()
    let inp = input("anything", sourceApp: "com.example.NotATerminal")
    XCTAssertFalse(try provider.evaluate(inp, params: .emptyObject))
  }

  func testTerminalSourceFalseForNilApp() throws {
    let provider = TerminalSourceCondition()
    let inp = input("anything", sourceApp: nil)
    XCTAssertFalse(try provider.evaluate(inp, params: .emptyObject))
  }

  func testTerminalSourceDescriptor() {
    let d = TerminalSourceCondition().descriptor
    XCTAssertEqual(d.id, "com.maccay.terminal-source")
    XCTAssertEqual(d.kind, .condition)
    XCTAssertEqual(d.engine, .native)
    XCTAssertEqual(d.source, .builtin)
    XCTAssertTrue(d.params.isEmpty)
  }

  // MARK: - TrimAction

  func testTrimReturnsReplace() async throws {
    let outcome = try await TrimAction().run(input("  hello  "), params: .emptyObject)
    XCTAssertEqual(outcome, .replace("hello"))
  }

  func testTrimPreservesInnerWhitespace() async throws {
    let outcome = try await TrimAction().run(input("  hello world  "), params: .emptyObject)
    XCTAssertEqual(outcome, .replace("hello world"))
  }

  func testTrimThrowsOnEmpty() async {
    do {
      _ = try await TrimAction().run(input(""), params: .emptyObject)
      XCTFail("Expected ActionError.noValue")
    } catch ActionError.noValue {
      // expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testTrimDescriptor() {
    let d = TrimAction().descriptor
    XCTAssertEqual(d.id, "com.maccay.trim")
    XCTAssertEqual(d.kind, .action)
    XCTAssertEqual(d.engine, .native)
    XCTAssertEqual(d.source, .builtin)
    XCTAssertTrue(d.params.isEmpty)
  }

  // MARK: - UppercaseAction

  func testUppercaseReturnsReplace() async throws {
    let outcome = try await UppercaseAction().run(input("hello"), params: .emptyObject)
    XCTAssertEqual(outcome, .replace("HELLO"))
  }

  func testUppercaseThrowsOnEmpty() async {
    do {
      _ = try await UppercaseAction().run(input(""), params: .emptyObject)
      XCTFail("Expected ActionError.noValue")
    } catch ActionError.noValue {
      // expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testUppercaseDescriptor() {
    let d = UppercaseAction().descriptor
    XCTAssertEqual(d.id, "com.maccay.uppercase")
    XCTAssertEqual(d.kind, .action)
  }

  // MARK: - LowercaseAction

  func testLowercaseReturnsReplace() async throws {
    let outcome = try await LowercaseAction().run(input("HELLO"), params: .emptyObject)
    XCTAssertEqual(outcome, .replace("hello"))
  }

  func testLowercaseThrowsOnEmpty() async {
    do {
      _ = try await LowercaseAction().run(input(""), params: .emptyObject)
      XCTFail("Expected ActionError.noValue")
    } catch ActionError.noValue {
      // expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testLowercaseDescriptor() {
    let d = LowercaseAction().descriptor
    XCTAssertEqual(d.id, "com.maccay.lowercase")
    XCTAssertEqual(d.kind, .action)
  }

  // MARK: - StripFormattingAction

  func testStripFormattingReturnsReplaceWithSameString() async throws {
    // stripFormatting on a plain string returns the same string unchanged
    let outcome = try await StripFormattingAction().run(input("hello"), params: .emptyObject)
    XCTAssertEqual(outcome, .replace("hello"))
  }

  func testStripFormattingThrowsOnEmpty() async {
    do {
      _ = try await StripFormattingAction().run(input(""), params: .emptyObject)
      XCTFail("Expected ActionError.noValue")
    } catch ActionError.noValue {
      // expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testStripFormattingDescriptor() {
    let d = StripFormattingAction().descriptor
    XCTAssertEqual(d.id, "com.maccay.strip-formatting")
    XCTAssertEqual(d.kind, .action)
  }

  // MARK: - UnwrapAction

  func testUnwrapJoinsWrappedLines() async throws {
    let line = String(repeating: "a", count: 42)
    let text = line + "\n" + "hello"
    let outcome = try await UnwrapAction().run(input(text), params: .emptyObject)
    // isSoftWrapped → delete newlines
    XCTAssertEqual(outcome, .replace(line + "hello"))
  }

  func testUnwrapCollapsesSoftNewlinesOnNonWrapped() async throws {
    let outcome = try await UnwrapAction().run(input("line one\nline two"), params: .emptyObject)
    XCTAssertEqual(outcome, .replace("line one line two"))
  }

  func testUnwrapThrowsOnEmpty() async {
    do {
      _ = try await UnwrapAction().run(input(""), params: .emptyObject)
      XCTFail("Expected ActionError.noValue")
    } catch ActionError.noValue {
      // expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testUnwrapDescriptor() {
    let d = UnwrapAction().descriptor
    XCTAssertEqual(d.id, "com.maccay.unwrap")
    XCTAssertEqual(d.kind, .action)
  }

  // MARK: - FixKeyboardLayoutAction

  func testFixKeyboardLayoutEnToHe() async throws {
    // "akuo" typed on EN layout → "שלום" in HE
    let outcome = try await FixKeyboardLayoutAction().run(input("akuo"), params: .emptyObject)
    XCTAssertEqual(outcome, .replace("שלום"))
  }

  func testFixKeyboardLayoutHeToEn() async throws {
    // "שלום" typed on HE layout → "akuo" in EN
    let outcome = try await FixKeyboardLayoutAction().run(input("שלום"), params: .emptyObject)
    XCTAssertEqual(outcome, .replace("akuo"))
  }

  func testFixKeyboardLayoutThrowsOnEmpty() async {
    do {
      _ = try await FixKeyboardLayoutAction().run(input(""), params: .emptyObject)
      XCTFail("Expected ActionError.noValue")
    } catch ActionError.noValue {
      // expected
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFixKeyboardLayoutDescriptor() {
    let d = FixKeyboardLayoutAction().descriptor
    XCTAssertEqual(d.id, "com.maccay.fix-keyboard-layout")
    XCTAssertEqual(d.kind, .action)
  }

  // MARK: - registerFirstParty

  func testRegisterFirstPartyRegistersAllEight() {
    let registry = ProviderRegistry()
    FirstPartyProviders.registerFirstParty(into: registry)

    // 2 conditions
    XCTAssertNotNil(registry.condition("com.maccay.soft-wrap"))
    XCTAssertNotNil(registry.condition("com.maccay.terminal-source"))

    // 6 actions
    XCTAssertNotNil(registry.action("com.maccay.trim"))
    XCTAssertNotNil(registry.action("com.maccay.uppercase"))
    XCTAssertNotNil(registry.action("com.maccay.lowercase"))
    XCTAssertNotNil(registry.action("com.maccay.strip-formatting"))
    XCTAssertNotNil(registry.action("com.maccay.unwrap"))
    XCTAssertNotNil(registry.action("com.maccay.fix-keyboard-layout"))
  }

  func testRegisterFirstPartyDescriptorCount() {
    let registry = ProviderRegistry()
    FirstPartyProviders.registerFirstParty(into: registry)
    let all = registry.descriptors()
    XCTAssertEqual(all.count, 8)
  }
}
