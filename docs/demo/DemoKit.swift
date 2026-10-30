// DemoKit — shared by every Padina app demo. Renders a "screen recording" offscreen: nothing is ever shown on
// the real screen, no clicks, no screencapture. Layout canvas 960x600 pt, composed at 2560x1600 px, downscaled to 1280x800.
//
//   Canvas()                      wallpaper-filled canvas, y-down point coordinates (lay out relative to Demo.size)
//   canvas.menuBar(app:...)       house menu bar (transparent, macOS 26); returns the app status item's frame
//   canvas.menu(rows, under:, hover:)  macOS menu (MenuMock) under a status item; hover highlights enabled rows only
//   canvas.window / .panel        glass panel or captured NSWindow (real title bar; SwiftUI view or NSViewController) with house shadow
//   canvas.cursor                 eased cursor with click pulse
//   Scene(name:duration:caption:) { t in ... }  one scene; Demo.run(scenes:) draws captions, crossfades, loops, writes PNG frames
//   encode.sh                     frames -> GIF + MP4 + poster
//
// Used unchanged by every demo (see README.md). Kit changes go through the main thread first so all demos stay identical.

import AppKit
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Constants

enum Demo {
    static let size = CGSize(width: 960, height: 600)       // layout canvas, points: everything is laid out relative to this
    static let pixels = CGSize(width: 2560, height: 1600)   // what the canvas is rendered at
    static let out = CGSize(width: 1280, height: 800)       // PNG frames / MP4 size (pixels downscaled 2:1)
    static let scale: CGFloat = pixels.width / size.width   // 2.667 px per point
    static let barHeight: CGFloat = 28
    static let clock = "Thu Oct 30 9:41 AM"
    static var bounds: CGRect { CGRect(origin: .zero, size: size) }
}

/// Deterministic "now" for views that read the time through TimelineView (the shim below shadows SwiftUI's).
enum DemoClock { @MainActor static var now = Date() }

struct DemoTimelineContext { let date: Date }

struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
    let content: (DemoTimelineContext) -> Content
    init(_ schedule: Schedule, @ViewBuilder content: @escaping (DemoTimelineContext) -> Content) { self.content = content }
    var body: some View { content(DemoTimelineContext(date: MainActor.assumeIsolated { DemoClock.now })) }
}

// MARK: - Wallpaper + materials (generated once, no Apple artwork)

enum Wallpaper {
    static let image: CGImage = {
        let w = Int(Demo.pixels.width), h = Int(Demo.pixels.height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.scaleBy(x: Demo.scale, y: Demo.scale)
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
        let H = Demo.size.height, W = Demo.size.width, k = W / 1280  // glow positions/radii below were drawn on 1280x800
        // base: top-to-bottom (CG origin is bottom-left here)
        let base = CGGradient(colorsSpace: cs, colors: [rgb(0.03, 0.09, 0.20), rgb(0.07, 0.07, 0.24), rgb(0.07, 0.08, 0.27)] as CFArray,
                              locations: [0, 0.55, 1])!
        c.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: H), options: [])
        func glow(_ x: CGFloat, _ yTop: CGFloat, _ r: CGFloat, _ col: CGColor) {
            let g = CGGradient(colorsSpace: cs, colors: [col, col.copy(alpha: 0.45 * col.alpha)!, col.copy(alpha: 0)!] as CFArray, locations: [0, 0.45, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: x * k, y: H - yTop * k), startRadius: 0, endCenter: CGPoint(x: x * k, y: H - yTop * k), endRadius: r * k, options: [])
        }
        glow(120, 780, 760, rgb(0.07, 0.55, 0.78, 0.62))   // teal, bottom-left
        glow(1180, 40, 720, rgb(0.52, 0.22, 0.86, 0.60))   // violet, top-right
        glow(900, 760, 560, rgb(0.93, 0.30, 0.55, 0.38))   // pink, bottom-right
        glow(430, 230, 560, rgb(0.17, 0.33, 0.96, 0.34))   // blue, upper-left
        glow(640, 430, 380, rgb(0.55, 0.78, 1.0, 0.10))    // faint lift in the middle
        // vignette
        let vg = CGGradient(colorsSpace: cs, colors: [rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.35)] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(vg, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: 380 * k, endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: 900 * k, options: .drawsAfterEndLocation)
        // static +-1.5 level noise so the dark gradient does not band (deterministic: GIF dither stays stable)
        let p = c.data!.assumingMemoryBound(to: UInt8.self), bpr = c.bytesPerRow
        var s: UInt32 = 0x9E3779B9
        for y in 0..<h { for x in 0..<w {
            s = s &* 1664525 &+ 1013904223
            let n = Int((s >> 24) % 4) - 1 // -1...2 (mean .5)
            let o = y * bpr + x * 4
            for k in 0..<3 { p[o + k] = UInt8(max(0, min(255, Int(p[o + k]) + n))) }
        } }
        return c.makeImage()!
    }()

    /// Wallpaper blurred and saturated once: the backdrop every glass material samples.
    static let blurred: CGImage = {
        let ci = CIImage(cgImage: image)
        let out = ci.clampedToExtent().applyingGaussianBlur(sigma: 24 * Demo.scale)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: 0.0, kCIInputContrastKey: 1.0])
        return CIContext().createCGImage(out, from: ci.extent)!
    }()
}

