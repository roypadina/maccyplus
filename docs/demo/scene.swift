// MaccyPlus demo. The history popup is the REAL app UI: DemoLayers.swift renders HeaderView / HistoryListView / FooterView (as ContentView
// composes them, minus the glass the kit draws) over fake history to $MACCYPLUS_LAYERS/panel.png, and writes layers.json with the real
// frames (bolt badge, search field) and the real action titles ActionEngine resolves for the top row. Everything else is the kit.
// Source facts are cited as File.swift:line from Maccy/.
import AppKit
import ImageIO
import SwiftUI

private let W = Demo.size.width, H = Demo.size.height
private let env = ProcessInfo.processInfo.environment
private let layersDir = URL(fileURLWithPath: env["MACCYPLUS_LAYERS"]!)
private let assetsDir = URL(fileURLWithPath: env["MACCYPLUS_ASSETS"]!)

// MARK: - layers

private func loadPNG(_ url: URL) -> CGImage { CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)! }
private let layers = try! JSONSerialization.jsonObject(with: Data(contentsOf: layersDir.appendingPathComponent("layers.json"))) as! [String: Any]
private func rect(_ any: Any) -> CGRect {
    let d = any as! [String: Double]
    return CGRect(x: d["x"]!, y: d["y"]!, width: d["w"]!, height: d["h"]!)
}
private let panelImage = loadPNG(layersDir.appendingPathComponent("panel.png"))                 // 450 x 294 pt at the kit's 8/3 px per pt
private let badge = rect((layers["popUpButtons"] as! [Any])[0])                                 // top row's bolt menu, panel points
private let searchField = rect((layers["textFields"] as! [Any])[0])                             // the search NSTextField, panel points
private let topRowActions = ((layers["rows"] as! [[String: Any]])[0]["actions"] as! [String])   // ["Web search"] for the key "ABC-123"

// HistoryItemView.swift rowActions: the first action is suffixed " (default)"; ListItemView.swift Menu rows are Labels with the "bolt" glyph.
private let actionRows: [MenuMock.Row] = topRowActions.enumerated().map { i, title in .item(i == 0 ? "\(title) (default)" : title, symbol: "bolt") }

// MARK: - status item: Defaults[.menuIcon] .maccy = StatusBarMenuImage (template image, AppDelegate.swift:15), drawn white like any template glyph

private func glyphSlot(_ width: CGFloat) -> String {  // reserves the glyph's width in the kit's status item; the glyph is drawn over it
    var s = ""
    while (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width < width { s += " " }
    return s
}
private let glyph: CGImage = {
    let img = loadPNG(assetsDir.appendingPathComponent("LightMenuBar-32w.png"))
    let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
    ctx.draw(img, in: r); ctx.setBlendMode(.sourceIn); ctx.setFillColor(CGColor(gray: 1, alpha: 0.95)); ctx.fill(r)
    return ctx.makeImage()!
}()
private let glyphSize: CGFloat = 16  // LightMenuBar-16w.png is 16 pt wide

@MainActor private func drawBar(_ c: Canvas, app: String) {
    // the frontmost fake app's own menus (kit v2 `menus:`): Editor = TextEdit's, Browser = Safari's
    let menus = app == "Browser" ? ["File", "Edit", "View", "History", "Bookmarks", "Window", "Help"]
                                 : ["File", "Edit", "Format", "View", "Window", "Help"]
    let f = c.menuBar(app: StatusItem(text: glyphSlot(glyphSize)), appName: app, menus: menus)
    c.draw(glyph, in: CGRect(x: f.minX + 8, y: (Demo.barHeight - glyphSize) / 2, width: glyphSize, height: glyphSize))
}

// MARK: - the two other apps on screen (not MaccyPlus): a plain editor with the key selected, and the page that opens (generic, fake data)

private let accent = Color(red: 0.04, green: 0.52, blue: 1.0)

private struct EditorView: View {
    static let size = CGSize(width: 440, height: 204)
    static let padX: CGFloat = 22, padTop: CGFloat = 18, headH: CGFloat = 34, lineH: CGFloat = 28, iconW: CGFloat = 18, gap: CGFloat = 10
    static let font = NSFont.systemFont(ofSize: 15)
    static let before = "Fix ", key = "ABC-123", after = " before the release"
    static let keyLine = 1
    static func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
    /// Centre of the key, in content points (below the title bar).
    static var keyCenter: CGPoint {
        CGPoint(x: padX + iconW + gap + width(before) + width(key) / 2, y: padTop + headH + lineH * CGFloat(keyLine) + lineH / 2)
    }
    let selected: Bool
    var active = true  // inactive window: macOS draws the selection gray
    private func line(_ i: Int, _ text: String) -> some View {
        HStack(spacing: Self.gap) {
            Image(systemName: "square").font(.system(size: 13)).foregroundStyle(.white.opacity(0.45)).frame(width: Self.iconW)
            if i == Self.keyLine {
                HStack(spacing: 0) {
                    Text(Self.before)
                    Text(Self.key).background(selected ? (active ? accent.opacity(0.55) : Color(nsColor: .unemphasizedSelectedTextBackgroundColor)) : .clear)
                    Text(Self.after)
                }
            } else {
                Text(text)
            }
        }
        .font(Font(Self.font)).foregroundStyle(.white.opacity(0.92))
        .frame(height: Self.lineH, alignment: .leading)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Before the release").font(.system(size: 18, weight: .bold)).frame(height: Self.headH, alignment: .leading)
            line(0, "Update the changelog")
            line(1, "")
            line(2, "Tag the build and publish notes")
            line(3, "Tell the team in the channel")
        }
        .padding(.horizontal, Self.padX).padding(.top, Self.padTop)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color(white: 0.13))
    }
}

