import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  // Default differs from upstream Maccy (⌘⇧C) so MaccyPlus can run alongside it.
  static let popup = Self("popup", initial: Shortcut(.c, modifiers: [.command, .option]))
  static let pin = Self("pin", initial: Shortcut(.p, modifiers: [.option]))
  static let delete = Self("delete", initial: Shortcut(.delete, modifiers: [.option]))
  static let togglePreview = Self("togglePreview", initial: Shortcut(.space, modifiers: [.control]))
}
