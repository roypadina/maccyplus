import AppKit
import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator
  var previous: HistoryItemDecorator?
  var next: HistoryItemDecorator?
  var index: Int

  private var visualIndex: Int? {
    if appState.navigator.isMultiSelectInProgress && item.selectionIndex >= 0 {
      return item.selectionIndex
    }
    return nil
  }

  private var selectionAppearance: SelectionAppearance {
    let previousSelected = previous?.isSelected ?? false
    let nextSelected = next?.isSelected ?? false
    switch (previousSelected, nextSelected) {
    case (true, false):
      return .topConnection
    case (false, true):
      return .bottomConnection
    case (true, true):
      return .topBottomConnection
    default:
      return .none
    }
  }

  @Environment(AppState.self) private var appState

  var body: some View {
    ListItemView(
      id: item.id,
      selectionId: item.id,
      appIcon: item.item.fromPhone ? PhoneIcon.applicationImage : item.applicationImage,
      image: item.thumbnailImage,
      accessoryImage: item.thumbnailImage != nil ? nil : ColorImage.from(item.title),
      attributedTitle: item.attributedTitle,
      shortcuts: item.shortcuts,
      rowActions: rowActions,
      isSelected: item.isSelected,
      selectionIndex: visualIndex,
      selectionAppearance: selectionAppearance
    ) {
      Text(verbatim: item.title)
    }
    .onAppear {
      item.ensureThumbnailImage()
    }
    .onTapGesture {
      if NSEvent.modifierFlags.contains(.command) && appState.multiSelectionEnabled {
        appState.navigator.addToSelection(item: item)
      } else {
        Task {
          appState.history.select(item)
        }
      }
    }
    .contextMenu {
      actionsMenu
    }
  }

  @ViewBuilder
  private var actionsMenu: some View {
    if rowActions.isEmpty {
      Text("No matching actions")
    } else {
      ForEach(rowActions) { rowAction in
        Button(action: rowAction.run) {
          Label(rowAction.title, systemImage: rowAction.systemImage)
        }
      }
    }
  }

  private var rowActions: [RowActionItem] {
    ActionEngine.shared.resolvedActions(for: item.item).enumerated().map { index, action in
      RowActionItem(
        id: action.id,
        title: index == 0 ? "\(action.title) (default)" : action.title,
        systemImage: action.systemImage
      ) {
        ActionEngine.shared.run(action, on: item.item)
        appState.popup.close()
      }
    }
  }
}

// A colorful app-icon-style badge for clips synced from the phone: a blue→purple
// rounded-rect (matching the Android app's look) with a white phone glyph. Shown
// in the row's leading app-icon slot instead of the source app's icon.
enum PhoneIcon {
  static let applicationImage = ApplicationImage(
    bundleIdentifier: "com.royp.MaccyActions.phone", image: makeIcon())

  private static func makeIcon() -> NSImage {
    let size = NSSize(width: 64, height: 64)
    let icon = NSImage(size: size)
    icon.lockFocus()

    let rect = NSRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
    let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
    let gradient = NSGradient(
      starting: NSColor(srgbRed: 0.30, green: 0.33, blue: 0.82, alpha: 1),   // blue
      ending: NSColor(srgbRed: 0.53, green: 0.27, blue: 0.64, alpha: 1))     // purple
    gradient?.draw(in: path, angle: -90)

    if let glyph = whiteGlyph() {
      let s = glyph.size
      glyph.draw(in: NSRect(x: (size.width - s.width) / 2,
                            y: (size.height - s.height) / 2,
                            width: s.width, height: s.height))
    }

    icon.unlockFocus()
    return icon
  }

  // SF Symbol "iphone" tinted solid white, in its own image (so the tint doesn't
  // bleed onto the gradient when composited).
  private static func whiteGlyph() -> NSImage? {
    guard let symbol = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 38, weight: .semibold))
    else { return nil }
    let out = NSImage(size: symbol.size)
    out.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
  }
}