enum Material {
    case menu, panel
    var tint: CGColor {
        switch self {
        case .menu: CGColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 0.60)
        case .panel: CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.60)
        }
    }
}

// MARK: - Canvas

struct StatusItem { var symbol: String? = nil; var text: String? = nil }

@MainActor
final class Canvas {
    let ctx: CGContext
    private(set) var statusFrame = CGRect.zero

    init(background: CGImage? = Wallpaper.image) {
        let w = Int(Demo.pixels.width), h = Int(Demo.pixels.height)
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: Demo.scale, y: Demo.scale)
        ctx.translateBy(x: 0, y: Demo.size.height)
        ctx.scaleBy(x: 1, y: -1)  // y-down points from here on
        if let background { draw(background, in: Demo.bounds) }
    }

    var image: CGImage { ctx.makeImage()! }

    func draw(_ img: CGImage, in r: CGRect, alpha: CGFloat = 1) {
        ctx.saveGState(); ctx.setAlpha(alpha)
        ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    /// Draw a `size`-pt image (as returned by `renderView`) with its top-left at `origin`.
    func draw(_ img: CGImage, at origin: CGPoint, alpha: CGFloat = 1) {
        draw(img, in: CGRect(origin: origin, size: CGSize(width: CGFloat(img.width) / Demo.scale, height: CGFloat(img.height) / Demo.scale)), alpha: alpha)
    }

    private func appKit(_ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: glass

    func shadow(_ path: CGPath, blur: CGFloat, dy: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        let outside = CGMutablePath(); outside.addRect(Demo.bounds.insetBy(dx: -2000, dy: -2000)); outside.addPath(path)
        ctx.addPath(outside); ctx.clip(using: .evenOdd)   // only the part outside the shape survives, like a real window shadow
        ctx.setShadow(offset: CGSize(width: 0, height: -dy * Demo.scale), blur: blur * Demo.scale, color: CGColor(gray: 0, alpha: alpha))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.addPath(path); ctx.fillPath()
        ctx.restoreGState()
    }

    func material(_ m: Material, path: CGPath) {
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        draw(Wallpaper.blurred, in: Demo.bounds)
        ctx.setFillColor(m.tint); ctx.fill(Demo.bounds)
        ctx.restoreGState()
    }

    func hairline(_ path: CGPath, alpha: CGFloat) {
        ctx.saveGState(); ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: alpha)); ctx.setLineWidth(0.75); ctx.strokePath(); ctx.restoreGState()
    }

    static func continuousRect(_ r: CGRect, radius: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r).cgPath
    }

    // MARK: menu bar

    /// Transparent macOS 26 menu bar (text straight on the wallpaper): Finder + menus on the left, third-party item then
    /// system icons then clock on the right. Returns the app item's frame (its highlight rect), so scenes can point the cursor at it and drop a menu under it.
    @discardableResult
    func menuBar(app: StatusItem, appActive: Bool = false, clock: String = Demo.clock, appName: String = "Finder",
                 menus: [String] = ["File", "Edit", "View", "Go", "Window", "Help"]) -> CGRect {
        let W = Demo.size.width, h = Demo.barHeight

        let white = NSColor(white: 1, alpha: 0.95)
        func attr(_ s: String, _ weight: NSFont.Weight) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: weight), .foregroundColor: white])
        }
        func symbol(_ name: String, _ pt: CGFloat = 13) -> NSImage? {
            let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .medium).applying(.init(paletteColors: [white]))
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        }
        func put(_ s: NSAttributedString, x: CGFloat) { appKit { s.draw(at: CGPoint(x: x, y: (h - s.size().height) / 2)) } }
        func put(_ i: NSImage, x: CGFloat) {
            appKit { i.draw(in: CGRect(x: x, y: (h - i.size.height) / 2, width: i.size.width, height: i.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        }

        var x: CGFloat = 16
        for (i, t) in ([appName] + menus).enumerated() {  // menus = the frontmost app's menu titles (default Finder)
            let a = attr(t, i == 0 ? .bold : .regular); put(a, x: x); x += a.size().width + 19
        }

        var rx = W - 16
        let clockA = attr(clock, .regular); rx -= clockA.size().width; put(clockA, x: rx); rx -= 18
        for name in ["switch.2", "battery.100", "wifi"] {
            guard let i = symbol(name) else { continue }
            rx -= i.size.width; put(i, x: rx); rx -= 16
        }
        // app item
        let img = app.symbol.flatMap { symbol($0) }, txt = app.text.map { attr($0, .regular) }
        let contentW = (img?.size.width ?? 0) + (img != nil && txt != nil ? 5 : 0) + (txt?.size().width ?? 0)
        let frame = CGRect(x: rx - contentW - 16 + 8, y: 3, width: contentW + 16, height: h - 6)
        if appActive { ctx.setFillColor(CGColor(gray: 1, alpha: 0.22)); ctx.addPath(Canvas.continuousRect(frame, radius: 8)); ctx.fillPath() }
        var ax = frame.minX + 8
        if let img { put(img, x: ax); ax += img.size.width + (txt != nil ? 5 : 0) }
        if let txt { put(txt, x: ax) }
        statusFrame = frame
        return frame
    }

    // MARK: menus + panels + windows

    static func menuFrame(_ rows: [MenuMock.Row], under item: CGRect) -> CGRect {
        let size = MenuMock.size(rows)
        return CGRect(origin: CGPoint(x: min(item.minX, Demo.size.width - size.width - 8), y: Demo.barHeight + 2), size: size)
    }

    /// The row a pointer at `p` (canvas points) highlights in a menu dropped under `item`: enabled items only, like a real menu.
    static func hoverRow(_ rows: [MenuMock.Row], under item: CGRect, at p: CGPoint) -> Int? {
        let origin = menuFrame(rows, under: item).origin
        for (i, f) in MenuMock.frames(rows).enumerated() where f.offsetBy(dx: origin.x, dy: origin.y).contains(p) {
            if case .item(_, _, _, _, true) = rows[i] { return i }
        }
        return nil
    }

    /// Menu dropped under `item` (a status item frame). Returns its frame. `hover` is the cursor position: the enabled
    /// row under it is highlighted (disabled rows, headers and separators never are).
    @discardableResult
    func menu(_ rows: [MenuMock.Row], under item: CGRect, hover: CGPoint? = nil, alpha: CGFloat = 1) -> CGRect {
        let frame = Canvas.menuFrame(rows, under: item), origin = frame.origin
        let highlight = hover.flatMap { Canvas.hoverRow(rows, under: item, at: $0) }
        let path = Canvas.continuousRect(frame, radius: MenuMock.radius)
        ctx.saveGState(); ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        shadow(path, blur: 26, dy: 10, alpha: 0.38)
        material(.menu, path: path)
        if let img = MenuMock.render(rows, highlight: highlight) { draw(img, at: origin) }
        hairline(path, alpha: 0.16)
        ctx.endTransparencyLayer(); ctx.restoreGState()
        return frame
    }

    /// A borderless glass panel: `content` is a SwiftUI render with a transparent material area (what `renderView` returns).
    func panel(_ content: CGImage, at origin: CGPoint, radius: CGFloat, alpha: CGFloat = 1) {
        let size = CGSize(width: CGFloat(content.width) / Demo.scale, height: CGFloat(content.height) / Demo.scale)
        let path = Canvas.continuousRect(CGRect(origin: origin, size: size), radius: radius)
        ctx.saveGState(); ctx.setAlpha(alpha); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        shadow(path, blur: 44, dy: 18, alpha: 0.42)
        shadow(path, blur: 8, dy: 2, alpha: 0.30)
        material(.panel, path: path)
        draw(content, at: origin)
        ctx.endTransparencyLayer(); ctx.restoreGState()
    }

    /// A captured NSWindow image (real title bar). The kit rounds the corners (`radius`: 16 plain, 26 with a toolbar on
    /// macOS 26), adds the hairline edge and the house shadow.
    func window(_ content: CGImage, at origin: CGPoint, radius: CGFloat = 16, alpha: CGFloat = 1) {
        let size = CGSize(width: CGFloat(content.width) / Demo.scale, height: CGFloat(content.height) / Demo.scale)
        let path = Canvas.continuousRect(CGRect(origin: origin, size: size), radius: radius)
        ctx.saveGState(); ctx.setAlpha(alpha); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        shadow(path, blur: 50, dy: 22, alpha: 0.45)
        shadow(path, blur: 8, dy: 2, alpha: 0.30)
        ctx.saveGState(); ctx.addPath(path); ctx.clip(); draw(content, at: origin); ctx.restoreGState()
        hairline(path, alpha: 0.20)
        ctx.endTransparencyLayer(); ctx.restoreGState()
    }

    // MARK: cursor + caption

    /// The system arrow (NSCursor.arrow), tip at `pos`. `press` 0...1 shrinks it; `pulse` 0...1 is the click ripple's progress.
    func cursor(at pos: CGPoint, alpha: CGFloat = 1, press: CGFloat = 0, pulse: CGFloat? = nil) {
        if let p = pulse, p > 0, p < 1 {
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.30 * (1 - p)))
            let r = 5 + 17 * p
            ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: 2 * r, height: 2 * r))
        }
        guard alpha > 0 else { return }
        let cur = NSCursor.arrow, s = 1 - 0.10 * press
        let size = CGSize(width: cur.image.size.width * s, height: cur.image.size.height * s)
        let origin = CGPoint(x: pos.x - cur.hotSpot.x * s, y: pos.y - cur.hotSpot.y * s)
        appKit {
            NSGraphicsContext.current?.cgContext.setAlpha(alpha)
            cur.image.draw(in: CGRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// One short sentence, bottom centre: 17 pt semibold white on 55 % black, 14 pt radius. Drawn by `Demo.run` from `Scene.caption`.
    func caption(_ text: String, alpha: CGFloat = 1) {
        guard alpha > 0, !text.isEmpty else { return }
        let a = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor.white])
        let ts = a.size(), box = CGSize(width: ts.width + 40, height: 42)
        let frame = CGRect(x: (Demo.size.width - box.width) / 2, y: Demo.size.height - 34 - box.height, width: box.width, height: box.height)
        ctx.saveGState(); ctx.setAlpha(alpha)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.55)); ctx.addPath(Canvas.continuousRect(frame, radius: 14)); ctx.fillPath()
        appKit { a.draw(at: CGPoint(x: frame.minX + 20, y: frame.minY + (box.height - ts.height) / 2)) }
        ctx.restoreGState()
    }
}

