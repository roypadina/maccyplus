import AppKit
import KeyboardShortcuts

// Parses/formats a human keyboard-shortcut spec like "cmd+shift+u" to and from
// a `KeyboardShortcuts.Shortcut`. Lives on `ActionConfig.shortcut` so per-action
// shortcuts survive export/import and CLI editing.
enum ShortcutSpec {
  // Token (lowercased) -> key. Bidirectional via `keyNames` for the reverse map.
  private static let keysByName: [String: KeyboardShortcuts.Key] = [
    "a": .a, "b": .b, "c": .c, "d": .d, "e": .e, "f": .f, "g": .g, "h": .h,
    "i": .i, "j": .j, "k": .k, "l": .l, "m": .m, "n": .n, "o": .o, "p": .p,
    "q": .q, "r": .r, "s": .s, "t": .t, "u": .u, "v": .v, "w": .w, "x": .x,
    "y": .y, "z": .z,
    "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four,
    "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
    "space": .space,
    "return": .return, "enter": .return,
    "tab": .tab,
    "escape": .escape, "esc": .escape,
    "delete": .delete, "backspace": .delete,
    "f1": .f1, "f2": .f2, "f3": .f3, "f4": .f4, "f5": .f5, "f6": .f6,
    "f7": .f7, "f8": .f8, "f9": .f9, "f10": .f10, "f11": .f11, "f12": .f12
  ]

  // Canonical name for each key, for `format`. Where multiple tokens map to a
  // key (e.g. enter/return), this picks the canonical one.
  private static let nameByKey: [KeyboardShortcuts.Key: String] = [
    .a: "a", .b: "b", .c: "c", .d: "d", .e: "e", .f: "f", .g: "g", .h: "h",
    .i: "i", .j: "j", .k: "k", .l: "l", .m: "m", .n: "n", .o: "o", .p: "p",
    .q: "q", .r: "r", .s: "s", .t: "t", .u: "u", .v: "v", .w: "w", .x: "x",
    .y: "y", .z: "z",
    .zero: "0", .one: "1", .two: "2", .three: "3", .four: "4",
    .five: "5", .six: "6", .seven: "7", .eight: "8", .nine: "9",
    .space: "space",
    .return: "return",
    .tab: "tab",
    .escape: "escape",
    .delete: "delete",
    .f1: "f1", .f2: "f2", .f3: "f3", .f4: "f4", .f5: "f5", .f6: "f6",
    .f7: "f7", .f8: "f8", .f9: "f9", .f10: "f10", .f11: "f11", .f12: "f12"
  ]

  // Modifier token (lowercased) -> flag.
  private static let modifiersByName: [String: NSEvent.ModifierFlags] = [
    "cmd": .command, "command": .command, "⌘": .command,
    "shift": .shift, "⇧": .shift,
    "opt": .option, "option": .option, "alt": .option, "⌥": .option,
    "ctrl": .control, "control": .control, "⌃": .control
  ]

  static func parse(_ spec: String) -> KeyboardShortcuts.Shortcut? {
    let tokens = spec
      .split(separator: "+", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    guard !tokens.isEmpty else { return nil }

    var modifiers: NSEvent.ModifierFlags = []
    var key: KeyboardShortcuts.Key?
    for token in tokens {
      if let modifier = modifiersByName[token] {
        modifiers.insert(modifier)
      } else if let resolved = keysByName[token] {
        key = resolved
      } else {
        return nil
      }
    }

    guard let key else { return nil }
    return KeyboardShortcuts.Shortcut(key, modifiers: modifiers)
  }

  static func format(_ shortcut: KeyboardShortcuts.Shortcut) -> String? {
    guard let key = shortcut.key, let name = nameByKey[key] else { return nil }

    var tokens: [String] = []
    if shortcut.modifiers.contains(.control) { tokens.append("ctrl") }
    if shortcut.modifiers.contains(.option) { tokens.append("opt") }
    if shortcut.modifiers.contains(.shift) { tokens.append("shift") }
    if shortcut.modifiers.contains(.command) { tokens.append("cmd") }
    tokens.append(name)
    return tokens.joined(separator: "+")
  }
}
