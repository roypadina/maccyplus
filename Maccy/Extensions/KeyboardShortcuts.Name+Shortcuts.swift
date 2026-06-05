import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  // Default differs from upstream Maccy (⌘⇧C) so Maccy Actions can run alongside it.
  static let popup = Self("popup", default: Shortcut(.c, modifiers: [.command, .option]))
  static let pin = Self("pin", default: Shortcut(.p, modifiers: [.option]))
  static let delete = Self("delete", default: Shortcut(.delete, modifiers: [.option]))
  static let togglePreview = Self("togglePreview", default: Shortcut(.space, modifiers: [.control]))
  // Opens the Remote Clipboard panel (the paired phone's history).
  static let showRemoteClipboard = Self("showRemoteClipboard", default: Shortcut(.v, modifiers: [.control, .shift]))
}
