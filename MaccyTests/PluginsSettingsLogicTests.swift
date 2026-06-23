import XCTest
@testable import Maccy

@MainActor
final class PluginsSettingsLogicTests: XCTestCase {
  private let probeID = "test.consent.probe"

  override func setUp() {
    super.setUp()
    CapabilityManager.shared.revokeAll(pluginID: probeID)
  }

  override func tearDown() {
    CapabilityManager.shared.revokeAll(pluginID: probeID)
    super.tearDown()
  }

  // No declared capabilities → no consent needed, regardless of source.
  func testNoCapabilitiesNeverRequiresConsent() {
    XCTAssertFalse(
      PluginsSettingsPane.requiresConsent(
        declared: [],
        source: .marketplace("some-third-party"),
        manager: CapabilityManager.shared,
        pluginID: probeID
      )
    )
  }

  // Declared capability, none granted yet → requires consent.
  func testUngrantedCapabilityRequiresConsent() {
    XCTAssertTrue(
      PluginsSettingsPane.requiresConsent(
        declared: [.network],
        source: .marketplace("some-third-party"),
        manager: CapabilityManager.shared,
        pluginID: probeID
      )
    )
  }

  // Declared capability already granted → no further consent needed.
  func testAlreadyGrantedCapabilityDoesNotRequireConsent() {
    CapabilityManager.shared.grant([.network], pluginID: probeID)
    XCTAssertFalse(
      PluginsSettingsPane.requiresConsent(
        declared: [.network],
        source: .marketplace("some-third-party"),
        manager: CapabilityManager.shared,
        pluginID: probeID
      )
    )
  }

  // A second, not-yet-granted capability still triggers consent.
  func testPartiallyGrantedCapabilitiesRequireConsent() {
    CapabilityManager.shared.grant([.network], pluginID: probeID)
    XCTAssertTrue(
      PluginsSettingsPane.requiresConsent(
        declared: [.network, .fileRead],
        source: .marketplace("some-third-party"),
        manager: CapabilityManager.shared,
        pluginID: probeID
      )
    )
  }
}
