
<img width="128px" src="https://maccy.app/img/maccy/Logo.png" alt="Logo" />

# [Maccy](https://maccy.app)

[![Downloads](https://img.shields.io/github/downloads/p0deje/Maccy/total.svg)](https://github.com/p0deje/Maccy/releases/latest)
[![Build Status](https://img.shields.io/bitrise/716921b669780314/master?token=3pMiCb5dpFzlO-7jTYtO3Q)](https://app.bitrise.io/app/716921b669780314)

Maccy is a lightweight clipboard manager for macOS. It keeps the history of what you copy
and lets you quickly navigate, search, and use previous clipboard contents.

Maccy works on macOS Sonoma 14 or higher.

<!-- vim-markdown-toc GFM -->

* [Features](#features)
* [Install](#install)
* [Usage](#usage)
* [Actions](#actions)
  * [Unwrap soft-wrapped terminal commands](#unwrap-soft-wrapped-terminal-commands)
  * [Per-action shortcuts](#per-action-shortcuts)
  * [Terminal apps](#terminal-apps)
  * [Configure actions from the command line](#configure-actions-from-the-command-line)
* [Advanced](#advanced)
  * [Ignore Copied Items](#ignore-copied-items)
  * [Ignore Custom Copy Types](#ignore-custom-copy-types)
  * [Speed up Clipboard Check Interval](#speed-up-clipboard-check-interval)
* [FAQ](#faq)
  * [Why doesn't it paste when I select an item in history?](#why-doesnt-it-paste-when-i-select-an-item-in-history)
  * [When assigning a hotkey to open Maccy, it says that this hotkey is already used in some system setting.](#when-assigning-a-hotkey-to-open-maccy-it-says-that-this-hotkey-is-already-used-in-some-system-setting)
  * [How to restore hidden footer?](#how-to-restore-hidden-footer)
  * [How to ignore copies from Universal Clipboard?](#how-to-ignore-copies-from-universal-clipboard)
  * [My keyboard shortcut stopped working in password fields. How do I fix this?](#my-keyboard-shortcut-stopped-working-in-password-fields-how-do-i-fix-this)
* [Translations](#translations)
* [Motivation](#motivation)
* [License](#license)

<!-- vim-markdown-toc -->

## Features

* Lightweight and fast
* Keyboard-first
* Secure and private
* Native UI
* Open source and free

## Install

Download the latest version from the [releases](https://github.com/p0deje/Maccy/releases/latest) page, or use [Homebrew](https://brew.sh/):

```sh
brew install maccy
```

## Usage

1. <kbd>SHIFT (⇧)</kbd> + <kbd>COMMAND (⌘)</kbd> + <kbd>C</kbd> to popup Maccy or click on its icon in the menu bar.
2. Type what you want to find.
3. To select the history item you wish to copy, press <kbd>ENTER</kbd>, or click the item, or use <kbd>COMMAND (⌘)</kbd> + `n` shortcut.
4. To choose the history item and paste, press <kbd>OPTION (⌥)</kbd> + <kbd>ENTER</kbd>, or <kbd>OPTION (⌥)</kbd> + <kbd>CLICK</kbd> the item, or use <kbd>OPTION (⌥)</kbd> + `n` shortcut.
5. To choose the history item and paste without formatting, press <kbd>OPTION (⌥)</kbd> + <kbd>SHIFT (⇧)</kbd> + <kbd>ENTER</kbd>, or <kbd>OPTION (⌥)</kbd> + <kbd>SHIFT (⇧)</kbd> + <kbd>CLICK</kbd> the item, or use <kbd>OPTION (⌥)</kbd> + <kbd>SHIFT (⇧)</kbd> + `n` shortcut.
6. To delete the history item, press <kbd>OPTION (⌥)</kbd> + <kbd>DELETE (⌫)</kbd>.
7. To see the full text of the history item, wait a couple of seconds for tooltip.
8. To pin the history item so that it remains on top of the list, press <kbd>OPTION (⌥)</kbd> + <kbd>P</kbd>. The item will be moved to the top with a random but permanent keyboard shortcut. To unpin it, press <kbd>OPTION (⌥)</kbd> + <kbd>P</kbd> again.
9. To clear all unpinned items, select _Clear_ in the menu, or press <kbd>OPTION (⌥)</kbd> + <kbd>COMMAND (⌘)</kbd> + <kbd>DELETE (⌫)</kbd>. To clear all items including pinned, select _Clear_ in the menu with  <kbd>OPTION (⌥)</kbd> pressed, or press <kbd>SHIFT (⇧)</kbd> + <kbd>OPTION (⌥)</kbd> + <kbd>COMMAND (⌘)</kbd> + <kbd>DELETE (⌫)</kbd>.
10. To disable Maccy and ignore new copies, click on the menu icon with <kbd>OPTION (⌥)</kbd> pressed.
11. To ignore only the next copy, click on the menu icon with <kbd>OPTION (⌥)</kbd> + <kbd>SHIFT (⇧)</kbd> pressed.
12. To customize the behavior, check "Preferences…" window, or press <kbd>COMMAND (⌘)</kbd> + <kbd>,</kbd>.

## Actions

Actions let Maccy *do something* with a copied value instead of just storing it. An
**action rule** has **conditions** (when it applies) and one or more ordered **actions**
(what it does). A rule can run from the popup's right-click menu, from a global shortcut,
from a per-action shortcut, or automatically the moment a matching value is copied.
Rules are edited under Preferences → Actions.

**Conditions** — kind (URL, email, phone, file path, color hex, image, text), regex,
contains-text, source app, **soft-wrapped** (the value looks like a wrapped terminal
command), and **from a terminal** (the copy came from a configured terminal app). A rule
matches when *all* or *any* of its conditions hold.

**Actions** — open as URL, open in a specific app, web search, **transform text**
(trim, UPPERCASE, lowercase, strip formatting, **unwrap**), and run a macOS Shortcut.

### Unwrap soft-wrapped terminal commands

When a coding agent or CLI prints a long command in the terminal, the terminal wraps it
across several visual lines. Copying it brings along the line breaks, so pasting it
elsewhere fails. The **unwrap** transform strips those wrap breaks and leaves a single,
ready-to-paste command on the clipboard.

The built-in **"Unwrap terminal command"** rule does this automatically: when a copy comes
**from a terminal app** *and* shows a fixed-width wrap signature, the wrap breaks are
removed (the original command is reconstructed exactly — no merged tokens, no spurious
spaces). Genuine multi-line scripts are left untouched. You can also trigger unwrap
manually by giving the action a [per-action shortcut](#per-action-shortcuts).

### Per-action shortcuts

Any single action can carry its own keyboard shortcut (recorded in the rule editor). That
shortcut runs **only that action** on the current clipboard, unconditionally — independent
of rule matching and of the global default-action shortcut. Specs look like `cmd+shift+u`.

### Terminal apps

The **from a terminal** condition matches copies whose source app is in a configurable
list (Terminal.app, iTerm2, Warp, kitty, Alacritty, WezTerm, Ghostty, VS Code by default).
Edit the list under Preferences → Actions → "Terminal apps…", or from the command line.

### Configure actions from the command line

MaccyPlus ships a headless CLI so rules, actions, the terminal-app list, and per-action
shortcuts can be managed without the GUI — useful for scripting and for AI coding agents.
The running app picks up changes immediately.

```sh
APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.royp.MaccyPlus'" | head -1)
BIN="$APP/Contents/MacOS/MaccyPlus"

"$BIN" rules describe          # live JSON schema: condition/action/transform catalog
"$BIN" rules list              # all rules as JSON
"$BIN" rules add  --json '…'   # create a rule (also: get/update/remove/move/enable/disable/import)
"$BIN" terminals list          # the terminal-app list (also: add/remove/reset)
```

All commands take and emit JSON and validate input before writing. For the full schema,
command reference, and recipes — including how an agent should drive it — see the bundled
skill at [`.claude/skills/maccyplus/SKILL.md`](.claude/skills/maccyplus/SKILL.md).

## Advanced

### Ignore Copied Items

You can tell Maccy to ignore all copied items:

```sh
defaults write org.p0deje.Maccy ignoreEvents true # default is false
```

This is useful if you have some workflow for copying sensitive data. You can set `ignoreEvents` to true, copy the data and set `ignoreEvents` back to false.

You can also click the menu icon with <kbd>OPTION (⌥)</kbd> pressed. To ignore only the next copy, click with <kbd>OPTION (⌥)</kbd> + <kbd>SHIFT (⇧)</kbd> pressed.

### Ignore Custom Copy Types

By default Maccy will ignore certain copy types that are considered to be confidential
or temporary. The default list always include the following types:

* `org.nspasteboard.TransientType`
* `org.nspasteboard.ConcealedType`
* `org.nspasteboard.AutoGeneratedType`

Also, default configuration includes the following types but they can be removed
or overwritten:

* `com.agilebits.onepassword`
* `com.typeit4me.clipping`
* `de.petermaurer.TransientPasteboardType`
* `Pasteboard generator type`
* `net.antelle.keeweb`

You can add additional custom types using settings.
To find what custom types are used by an application, you can use
free application [Pasteboard-Viewer](https://github.com/sindresorhus/Pasteboard-Viewer).
Simply download the application, open it, copy something from the application you
want to ignore and look for any custom types in the left sidebar. [Here is an example
of using this approach to ignore Adobe InDesign](https://github.com/p0deje/Maccy/issues/125).

### Speed up Clipboard Check Interval

By default, Maccy checks clipboard every 500 ms, which should be enough for most users. If you want
to speed it up, you can change it with `defaults`:

```sh
defaults write org.p0deje.Maccy clipboardCheckInterval 0.1 # 100 ms
```

## FAQ

### Why doesn't it paste when I select an item in history?

1. Make sure you have "Paste automatically" enabled in Preferences.
2. Make sure "Maccy" is added to System Settings -> Privacy & Security -> Accessibility.

### When assigning a hotkey to open Maccy, it says that this hotkey is already used in some system setting.

1. Open System settings -> Keyboard -> Keyboard Shortcuts.
2. Find where that hotkey is used. For example, "Convert text to simplified Chinese" is under Services -> Text.
3. Disable that hotkey or remove assigned combination ([screenshot](https://github.com/p0deje/Maccy/assets/576152/446719e6-c3e5-4eb0-95fb-5a811066487f)).
4. Restart Maccy.
5. Assign hotkey in Maccy settings.

### How to restore hidden footer?

1. Open Maccy window.
2. Press <kbd>COMMAND (⌘)</kbd> + <kbd>,</kbd> to open preferences.
3. Enable footer in Appearance section.

If for some reason it doesn't work, run the following command in Terminal.app:

```sh
defaults write org.p0deje.Maccy showFooter 1
```

### How to ignore copies from [Universal Clipboard](https://support.apple.com/en-us/102430)?

1. Open Preferences -> Ignore -> Pasteboard Types.
2. Add `com.apple.is-remote-clipboard`.

### My keyboard shortcut stopped working in password fields. How do I fix this?

If your shortcut produces a character (like `Option+C` → "ç"), macOS security may block it in password fields. Use [Karabiner-Elements](https://karabiner-elements.pqrs.org/) to remap your shortcut to a different combination like `Cmd+Shift+C`. [See detailed solution](docs/keyboard-shortcut-password-fields.md).

## Translations

The translations are hosted in [Weblate](https://hosted.weblate.org/engage/maccy/).
You can use it to suggest changes in translations and localize the application to a new language.

[![Translation status](https://hosted.weblate.org/widget/maccy/multi-auto.svg)](https://hosted.weblate.org/engage/maccy/)

## Motivation

There are dozens of similar applications out there, so why build another?
Over the past years since I moved from Linux to macOS, I struggled to find
a clipboard manager that is as free and simple as [Parcellite](http://parcellite.sourceforge.net),
but I couldn't. So I've decided to build one.

Also, I wanted to learn Swift and get acquainted with macOS application development.


## License

[MIT](./LICENSE)
