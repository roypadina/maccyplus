import SwiftUI

// Note: `@main` lives in `main.swift` so the binary can run headless as a CLI
// (see `ActionsCLI`). A SwiftUI `App` still gets a synthesized `static func main()`.
struct MaccyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  // It's impossible to create sceneless application,
  // so we are hacking this around by creating a menubar
  // scene that is always hidden.
  @State private var hiddenMenu: Bool = false

  var body: some Scene {
    MenuBarExtra("", isInserted: $hiddenMenu) {
      EmptyView()
    }
  }
}
