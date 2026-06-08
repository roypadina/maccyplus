import AppKit
import SwiftUI

// Lightweight floating panel hosting the Remote Clipboard view. Independent of
// the main popup's FloatingPanel so it carries none of the preview/navigator state.
@MainActor
final class RemoteClipboardPanel: NSPanel {
  static let shared = RemoteClipboardPanel()

  private init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
      styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = true
    hidesOnDeactivate = false
    animationBehavior = .utilityWindow
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true

    contentView = NSHostingView(rootView: RemoteClipboardView(onClose: { [weak self] in
      self?.close()
    }).ignoresSafeArea())
  }

  func toggle() {
    if isVisible {
      close()
    } else {
      present()
    }
  }

  private func present() {
    // Rebuild the hosting view on every open. An NSPanel reuses its content view
    // across close/open, so SwiftUI's onAppear and @Observable updates don't
    // re-fire on re-open — the panel would keep showing the first snapshot. A
    // fresh view reads the current store and re-runs onAppear.
    contentView = NSHostingView(rootView: RemoteClipboardView(onClose: { [weak self] in
      self?.close()
    }).ignoresSafeArea())
    // Pull the phone's current history so the panel is never stale on open.
    LanSyncService.shared.requestHistory()
    if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      let size = self.frame.size
      let origin = NSPoint(
        x: frame.midX - size.width / 2,
        y: frame.midY - size.height / 2 + 80)
      setFrameOrigin(origin)
    }
    orderFrontRegardless()
    makeKey()
  }

  override var canBecomeKey: Bool { true }

  override func resignKey() {
    super.resignKey()
    if NSApp.alertWindow == nil {
      close()
    }
  }
}
