// Demo layer renderer. render.sh copies the repo to a temp dir, drops this file over MaccyTests/ScreenshotRenderTests.swift (already
// in the test target, so the pbxproj is untouched) and runs it app-hosted with PRODUCT_BUNDLE_IDENTIFIER=com.royp.MaccyPlusShots,
// so the user's prefs and history are never read or written. It renders the REAL popup views (HeaderView / HistoryListView / FooterView,
// exactly as ContentView composes them, minus the glass backdrop the demo kit draws) over fake history as a transparent PNG at the
// kit's 8/3 px per pt, plus layers.json with the frames the scene needs (bolt badge, search field). Dev-only; skipped unless
// RENDER_DEMO_LAYERS=1. It never touches the pasteboard.
import AppKit
import Defaults
import SwiftData
import SwiftUI
import XCTest
@testable import Maccy

// ContentView.body without the GlassEffectView ZStack layer (the kit draws the glass).
private struct DemoPopup: View {
  @State private var appState = AppState.shared
  @FocusState private var searchFocused: Bool

  var body: some View {
    KeyHandlingView(searchQuery: $appState.history.searchQuery, searchFocused: $searchFocused) {
      VStack(spacing: 0) {
        SlideoutView(controller: appState.preview) {
          HeaderView(controller: appState.preview, searchFocused: $searchFocused)
          VStack(alignment: .leading, spacing: 0) {
            HistoryListView(searchQuery: $appState.history.searchQuery, searchFocused: $searchFocused)
            FooterView(footer: appState.footer)
          }
          .padding(.horizontal, Popup.horizontalPadding)
        } slideout: {
          SlideoutContentView()
        }
        .frame(minHeight: 0)
        .layoutPriority(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .environment(appState)
    .environment(ModifierFlags())
    .environment(\.scenePhase, .active)
    .environment(\.colorScheme, .dark)
  }
}

@MainActor
final class DemoLayerTests: XCTestCase {
  private let scale: CGFloat = 8.0 / 3.0  // DemoKit: 2560 px over a 960 pt canvas

  private func item(_ text: String, minutesAgo: Double) -> HistoryItem {
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: text.data(using: .utf8))]
    item.numberOfCopies = 1
    item.title = item.generateTitle()
    item.firstCopiedAt = Date.now.addingTimeInterval(-minutesAgo * 60)
    item.lastCopiedAt = item.firstCopiedAt
    return item
  }

  private func frames(of view: NSView, in host: NSView, matching: (NSView) -> Bool, into out: inout [[String: Double]]) {
    if matching(view) {
      let r = host.convert(view.bounds, from: view)
      let y = host.isFlipped ? r.minY : host.bounds.height - r.maxY
      out.append(["x": r.minX, "y": y, "w": r.width, "h": r.height])
    }
    for sub in view.subviews { frames(of: sub, in: host, matching: matching, into: &out) }
  }

  private func dump(_ view: NSView, _ depth: Int, into log: inout String) {
    log += String(repeating: " ", count: depth) + "\(type(of: view)) \(view.frame)\n"
    for sub in view.subviews { dump(sub, depth + 1, into: &log) }
  }

  func testRenderDemoLayers() async throws {
    let env = ProcessInfo.processInfo.environment
    try XCTSkipUnless(env["RENDER_DEMO_LAYERS"] == "1")
    let outDir = URL(fileURLWithPath: env["DEMO_LAYERS_OUT"] ?? NSTemporaryDirectory() + "maccyplus-demo-layers")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    // Rules: the shipped presets plus the Jira rule from the README (regex key -> web search with a template).
    let jira = ActionRule(
      name: "Open Jira ticket",
      conditions: [RuleCondition(provider: "builtin.regex", params: .object(["pattern": .string("^[A-Z]{2,5}-\\d+$")]))],
      actions: [ActionConfig(provider: "builtin.webSearch", params: .object(["template": .string("https://example.atlassian.net/browse/{query}")]))]
    )
    let saved = (Defaults[.actionRules], Defaults[.showSearch], Defaults[.showFooter], Defaults[.pinTo])
    Defaults[.actionRules] = [jira] + ActionRule.presets
    defer { (Defaults[.actionRules], Defaults[.showSearch], Defaults[.showFooter], Defaults[.pinTo]) = saved }

    let appState = AppState.shared
    History.shared.clearAll()
    // Oldest first: History sorts by last copy, newest on top.
    for (text, ago) in [
      ("SELECT id, name FROM orders LIMIT 10;", 41),
      ("Ship the release notes on Friday", 27),
      ("hello@example.com", 14),
      ("npm run build -- --watch", 9),
      ("https://example.com/docs/getting-started", 4),
      ("ABC-123", 0),
    ] as [(String, Double)] {
      _ = History.shared.add(item(text, minutesAgo: ago))
    }
    try await History.shared.load()
    appState.navigator.select(item: History.shared.firstUnpinnedItem)

    let width: CGFloat = 450  // Defaults[.windowSize].width
    func host(height: CGFloat) -> (NSWindow, NSHostingView<AnyView>) {
      let host = NSHostingView(rootView: AnyView(DemoPopup().frame(width: width, height: height, alignment: .topLeading)))
      let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false  // ARC owns it; the default over-releases at test teardown (SIGSEGV in the autorelease pool)
      window.appearance = NSAppearance(named: .darkAqua)
      window.isOpaque = false
      window.backgroundColor = .clear
      window.contentView = host
      host.frame = CGRect(x: 0, y: 0, width: width, height: height)
      return (window, host)
    }

    // 1. natural height: render tall, let HistoryListView report it, then size to it (multiple of 3 so 8/3 px/pt is integral).
    var (window, hostView) = host(height: 700)
    try await Task.sleep(for: .seconds(1))  // lets the main run loop lay the views out
    hostView.layoutSubtreeIfNeeded()
    let natural = ceil(appState.popup.height / 3) * 3
    XCTAssertGreaterThan(natural, 100, "popup height was not measured")
    (window, hostView) = host(height: natural)
    try await Task.sleep(for: .seconds(1))  // lets the main run loop lay the views out
    hostView.layoutSubtreeIfNeeded()

    // 2. render
    let size = CGSize(width: width, height: natural)
    let rep = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    rep.size = size
    hostView.cacheDisplay(in: hostView.bounds, to: rep)
    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: outDir.appendingPathComponent("panel.png"))

    // 3. geometry for the scene (top-left origin, panel points) + a view dump for debugging
    var badges: [[String: Double]] = [], fields: [[String: Double]] = []
    frames(of: hostView, in: hostView, matching: { $0 is NSPopUpButton }, into: &badges)
    frames(of: hostView, in: hostView, matching: { $0 is NSTextField || $0 is NSTextView }, into: &fields)
    var log = ""
    dump(hostView, 0, into: &log)
    try log.write(to: outDir.appendingPathComponent("views.txt"), atomically: true, encoding: .utf8)
    let rows = History.shared.unpinnedItems.map { ["title": $0.title, "actions": $0.resolvedActions.map(\.title)] as [String: Any] }
    let layers: [String: Any] = [
      "width": Double(size.width), "height": Double(size.height), "popupHeight": Double(appState.popup.height),
      "popUpButtons": badges, "textFields": fields, "rows": rows,
      "footerTitles": appState.footer.items.map(\.title),
    ]
    try JSONSerialization.data(withJSONObject: layers, options: [.prettyPrinted, .sortedKeys]).write(to: outDir.appendingPathComponent("layers.json"))
    print("DEMO_LAYERS_OUT=\(outDir.path)")
    window.close()
  }
}