// MARK: - SwiftUI -> CGImage (transparent, dark, 2x)

@MainActor
func renderView<V: View>(_ view: V) -> CGImage? {
    let r = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    r.scale = Demo.scale
    r.isOpaque = false
    return r.cgImage
}

/// An app window in real AppKit chrome (title bar, traffic lights), captured offscreen: the window is never ordered front.
private final class CaptureWindow: NSWindow {
    var forceActive = true
    override var isKeyWindow: Bool { forceActive }
    override var isMainWindow: Bool { forceActive }
    // Private AppKit hooks the title bar / controls ask whether to draw in the active (coloured) state. Offscreen the
    // window is never key, so answer yes. Dev tool only: if a macOS update drops them the window just renders inactive.
    @objc(hasKeyAppearance) func demoHasKeyAppearancePublic() -> Bool { forceActive }  // AppKit-backed controls (NSSwitch...) ask this one
    @objc(_hasKeyAppearance) func demoHasKeyAppearance() -> Bool { forceActive }
    @objc(_hasActiveAppearance) func demoHasActiveAppearance() -> Bool { forceActive }
    @objc(_hasMainAppearance) func demoHasMainAppearance() -> Bool { forceActive }
}

@MainActor
func captureWindow<V: View>(_ content: V, size: CGSize, title: String, active: Bool = true) -> CGImage? {
    let w = CaptureWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false, screen: nil)
    w.forceActive = active
    w.title = title
    w.appearance = NSAppearance(named: .darkAqua)
    w.contentView = NSHostingView(rootView: content.environment(\.colorScheme, .dark).environment(\.controlActiveState, active ? .key : .inactive))
    w.setContentSize(size)
    return snapshot(w)
}

