import Defaults
import KeyboardShortcuts
import SwiftUI
import XCTest
@testable import Maccy

// Dev-only: renders README screenshots with fake data. Skipped unless RENDER_SCREENSHOTS=1.
// Run with a throwaway bundle id so the real app's prefs are untouched, then copy PNGs from the
// test host's temp dir ($TMPDIR/maccyplus-shots) into docs/screenshots/.
@MainActor
final class ScreenshotRenderTests: XCTestCase {
  // Renders a light and a "-dark" variant so the README can serve the one matching the GitHub theme.
  private func render<V: View>(_ view: V, size: CGSize, name: String, wait: TimeInterval = 0.5) throws {
    for dark in [false, true] {
      try render(view, size: size, name: dark ? "\(name)-dark" : name, dark: dark, wait: wait)
    }
  }

  private func render<V: View>(_ view: V, size: CGSize, name: String, dark: Bool, wait: TimeInterval) throws {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.titled], backing: .buffered, defer: false
    )
    let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
    window.appearance = appearance
    window.contentView = host
    host.frame = CGRect(origin: .zero, size: size)
    RunLoop.current.run(until: Date().addingTimeInterval(wait))
    host.layoutSubtreeIfNeeded()
    // macOS 27 draws a shortcut recorder's text twice offscreen (the AppKit cell, gray and offset, plus the
    // label on top). For the capture, swap the recorders' draw(_:) for a plain field pill; restored after.
    var pillClass: AnyClass?
    var swapped: [(NSView, AnyClass)] = []
    func pillRecorders(_ v: NSView) {
      if String(describing: type(of: v)) == "RecorderCocoa" {
        if pillClass == nil, let sub = objc_allocateClassPair(type(of: v), "RecorderPill\(UUID().uuidString.prefix(8))", 0) {
          let imp = imp_implementationWithBlock({ (me: AnyObject, _: NSRect) in
            guard let view = me as? NSView else { return }
            let isDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let b = view.bounds.insetBy(dx: 0.5, dy: 0.5)
            let pill = NSBezierPath(roundedRect: b, xRadius: b.height / 2, yRadius: b.height / 2)
            NSColor(white: isDark ? 0.09 : 1, alpha: 1).setFill()  // the other text fields' fill (sampled)
            pill.fill()
            NSColor(white: isDark ? 0.22 : 0.82, alpha: 1).setStroke()
            pill.lineWidth = 1
            pill.stroke()
          } as @convention(block) (AnyObject, NSRect) -> Void)
          class_addMethod(sub, #selector(NSView.draw(_:)), imp, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
          objc_registerClassPair(sub)
          pillClass = sub
        }
        if let pillClass { swapped.append((v, type(of: v))); object_setClass(v, pillClass) }
      }
      v.subviews.forEach(pillRecorders)
    }
    pillRecorders(host)
    defer { swapped.forEach { object_setClass($0.0, $0.1) } }
    let scale = 2
    func bitmap() throws -> NSBitmapImageRep {
      let rep = try XCTUnwrap(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ))
      rep.size = size
      return rep
    }
    let rep = try bitmap()
    host.cacheDisplay(in: host.bounds, to: rep)
    // Flatten onto the opaque window background: a transparent PNG loses its dark text on GitHub's dark page.
    let flat = try bitmap()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: flat)
    appearance.performAsCurrentDrawingAppearance {
      NSColor.windowBackgroundColor.setFill()
      CGRect(origin: .zero, size: size).fill()
    }
    rep.draw(
      in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver,
      fraction: 1, respectFlipped: false, hints: nil
    )
    NSGraphicsContext.restoreGraphicsState()
    let png = try XCTUnwrap(flat.representation(using: .png, properties: [:]))
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
    try render(PluginsSettingsPane(height: 1480), size: CGSize(width: 760, height: 1480), name: "plugins", wait: 3)
  }
}
