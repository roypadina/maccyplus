import Cocoa
import SwiftUI

// MaccyPlus: custom About window (the standard panel's fixed-height credits box clipped our text).
// MaccyPlus credits lead; upstream Maccy credits stay, smaller, at the bottom.
class About {
  private var window: NSWindow?

  @objc
  func openAbout(_ sender: NSMenuItem?) {
    if window == nil {
      let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
      window.title = "About MaccyPlus"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      self.window = window
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}

private struct AboutView: View {
  private let info = Bundle.main.infoDictionary ?? [:]

  var body: some View {
    VStack(spacing: 12) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)

      VStack(spacing: 2) {
        Text("MaccyPlus").font(.title.bold())
        Text("Version \(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 8) {
        Text("Made by Roy Padina").font(.headline)
        Text("I'm a software engineer from Israel who builds small, focused Mac tools to fix the little annoyances in my own day — then shares them free and open source.")
        Text("If this app saves you time, a coffee on Ko-fi keeps the next one coming. ☕")
      }
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      HStack {
        Link(destination: URL(string: "https://ko-fi.com/roypadina")!) {
          Text("Support on Ko-fi ☕").frame(minWidth: 140)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Link(destination: URL(string: "https://github.com/roypadina/maccyplus")!) {
          Text("GitHub").frame(minWidth: 70)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }

      Link("Report an issue", destination: URL(string: "https://github.com/roypadina/maccyplus/issues")!)
        .font(.callout)

      Divider().padding(.vertical, 4)

      VStack(spacing: 3) {
        Text("Based on [Maccy](https://github.com/p0deje/Maccy) by Alexey Rodionov · [maccy.app](https://maccy.app)")
        Text("Kudos to [Sasha Koss](https://koss.nocorp.me) for help! 🏂")
        Text("Special thank you to Tonia, Anna & Guy! ❤️")
        Text("MaccyPlus © Roy Padina · Maccy © Alexey Rodionov · MIT")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(24)
    .frame(width: 380)
  }
}
