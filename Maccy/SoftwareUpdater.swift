import AppKit
import Sparkle

@Observable
class SoftwareUpdater {
  // MaccyPlus: one updater for the app's lifetime, started at launch, so the scheduled check runs
  // without Settings open (upstream created one per General pane).
  static let shared = SoftwareUpdater()

  var automaticallyChecksForUpdates = false {
    didSet {
      updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  private var updater: SPUUpdater
  private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?

  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: UpdateAlertPresenter.shared
  )

  init() {
    updater = updaterController.updater
    automaticallyChecksForUpdatesObservation = updater.observe(
      \.automaticallyChecksForUpdates,
      options: [.initial, .new, .old]
    ) { [unowned self] _, change in
      guard change.newValue != change.oldValue, let newValue = change.newValue else {
        return
      }

      MainActor.assumeIsolated {
        self.automaticallyChecksForUpdates = newValue
      }
    }
  }

  func checkForUpdates() {
    updater.checkForUpdates()
  }
}

/// MaccyPlus: a menu-bar-only app's scheduled update alert opens behind other windows, with no Dock
/// icon to find it by. Dock icon + front while the alert is up, back to accessory when it closes.
// @unchecked Sendable: no stored state.
nonisolated final class UpdateAlertPresenter: NSObject, SPUStandardUserDriverDelegate, @unchecked Sendable {
  static let shared = UpdateAlertPresenter()

  var supportsGentleScheduledUpdateReminders: Bool { true }

  // Sparkle calls these on the main thread; its header just doesn't say so to Swift.
  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool,
    forUpdate update: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    MainActor.assumeIsolated {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate()
    }
  }

  func standardUserDriverWillFinishUpdateSession() {
    DispatchQueue.main.async { // after Sparkle's window has closed
      if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
        NSApp.setActivationPolicy(.accessory)
      }
    }
  }
}