/// Same capture for a window built the way real apps build Settings: `NSWindow(contentViewController:)`, e.g. an
/// `NSTabViewController` with `tabStyle = .toolbar` whose items host SwiftUI via `NSHostingController` (set
/// `sizingOptions = .preferredContentSize` on each host, as the apps do). The window sizes itself from the controller; the
/// buttons in `disabledButtons` render dimmed (real Settings windows have no minimise/zoom).
@MainActor
func captureWindow(controller: NSViewController, title: String, styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable],
                   disabledButtons: [NSWindow.ButtonType] = [.miniaturizeButton, .zoomButton], active: Bool = true) -> CGImage? {
    let w = CaptureWindow(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: false, screen: nil)
    w.forceActive = active
    w.contentViewController = controller
    w.title = title
    w.appearance = NSAppearance(named: .darkAqua)
    for b in disabledButtons { w.standardWindowButton(b)?.isEnabled = false }
    w.layoutIfNeeded()
    return snapshot(w)
}

@MainActor
private func snapshot(_ w: NSWindow) -> CGImage? {
    guard let frameView = w.contentView?.superview else { return nil }
    frameView.layoutSubtreeIfNeeded()
    let b = frameView.bounds
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((b.width * Demo.scale).rounded(.up)), pixelsHigh: Int((b.height * Demo.scale).rounded(.up)),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = b.size
    frameView.cacheDisplay(in: b, to: rep)
    return rep.cgImage
}

