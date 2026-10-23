import Defaults
import KeyboardShortcuts
import SwiftUI
import XCTest
@testable import Maccy

// Dev-only: renders README screenshots with fake data. Skipped unless RENDER_SCREENSHOTS=1.
// Run with a throwaway bundle id so the real app's prefs are untouched, then copy PNGs from the
// test host's temp dir (see RENDER_SCREENSHOTS_OUT) into docs/screenshots/.
@MainActor
final class ScreenshotRenderTests: XCTestCase {
  private func render<V: View>(_ view: V, size: CGSize, name: String, wait: TimeInterval = 0.5) throws {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.titled], backing: .buffered, defer: false
    )
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    host.frame = CGRect(origin: .zero, size: size)
    RunLoop.current.run(until: Date().addingTimeInterval(wait))
    host.layoutSubtreeIfNeeded()
    let scale = 2
    let rep = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("maccyplus-shots")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png.write(to: dir.appendingPathComponent("\(name).png"))
  }

  func testRenderScreenshots() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDER_SCREENSHOTS"] == "1")

    func rule(_ name: String, _ conds: [RuleCondition], _ acts: [ActionConfig], auto: Bool = false) -> ActionRule {
      ActionRule(name: name, conditions: conds, actions: acts, autoRunDefault: auto)
    }
    let jira = rule(
      "Open Jira ticket",
      [RuleCondition(provider: "builtin.regex", params: .object(["pattern": .string("^[A-Z]{2,5}-\\d+$")]))],
      [
        ActionConfig(provider: "builtin.webSearch", params: .object(["template": .string("https://example.atlassian.net/browse/{query}")]), shortcut: "ctrl+opt+cmd+j"),
        ActionConfig(provider: "builtin.webSearch", params: .object(["template": .string(WebSearchTemplate.google)]))
      ]
    )
    let rules: [ActionRule] = [
      ActionRule.presets[0],
      jira,
      rule(
        "Reveal paths in Finder",
        [RuleCondition(provider: "builtin.kind", params: .object(["kind": .string("filePath")]))],
        [ActionConfig(provider: "builtin.revealInFinder", params: .emptyObject, shortcut: "ctrl+opt+cmd+f")]
      ),
      ActionRule.presets[3],
      ActionRule.presets[2]
    ]
    let saved = Defaults[.actionRules]
    Defaults[.actionRules] = rules
    defer { Defaults[.actionRules] = saved }

    var shortcutNames: [KeyboardShortcuts.Name] = []
    for r in rules {
      for a in r.actions where a.shortcut != nil {
        let n = KeyboardShortcuts.Name("action_\(a.id.uuidString)")
        shortcutNames.append(n)
        let key: KeyboardShortcuts.Key = r.name.hasPrefix("Reveal") ? .f : .j
        KeyboardShortcuts.setShortcut(.init(key, modifiers: [.control, .option, .command]), for: n)
      }
    }
    defer { shortcutNames.forEach { KeyboardShortcuts.reset($0) } }

    try render(ActionsSettingsPane(initialSelection: jira.id, height: 640), size: CGSize(width: 760, height: 640), name: "actions-rules")
    try render(PluginsSettingsPane(height: 1100), size: CGSize(width: 760, height: 1100), name: "plugins", wait: 3)
  }
}
