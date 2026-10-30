import Cocoa
import LaunchAtLogin
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
    NSApp.activate()
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
        .accessibilityHidden(true)

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

      HStack(spacing: 12) {
        Link("Report an issue", destination: URL(string: "https://github.com/roypadina/maccyplus/issues")!)
        Button("Welcome Guide…") { WelcomeWindow.show() }
          .buttonStyle(.link)
      }
      .font(.callout)

      Divider()

      VStack(spacing: 8) {
        Text("Have an idea, or want to help build it?").font(.headline)
        Text("Feature requests and pull requests are welcome. Ko-fi supporters go to the front of the queue.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        HStack {
          Link(destination: URL(string: "https://github.com/roypadina/maccyplus/issues/new?template=feature_request.yml")!) {
            Text("Request a feature").frame(minWidth: 120)
          }
          .buttonStyle(.bordered)

          Link(destination: URL(string: "https://github.com/roypadina/maccyplus/blob/main/CONTRIBUTING.md")!) {
            Text("Contribute").frame(minWidth: 90)
          }
          .buttonStyle(.bordered)
        }
      }

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

// MaccyPlus: first-launch Welcome window (house style). Kept in this fork-owned file so it needs no new pbxproj entry.
enum WelcomeWindow {
  private static var window: NSWindow?

  static func show() {
    if window == nil {
      let window = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView { Self.window?.close() }))
      window.title = "Welcome"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      Self.window = window
      // Release on close so the next open rebuilds the view and re-reads the Accessibility state.
      Task { @MainActor in
        for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification, object: window) { break }
        Self.window = nil
      }
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }
}

private struct WelcomeView: View {
  let onDone: () -> Void

  @State private var accessibilityAllowed = Accessibility.allowed

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text("Welcome to MaccyPlus").font(.title2.bold())
          Text("You copy a Jira key, a link or a terminal command, then open, search or tidy it by hand. MaccyPlus keeps your clipboard history and does that next step for you.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      row("clipboard", "MaccyPlus lives in the menu bar.",
          "Click its icon or press ⌥⌘C to open your history. Type to search, then press Return to copy an item.")
      row("bolt", "Actions work on what you copy.",
          "Right-click an item to open a Jira key, search a link or unwrap a copied command. Rules and per-action shortcuts live in Settings > Actions.")
      row("hand.raised", "Pasting needs Accessibility.",
          "To paste into the app you are using, allow MaccyPlus in System Settings > Privacy & Security > Accessibility. Copying works without it.")
      row("questionmark.circle", "Icon missing?",
          "Press ⌥⌘C, or open MaccyPlus again from Applications. Turn the icon back on in Settings > Appearance > Show menu icon.")

      LaunchAtLogin.Toggle("Open at Login")

      SupportBox()

      HStack {
        if !accessibilityAllowed {
          Button("Allow Accessibility…") { Accessibility.check() }
        }
        Spacer()
        Button("Done", action: onDone).keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 440)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      accessibilityAllowed = Accessibility.allowed  // the user may have granted it in System Settings
    }
  }

  private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 28).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct SupportBox: View {
  var body: some View {
    GroupBox {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Free and open source").font(.headline)
          Text("If MaccyPlus saves you time, a coffee on Ko-fi keeps the next one coming.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Link("Support on Ko-fi ☕", destination: URL(string: "https://ko-fi.com/roypadina")!).buttonStyle(.bordered)
      }
      .padding(4)
    }
  }
}
