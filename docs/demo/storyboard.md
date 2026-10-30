# MaccyPlus demo — storyboard (12.2 s, loops)

Real code: the history popup is the app's own UI. `DemoLayers.swift` renders `HeaderView` / `HistoryListView` / `FooterView` (composed as
`ContentView` does, minus the glass backdrop the kit draws) over fake history in an app-hosted XCTest run (throwaway bundle id
`com.royp.MaccyPlusShots`, a temp copy of the repo, never the pasteboard or any real history) to a transparent PNG at the kit's 8/3 px per pt,
and writes `layers.json`: the real frames (bolt badge, search field) and the action titles `ActionEngine.resolvedActions` returns for the
top row. The scene reads both, so the row text, the `⚡1` / `⚡2` badges, the `⌘1…⌘6` hints, the footer and the menu title all come from
the app. Menu item = `HistoryItemView.rowActions` ("Web search (default)", `bolt` glyph). Status item = the real `StatusBarMenuImage`
(`AppDelegate.swift:15`), tinted white like any template glyph. Fake data: key "ABC-123", `example.com`, `example.atlassian.net`, a
generic "Release checklist" editor and a generic browser page (the only things that are not MaccyPlus). Rule shown = README's Jira rule
(regex `^[A-Z]{2,5}-\d+$` → `builtin.webSearch`, template `https://example.atlassian.net/browse/{query}`) + the shipped presets.

| # | Scene | Start | Dur | What happens | Caption |
|---|-------|-------|-----|--------------|---------|
| 1 | copy | 0.0 | 2.8 | Editor window, menu bar shows the MaccyPlus glyph. Pointer glides to the key in "Fix ABC-123 before the release", click: the key is selected (copied with ⌘C). | Copy a Jira key, as usual |
| 2 | history | 2.8 | 3.0 | ⌥⌘C: the panel appears at once with its top-left at the pointer (`PopupPosition.cursor`, the default, `PopupPosition.swift:63`), newest copy on top and selected, search focused (caret blinks). Pointer heads for the top row's bolt badge. | ⌥⌘C opens your history, newest first |
| 3 | actions | 5.8 | 3.2 | Click the badge: the pull-down opens under it with the action the matching rule offers, "Web search (default)". Pointer moves onto it, row highlights. | Click the bolt, or press ⌥⌘1 |
| 4 | open | 9.0 | 3.2 | Click: menu and panel close at once (`HistoryItemView.swift` rowActions: `run()` then `popup.close()`); the page for `example.atlassian.net/browse/ABC-123` opens in the browser, the editor goes inactive; pointer fades. | The ticket opens in your browser |

Transitions: 0.2 s crossfade between scenes; captions fade old 0–0.12 s / new 0.12–0.35 s; the last 0.2 s dissolves into scene 1's first frame (clean loop).
Cursor: system arrow, eased glides on a slight arc, click = dip + ripple; visible only while it points at something.
Notes: no focus ring is drawn on the search field — it is a SwiftUI `.plain` TextField (`SearchFieldView.swift:31`); only the caret blinks (not verified against a
live capture). The pull-down menu is drawn with the kit's MenuMock at an explicit origin (a local `Canvas.menu(_:at:)` extension, same body as the kit's
`Canvas.menu(_:under:)`, which only anchors under the menu bar; NtfyBar does the same). Glass = kit blurred wallpaper + tint, not Liquid Glass.
Render: `./render.sh` (xcodebuild test in a temp repo copy → swiftc kit + scene → 30 fps frames → encode). Needs Xcode; first run builds the app (several minutes).