// MARK: - MenuMock: macOS menu, drawn from the app's real item titles

struct MenuMock: View {
    enum Row {
        case item(String, symbol: String? = nil, key: String? = nil, submenu: Bool = false, enabled: Bool = true)
        case header(String)
        case separator
    }
    static let radius: CGFloat = 14, pad: CGFloat = 5, inset: CGFloat = 6, rowH: CGFloat = 24, sepH: CGFloat = 11
    static let font = NSFont.menuFont(ofSize: 0)
    static let iconCol: CGFloat = 26

    let rows: [Row]
    let highlight: Int?

    static func hasIcons(_ rows: [Row]) -> Bool { rows.contains { if case .item(_, let s, _, _, _) = $0 { return s != nil } else { return false } } }

    static func height(_ r: Row) -> CGFloat { if case .separator = r { return sepH } else { return rowH } }

    static func size(_ rows: [Row]) -> CGSize {
        let icons = hasIcons(rows)
        var w: CGFloat = 0
        for r in rows {
            guard case .item(let t, _, let k, let sub, _) = r else { continue }
            let tw = (t as NSString).size(withAttributes: [.font: font]).width
            let kw = k.map { ($0 as NSString).size(withAttributes: [.font: font]).width + 22 } ?? (sub ? 26 : 0)
            w = max(w, tw + kw)
        }
        return CGSize(width: ceil(2 * inset + 2 * 9 + (icons ? iconCol : 0) + w + 18), height: 2 * pad + rows.map(height).reduce(0, +))
    }

