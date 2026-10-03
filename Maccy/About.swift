import Cocoa

class About {
  private let familyCredits = NSAttributedString(
    string: "Special thank you to Tonia, Anna & Guy! ❤️",
    attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
  )

  private var kossCredits: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "Kudos to Sasha Koss for help! 🏂",
                                           attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: "https://koss.nocorp.me", range: NSRange(location: 9, length: 10))
    return string
  }

  private var links: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "Website│GitHub│Support",
                                           attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: "https://maccy.app", range: NSRange(location: 0, length: 7))
    string.addAttribute(.link, value: "https://github.com/p0deje/Maccy", range: NSRange(location: 8, length: 6))
    string.addAttribute(.link, value: "mailto:support@maccy.app", range: NSRange(location: 15, length: 7))
    return string
  }

  private var maccyPlusCredits: NSMutableAttributedString {
    let string = NSMutableAttributedString(
      string: "MaccyPlus — made by Roy Padina\n\n" +
        "I'm a software engineer from Israel who builds small, focused Mac tools to fix the little " +
        "annoyances in my own day — then shares them free and open source.\n\n" +
        "If this app saves you time, a coffee on Ko-fi keeps the next one coming. ☕\n\n" +
        "Support on Ko-fi ☕│GitHub",
      attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor]
    )
    let text = string.string as NSString
    string.addAttribute(.link, value: "https://ko-fi.com/roypadina", range: text.range(of: "Support on Ko-fi ☕"))
    string.addAttribute(.link, value: "https://github.com/roypadina/maccyplus", range: text.range(of: "GitHub"))
    return string
  }

  private var credits: NSMutableAttributedString {
    let credits = NSMutableAttributedString(string: "",
                                            attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    credits.append(maccyPlusCredits)
    credits.append(NSAttributedString(string: "\n\nBased on Maccy by Alex Rodionov\n"))
    credits.append(links)
    credits.append(NSAttributedString(string: "\n\n"))
    credits.append(kossCredits)
    credits.append(NSAttributedString(string: "\n"))
    credits.append(familyCredits)
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }

  @objc
  func openAbout(_ sender: NSMenuItem?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