private struct PageView: View {
    static let size = CGSize(width: 540, height: 292)
    private func bar(_ w: CGFloat) -> some View { RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.12)).frame(width: w, height: 8) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "chevron.left").foregroundStyle(.white.opacity(0.7))
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.35))
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    Text("example.atlassian.net/browse/ABC-123").font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.10)))
            }
            .padding(.horizontal, 14).frame(height: 46).background(Color(white: 0.17))
            VStack(alignment: .leading, spacing: 14) {
                Text("ABC-123").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Text("Fix checkout timeout").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                Text("In progress").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(accent))
                VStack(alignment: .leading, spacing: 9) { bar(420); bar(380); bar(300) }.padding(.top, 6)
                Spacer()
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.12))
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

// MARK: - a menu at an explicit origin (the kit's Canvas.menu only anchors under the menu bar; a SwiftUI Menu drops from its button)

extension Canvas {
    @discardableResult
    func menu(_ rows: [MenuMock.Row], at origin: CGPoint, highlight: Int?, alpha: CGFloat = 1) -> CGRect {
        let frame = CGRect(origin: origin, size: MenuMock.size(rows))
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
}

// MARK: - scenes

@MainActor func maccyPlusScenes() -> [Scene] {
    let editorOrigin = CGPoint(x: 80, y: 58)
    let editorActive = captureWindow(EditorView(selected: false), size: EditorView.size, title: "Release checklist")!
    let editorSelected = captureWindow(EditorView(selected: true), size: EditorView.size, title: "Release checklist")!
    let editorIdle = captureWindow(EditorView(selected: true, active: false), size: EditorView.size, title: "Release checklist", active: false)!
    let page = captureWindow(PageView(), size: PageView.size, title: "Fix checkout timeout")!
    let titleH = CGFloat(editorActive.height) / Demo.scale - EditorView.size.height
    let pageOrigin = CGPoint(x: 250, y: 74)

    // The key is selected by the cursor; PopupPosition.cursor (the default) opens the panel with its top-left at the pointer (PopupPosition.swift:63-65).
    let word = CGPoint(x: editorOrigin.x + EditorView.keyCenter.x, y: editorOrigin.y + titleH + EditorView.keyCenter.y + 8)  // pointer on the lower half of the line
    let panelOrigin = word
    let panelSize = CGSize(width: CGFloat(panelImage.width) / Demo.scale, height: CGFloat(panelImage.height) / Demo.scale)
    let radius = 7.0 + 5.0  // FloatingPanel.swift:70  Popup.cornerRadius + Popup.horizontalPadding
    let badgeCenter = CGPoint(x: panelOrigin.x + badge.midX, y: panelOrigin.y + badge.midY)
    let menuOrigin = CGPoint(x: panelOrigin.x + badge.minX, y: panelOrigin.y + badge.maxY + 2)  // pull-down: left edge on the button, just below
    let rowFrames = MenuMock.frames(actionRows).map { $0.offsetBy(dx: menuOrigin.x, dy: menuOrigin.y) }
    let itemCenter = CGPoint(x: rowFrames[0].maxX - 22, y: rowFrames[0].midY)  // right end of the row, clear of the title text
    let caretRect = CGRect(x: panelOrigin.x + searchField.minX + 2, y: panelOrigin.y + searchField.minY, width: 1, height: searchField.height)

    func caretOn(_ t: Double) -> Bool { t.truncatingRemainder(dividingBy: 1.06) < 0.53 }  // NSTextView insertion point blink
    func drawCaret(_ c: Canvas, _ t: Double, alpha: CGFloat) {
        guard caretOn(t) else { return }
        c.ctx.setFillColor(CGColor(gray: 1, alpha: 0.92 * alpha)); c.ctx.fill(caretRect)
    }
    func drawPanel(_ c: Canvas, alpha: CGFloat) { c.panel(panelImage, at: panelOrigin, radius: radius, alpha: alpha) }

    // 1. copy: select the key, copy it (⌘C)
    let path1 = CursorPath(start: CGPoint(x: W * 0.74, y: H * 0.64),
                           moves: [.init(t0: 0.15, t1: 0.85, to: word)], clicks: [1.0])
    let s1 = Scene(name: "copy", duration: 2.8, caption: "Copy a Jira key, as usual") { t in
        let c = Canvas()
        drawBar(c, app: "Editor")
        c.window(t >= 1.0 ? editorSelected : editorActive, at: editorOrigin)
        let click = path1.click(t)
        c.cursor(at: path1.position(t), alpha: CGFloat(ramp(t, 0.05, 0.2)), press: click.press, pulse: click.pulse)
        return c.image
    }

    // 2. ⌥⌘C: the panel opens at the pointer, top row selected, search focused; the pointer heads for the bolt
    let path2 = CursorPath(start: word, moves: [.init(t0: 1.75, t1: 2.45, to: badgeCenter)])
    let s2 = Scene(name: "history", duration: 3.0, caption: "⌥⌘C opens your history, newest first") { t in
        let c = Canvas()
        drawBar(c, app: "Editor")
        c.window(editorSelected, at: editorOrigin)
        let open = ramp(t, 0.30, 0.36)
        if open > 0 { drawPanel(c, alpha: CGFloat(open)); drawCaret(c, t - 0.30, alpha: CGFloat(open)) }
        c.cursor(at: path2.position(t), alpha: 1)
        return c.image
    }

    // 3. click the bolt: the pull-down lists the actions the matching rule offers; hover follows the pointer
    let path3 = CursorPath(start: badgeCenter, moves: [.init(t0: 1.15, t1: 1.70, to: itemCenter)], clicks: [0.30])
    let s3 = Scene(name: "actions", duration: 3.2, caption: "Click the bolt, or press ⌥⌘1") { t in
        let c = Canvas()
        drawBar(c, app: "Editor")
        c.window(editorSelected, at: editorOrigin)
        drawPanel(c, alpha: 1); drawCaret(c, t + 2.7, alpha: 1)
        if t >= 0.30 {
            let p = path3.position(t)
            c.menu(actionRows, at: menuOrigin, highlight: rowFrames[0].contains(p) ? 0 : nil, alpha: CGFloat(ramp(t, 0.30, 0.38)))
        }
        let click = path3.click(t)
        c.cursor(at: path3.position(t), alpha: 1, press: click.press, pulse: click.pulse)
        return c.image
    }

    // 4. run it: menu and panel close at once (HistoryItemView.swift rowActions: run(); popup.close()), the URL opens in the browser
    let path4 = CursorPath(start: itemCenter, moves: [], clicks: [0.30])
    let s4 = Scene(name: "open", duration: 3.2, caption: "The ticket opens in your browser") { t in
        let c = Canvas()
        let opened = ramp(t, 0.50, 0.65)
        drawBar(c, app: opened > 0.5 ? "Browser" : "Editor")
        c.window(opened > 0 ? editorIdle : editorSelected, at: editorOrigin)
        if t < 0.30 {
            drawPanel(c, alpha: 1); drawCaret(c, t + 5.9, alpha: 1)
            c.menu(actionRows, at: menuOrigin, highlight: 0)
        }
        if opened > 0 { c.window(page, at: pageOrigin, alpha: CGFloat(opened)) }
        let click = path4.click(t)
        c.cursor(at: itemCenter, alpha: CGFloat(1 - ramp(t, 0.75, 1.05)), press: click.press, pulse: click.pulse)
        return c.image
    }
    return [s1, s2, s3, s4]
}

@main struct MaccyPlusDemo {
    @MainActor static func main() { Demo.run(scenes: maccyPlusScenes()) }
}