    /// Row frames in menu-local points (for hit-testing the cursor).
    static func frames(_ rows: [Row]) -> [CGRect] {
        var y = pad, out: [CGRect] = []
        let w = size(rows).width
        for r in rows { out.append(CGRect(x: 0, y: y, width: w, height: height(r))); y += height(r) }
        return out
    }

    @MainActor static func render(_ rows: [Row], highlight: Int?) -> CGImage? { renderView(MenuMock(rows: rows, highlight: highlight)) }

    private var accent: Color { Color(red: 0.04, green: 0.52, blue: 1.0) }

    var body: some View {
        let icons = Self.hasIcons(rows), size = Self.size(rows)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                switch r {
                case .separator:
                    Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                        .padding(.horizontal, 14).frame(height: Self.sepH)
                case .header(let t):
                    Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        .padding(.leading, Self.inset + 9).frame(maxWidth: .infinity, alignment: .leading).frame(height: Self.rowH)
                case .item(let t, let sym, let key, let sub, let enabled):
                    let on = i == highlight
                    HStack(spacing: 0) {
                        if icons {
                            Group { if let sym { Image(systemName: sym).font(.system(size: 12, weight: .regular)) } else { Color.clear } }
                                .frame(width: Self.iconCol - 6, alignment: .leading).padding(.trailing, 6)
                        }
                        Text(t).font(Font(Self.font)).fixedSize()
                        Spacer(minLength: 16)
                        if let key { Text(key).font(Font(Self.font)).foregroundStyle(.white.opacity(on ? 0.85 : 0.55)) }
                        if sub { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(on ? 0.9 : 0.55)) }
                    }
                    .foregroundStyle(.white.opacity(enabled ? 0.96 : 0.35))
                    .padding(.horizontal, 9)
                    .frame(height: Self.rowH)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? accent : .clear))
                    .padding(.horizontal, Self.inset)
                }
            }
        }
        .padding(.vertical, Self.pad)
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

// MARK: - Cursor path + easing

