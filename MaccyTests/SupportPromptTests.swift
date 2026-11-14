import Foundation
import Testing
@testable import Maccy

@MainActor
struct SupportPromptTests {
  private let day = SupportPromptState.day
  private let install = Date(timeIntervalSince1970: 1_794_528_000)  // 2026-11-13

  private func mayAsk(_ state: SupportPromptState, day dayCount: Double, pastes: Int = 80,
                      version: String = "2.11.0") -> Bool {
    state.mayAsk(now: install.addingTimeInterval(dayCount * day), installDate: install, pastes: pastes,
                 appVersion: version)
  }

  @Test("First ask needs 7 days and more than 60 pastes, never at 60 or below")
  func firstAskNeedsSevenDaysAndMoreThan60Pastes() {
    let state = SupportPromptState()
    #expect(!mayAsk(state, day: 6.9))
    #expect(!mayAsk(state, day: 30, pastes: 60))
    #expect(!mayAsk(state, day: 365, pastes: 0))
    #expect(mayAsk(state, day: 7, pastes: 61))
  }

  @Test("Snooze hides the card for 14 days")
  func snoozeHidesFourteenDays() {
    var state = SupportPromptState()
    state.record(.snooze, now: install.addingTimeInterval(10 * day), appVersion: "2.11.0")
    #expect(!mayAsk(state, day: 23.9))
    #expect(mayAsk(state, day: 24))
  }

  @Test("A tip keeps it quiet for 180 days")
  func supportQuietFor180Days() {
    var state = SupportPromptState()
    state.record(.support, now: install.addingTimeInterval(10 * day), appVersion: "2.11.0")
    #expect(!mayAsk(state, day: 189))
    #expect(mayAsk(state, day: 190))
  }

  @Test("Never lasts until the next major version and 90 days")
  func neverLastsUntilNextMajorAndNinetyDays() {
    var state = SupportPromptState()
    state.record(.never, now: install.addingTimeInterval(10 * day), appVersion: "2.11.0")
    #expect(!mayAsk(state, day: 300, version: "2.12.0"), "a feature release must not undo 'never'")
    #expect(!mayAsk(state, day: 50, version: "3.0.0"), "a major release within 90 days must not undo it")
    #expect(mayAsk(state, day: 100, version: "3.0.0"))
  }

  @Test("At most 3 asks per rolling 365 days")
  func atMostThreeAsksPerRolling365Days() {
    var state = SupportPromptState()
    for dayCount in [10.0, 40, 70] { state.recordShown(install.addingTimeInterval(dayCount * day)) }
    #expect(!mayAsk(state, day: 300))
    #expect(mayAsk(state, day: 376), "the first ask has rolled out of the window")
  }

  @Test("Old or partial state decodes without wiping the rest")
  func oldStateDecodes() throws {
    let empty = try JSONDecoder().decode(SupportPromptState.self, from: Data("{}".utf8))
    #expect(empty == SupportPromptState())

    var saved = SupportPromptState()
    saved.record(.snooze, now: install, appVersion: "2.11.0")
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
    json["futureKey"] = 1
    let decoded = try JSONDecoder().decode(SupportPromptState.self,
                                           from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded == saved, "an unknown key must not wipe the known ones")
  }
}
