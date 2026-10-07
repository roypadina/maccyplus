# Changelog

All notable changes to MaccyPlus are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.8.0] - 2026-10-07

### Added
- Agent clipboard API: `MaccyPlus history list|get|add|update|pin|unpin|top|copy|delete` lets AI agents leave values in history with a label and a note, and manage items like the user can.
- History items show an agent-set label chip; the note appears on hover and in the preview; search matches labels and notes.
- Claude Code plugin [`maccyplus-clipboard`](https://github.com/roypadina/padina-claude-code-plugins/tree/main/maccyplus-clipboard) teaches Claude to use it.

## [2.7.3] - 2026-10-03

### Changed
- New About window: everything fits, MaccyPlus credits and Ko-fi up front, links point to the MaccyPlus fork; original Maccy credits kept below.

## [2.7.2] - 2026-10-03

### Changed
- About panel keeps the original Maccy credits first; MaccyPlus credits and Ko-fi link follow below.

## [2.7.1] - 2026-10-03

### Added
- About panel credits the author and links to Ko-fi and GitHub; README Ko-fi support section.

## [2.7.0] - 2026-10-02

### Changed
- Synced with upstream Maccy 2.7.1.
- New and updated translations.

### Added
- Copy text from images (OCR button in preview), image dimensions in preview, HEX color swatches, toggle to open the preview automatically.
- Liquid Glass app icon, native text view for long text, VoiceOver improvements.

### Fixed
- macOS 26 hang on titles containing U+FFFC.
- Crash copying the bottom-most pinned item at full capacity.
- Wrong selection after deleting the first unpinned item; orphaned history content.
- Popup stays on the active screen and above Chrome autofill; minimum popup height of 3 items.

## [2.6.10] - 2026-09-15

### Fixed
- Editing or deleting an action left its keyboard shortcut registered system-wide (beep on press, key combination blocked for future actions). Rule reloads now clear those leftovers.

## [2.6.9] - 2026-09-15

### Added
- Condition **Path type** (`builtin.pathType`): matches only files or only folders (the copied path is checked on disk; a missing path matches neither). Pair it with the file-path kind condition to split one path rule into a file rule and a folder rule.

## [2.6.8] - 2026-09-15

### Added
- Built-in action **Open file**: copy a local path and open it; a file opens in its default app, a folder in Finder. Accepts absolute and `~/` paths, `file://` URLs and copied Finder items.

### Changed
- Sandbox exception for read-only filesystem access (`com.apple.security.temporary-exception.files.absolute-path.read-only = /`), needed to open files. No write access is granted.

## [2.6.7] - 2026-08-28

### Added
- Built-in action **Reveal in Finder** (`builtin.revealInFinder`): copy a local path and reveal it; a folder path opens that folder, a file path opens its folder with the file selected. Accepts `/abs`, `~/rel`, `file://` URLs and copied Finder items. macOS shows a one-time "wants to control Finder" prompt.

## [2.6.6] - 2026-06-26

### Changed
- Refined the "+" app-icon badge: smaller, cleaner corner accent.

## [2.6.5] - 2026-06-26

### Changed
- Polished the "+" app icon (clean centered badge); added a "+" to the menu-bar glyphs.

## [2.6.4] - 2026-06-26

### Added
- Headless CLI for managing plugins and local folders, so agents can build and register plugins without the GUI.

### Changed
- Rebrand to MaccyPlus (plugin ids `com.maccyplus.*`) with a new "+" app icon.

## [2.6.3] - 2026-06-25

### Added
- Plugin system: declarative and JavaScript clipboard conditions/actions, install/uninstall from the official marketplace.

### Changed
- Faster popup.

## [2.6.2] - 2026-06-23

### Added
- **Fix keyboard layout (EN ⇄ HE)** clipboard action: re-maps text typed in the wrong active layout between US-QWERTY and Israeli SI-1452; direction is auto-detected. Manual trigger only (rule or per-action shortcut).

## [2.6.1] - 2026-06-20

First release as Maccy Actions, a fork of Maccy.

### Added
- Rule-based Actions engine: rules (conditions) lead to actions (open URL/app, web search, transform, run Shortcut, send to phone).
- LAN clipboard sync to Android.
- Unwrap soft-wrapped terminal commands (automatic on char-wrap, ⌘⇧U for word-wrap).
- Per-action keyboard shortcuts; editable terminal-app list.
- Headless CLI to configure rules and actions.

### Notes
- Ad-hoc signed, not notarized: first launch needs right-click → Open (or clearing quarantine).

[Unreleased]: https://github.com/roypadina/maccyplus/compare/v2.7.3...HEAD
[2.7.3]: https://github.com/roypadina/maccyplus/compare/v2.7.2...v2.7.3
[2.7.2]: https://github.com/roypadina/maccyplus/compare/v2.7.1...v2.7.2
[2.7.1]: https://github.com/roypadina/maccyplus/compare/v2.7.0...v2.7.1
[2.7.0]: https://github.com/roypadina/maccyplus/compare/v2.6.10...v2.7.0
[2.6.10]: https://github.com/roypadina/maccyplus/compare/v2.6.9...v2.6.10
[2.6.9]: https://github.com/roypadina/maccyplus/compare/v2.6.8...v2.6.9
[2.6.8]: https://github.com/roypadina/maccyplus/compare/v2.6.7...v2.6.8
[2.6.7]: https://github.com/roypadina/maccyplus/compare/v2.6.6...v2.6.7
[2.6.6]: https://github.com/roypadina/maccyplus/compare/v2.6.5...v2.6.6
[2.6.5]: https://github.com/roypadina/maccyplus/compare/v2.6.4...v2.6.5
[2.6.4]: https://github.com/roypadina/maccyplus/compare/v2.6.3...v2.6.4
[2.6.3]: https://github.com/roypadina/maccyplus/compare/v2.6.2...v2.6.3
[2.6.2]: https://github.com/roypadina/maccyplus/compare/v2.6.1...v2.6.2
[2.6.1]: https://github.com/roypadina/maccyplus/releases/tag/v2.6.1