func ease(_ x: Double) -> Double { let t = max(0, min(1, x)); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func easeOut(_ x: Double) -> Double { let t = max(0, min(1, x)); return 1 - pow(1 - t, 3) }
/// 0 before `a`, 1 after `b`, linear between.
func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { b > a ? max(0, min(1, (t - a) / (b - a))) : (t >= a ? 1 : 0) }

/// Waypoints with eased glides (~0.5 s) along a slight arc, plus click times.
struct CursorPath {
    struct Move { var t0: Double; var t1: Double; var to: CGPoint }
    var start: CGPoint
    var moves: [Move]
    var clicks: [Double] = []

    func position(_ t: Double) -> CGPoint {
        var from = start
        for m in moves {
            if t < m.t0 { return from }
            if t < m.t1 {
                let e = CGFloat(ease((t - m.t0) / (m.t1 - m.t0)))
                let d = CGPoint(x: m.to.x - from.x, y: m.to.y - from.y)
                let bow = CGPoint(x: -d.y * 0.06, y: d.x * 0.06)   // perpendicular nudge: a hand does not move in a ruler line
                let k = 4 * e * (1 - e)
                return CGPoint(x: from.x + d.x * e + bow.x * k, y: from.y + d.y * e + bow.y * k)
            }
            from = m.to
        }
        return from
    }
    /// press 0...1 (cursor dips for 0.14 s), pulse 0...1 (ripple over 0.40 s) for the click nearest before `t`.
    func click(_ t: Double) -> (press: CGFloat, pulse: CGFloat?) {
        for c in clicks where t >= c && t < c + 0.40 {
            let press = t < c + 0.14 ? CGFloat(sin((t - c) / 0.14 * .pi)) : 0
            return (press, CGFloat((t - c) / 0.40))
        }
        return (0, nil)
    }
}

// MARK: - Timeline

struct Scene {
    var name: String
    var duration: Double
    var caption: String = ""   // one short sentence (<= 9 words); Demo.run draws it, fading old -> new at scene changes
    var render: @MainActor (_ t: Double) -> CGImage   // t = seconds since the scene began; may exceed duration during a crossfade
}

extension Demo {
    @MainActor static func mix(_ a: CGImage, _ b: CGImage, _ alpha: Double) -> CGImage {
        let c = Canvas(background: nil)
        c.draw(a, in: bounds); c.draw(b, in: bounds, alpha: CGFloat(alpha))
        return c.image
    }

    static func downscaled(_ img: CGImage) -> CGImage {
        let c = CGContext(data: nil, width: Int(out.width), height: Int(out.height), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.interpolationQuality = .high
        c.draw(img, in: CGRect(origin: .zero, size: out))
        return c.makeImage()!
    }

    static func writePNG(_ img: CGImage, to url: URL) {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
    }

    /// Renders every frame of the timeline to `<out>/%04d.png` (1280x800). Scene i+1 crossfades in over `fade` seconds; the last
    /// `fade` seconds dissolve back into the first scene's opening frame so the loop is clean. Captions are drawn here, after
    /// the crossfade, so two pills never overlap: a changed caption fades out over 0-0.12 s after the cut, the new one in over
    /// 0.12-0.35 s (the first scene's in over 0.12-0.35 s from the start; the last one fades out as the loop dissolve begins).
    /// Usage: `<exe> <out-dir> [fps=30] [--hires] [--at t1,t2]` (--hires writes the 2560x1600 frames).
    @MainActor static func run(scenes: [Scene], fade: Double = 0.2) {
        _ = NSApplication.shared
        let args = Array(CommandLine.arguments.dropFirst())
        guard let outArg = args.first else { print("usage: exe <out-dir> [fps] [--hires]"); exit(2) }
        let out = URL(fileURLWithPath: outArg)
        let fps = Double(args.dropFirst().first(where: { Double($0) != nil }) ?? "30")!
        let hires = args.contains("--hires")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        var starts: [Double] = [], acc = 0.0
        for s in scenes { starts.append(acc); acc += s.duration }
        let total = scenes.map(\.duration).reduce(0, +)
        let n = Int((total * fps).rounded())
        func caption(_ i: Int, _ local: Double, _ t: Double) -> (String, Double) {
            let cur = scenes[i].caption
            var (text, alpha) = (cur, 1.0)
            if i == 0 { alpha = ramp(local, 0.12, 0.35) }
            else if cur != scenes[i - 1].caption {
                if local < 0.12 { (text, alpha) = (scenes[i - 1].caption, 1 - ramp(local, 0, 0.12)) } else { alpha = ramp(local, 0.12, 0.35) }
            }
            if t > total - fade { alpha *= 1 - ramp(t, total - fade, total - fade + 0.12) }
            return (text, easeOut(alpha))
        }
        func frame(_ t: Double) -> CGImage {
            var i = starts.lastIndex(where: { $0 <= t + 1e-9 }) ?? 0
            i = min(i, scenes.count - 1)
            let local = t - starts[i]
            var img = scenes[i].render(local)
            if i > 0, local < fade { img = mix(scenes[i - 1].render(scenes[i - 1].duration + local), img, ease(local / fade)) }
            if t > total - fade { img = mix(img, scenes[0].render(0), ease((t - (total - fade)) / fade)) }
            let (text, alpha) = caption(i, local, t)
            if alpha > 0, !text.isEmpty {
                let c = Canvas(background: nil)
                c.draw(img, in: bounds); c.caption(text, alpha: CGFloat(alpha))
                img = c.image
            }
            return img
        }
        if let at = args.firstIndex(of: "--at") {  // preview: `--at 1.5,6.2` writes just those instants (full 2560x1600) as at-<t>.png
            for t in args[at + 1].split(separator: ",").compactMap({ Double($0) }) { writePNG(frame(t), to: out.appendingPathComponent("at-\(t).png")) }
            return
        }
        let t0 = Date()
        for f in 0..<n {
            let img = frame(Double(f) / fps)
            writePNG(hires ? img : downscaled(img), to: out.appendingPathComponent(String(format: "%04d.png", f)))
            if f % 30 == 0 { print("frame \(f)/\(n)  \(String(format: "%.1f", Date().timeIntervalSince(t0)))s") }
        }
        print("done: \(n) frames, \(total) s @ \(fps) fps -> \(out.path)")
    }
}
