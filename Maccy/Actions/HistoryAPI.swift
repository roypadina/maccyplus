import AppKit
import Foundation

// Agent-facing clipboard-history API: `MaccyPlus history <sub> …`.
//
// Unlike the rules CLI, history lives in the running app (SwiftData store +
// `History.shared`), so the CLI never touches the store. It writes a request
// file into the shared sandbox-container tmp dir, posts a distributed
// notification carrying only the request id (sandbox drops userInfo), and polls
// for the response file the app writes back. The app runs every command on
// `History.shared`, exactly like the equivalent user action.
enum HistoryAPI {
  static let requestNotification = "com.royp.MaccyPlus.historyRequest"
  static let usage = """
    Usage: MaccyPlus history <command>
      list [--limit N] [--label L] [--search Q] [--pinned] [--full]
      get <id>
      add [--text T | stdin] [--label L] [--note N] [--pin] [--copy]
      update <id> [--label L] [--note N]      ("" clears)
      pin <id> | unpin <id> | top <id> | copy <id> | delete <id>
    """

  // Same resolver as Storage.swift: inside the shared sandbox container for both
  // the app and the CLI (a shell-inherited TMPDIR is not guaranteed to be).
  private static var ipcDir: URL {
    URL.applicationSupportDirectory.appending(path: "Maccy/agent-ipc", directoryHint: .isDirectory)
  }

  // MARK: CLI side

  static func runCLI(_ args: [String]) -> Int32 {
    guard let cmd = args.first, !["-h", "--help", "help"].contains(cmd) else {
      print(usage)
      return args.isEmpty ? 1 : 0
    }
    var request: [String: Any] = ["cmd": cmd]
    var iterator = args.dropFirst().makeIterator()
    while let arg = iterator.next() {
      switch arg {
      case "--pinned", "--full", "--pin", "--copy":
        request[String(arg.dropFirst(2))] = true
      case "--limit", "--label", "--search", "--note", "--text":
        guard let value = iterator.next() else { return fail("Missing value after \(arg).") }
        request[String(arg.dropFirst(2))] = value
      default:
        if arg.hasPrefix("--") { return fail("Unknown option \(arg).\n\(usage)") }
        request["id"] = arg
      }
    }
    if cmd == "add", request["text"] == nil, isatty(0) == 0 {
      request["text"] = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    }

    let reqID = UUID().uuidString
    let reqURL = ipcDir.appending(path: "\(reqID).req.json")
    let resURL = ipcDir.appending(path: "\(reqID).res.json")
    do {
      try FileManager.default.createDirectory(at: ipcDir, withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: request).write(to: reqURL, options: .atomic)
    } catch {
      return fail("Could not write request: \(error.localizedDescription)")
    }
    DistributedNotificationCenter.default().postNotificationName(
      .init(requestNotification), object: reqID, userInfo: nil, deliverImmediately: true)

    let deadline = Date.now.addingTimeInterval(5)
    while Date.now < deadline {
      if let data = try? Data(contentsOf: resURL),
         let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        try? FileManager.default.removeItem(at: resURL)
        if let error = response["error"] as? String { return fail(error) }
        return emit(response["result"] ?? NSNull())
      }
      usleep(50_000)
    }
    try? FileManager.default.removeItem(at: reqURL)
    return fail("No response from MaccyPlus — is the app running?", code: 2)
  }

  private static func emit(_ value: Any) -> Int32 {
    guard let data = try? JSONSerialization.data(
      withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]) else {
      return fail("Could not encode response.")
    }
    FileHandle.standardOutput.write(data + Data("\n".utf8))
    return 0
  }

  private static func fail(_ message: String, code: Int32 = 1) -> Int32 {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    return code
  }

  // MARK: App side

  // Called on the main queue for every request notification.
  @MainActor
  static func handleRequestNotification(_ reqID: String?) {
    // The id becomes a file name — accept only a UUID so it can't escape ipcDir.
    guard let reqID, UUID(uuidString: reqID) != nil else { return }
    let reqURL = ipcDir.appending(path: "\(reqID).req.json")
    guard let data = try? Data(contentsOf: reqURL),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    try? FileManager.default.removeItem(at: reqURL)

    Task { @MainActor in
      var response: [String: Any]
      do {
        response = ["result": try await handle(request)]
      } catch {
        response = ["error": (error as? APIError)?.message ?? error.localizedDescription]
      }
      let resURL = ipcDir.appending(path: "\(reqID).res.json")
      let out = (try? JSONSerialization.data(withJSONObject: response, options: .fragmentsAllowed))
        ?? Data(#"{"error":"Could not encode response."}"#.utf8)
      try? out.write(to: resURL, options: .atomic)
    }
  }

  struct APIError: Error {
    let message: String
    init(_ message: String) { self.message = message }
  }

  @MainActor
  static func handle(_ request: [String: Any]) async throws -> Any { // swiftlint:disable:this cyclomatic_complexity
    let history = History.shared
    let cmd = request["cmd"] as? String ?? ""
    let full = request["full"] as? Bool ?? false

    func find() throws -> HistoryItemDecorator {
      guard let id = request["id"] as? String else { throw APIError("Missing <id>.\n\(usage)") }
      guard let item = history.all.first(where: { $0.item.uid == id }) else {
        throw APIError("No history item with id \(id).")
      }
      return item
    }

    func save() { try? Storage.shared.context.save() }

    switch cmd {
    case "list":
      var items = history.all
      if request["pinned"] as? Bool == true { items = items.filter(\.isPinned) }
      if let label = request["label"] as? String {
        items = items.filter { $0.item.label?.localizedCaseInsensitiveContains(label) == true }
      }
      if let query = request["search"] as? String {
        items = items.filter {
          [$0.item.previewableText, $0.item.label, $0.item.note].contains { $0?.localizedCaseInsensitiveContains(query) == true }
        }
      }
      let limit = max(0, Int(request["limit"] as? String ?? "") ?? 20)
      return items.prefix(limit).map { json($0, full: full) }

    case "get":
      return json(try find(), full: true)

    case "add":
      guard let text = request["text"] as? String, !text.isEmpty else {
        throw APIError("Nothing to add: pass --text or pipe the value via stdin.")
      }
      let itemLabel = try label(request["label"])
      let item = HistoryItem(contents: [
        HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(text.utf8))
      ])
      if #unavailable(macOS 15.0) {
        // On macOS 14 the history item needs to be inserted into storage directly after creating it.
        try? history.insertIntoStorage(item)
      }
      item.title = item.generateTitle()
      item.application = Bundle.main.bundleIdentifier
      item.label = itemLabel
      item.note = nonEmpty(request["note"])
      let added = history.add(item)
      if request["pin"] as? Bool == true, added.isUnpinned { history.togglePin(added) }
      save()
      if request["copy"] as? Bool == true { Clipboard.shared.copy(added.item) }
      return json(added, full: full)

    case "update":
      let item = try find()
      if request["label"] != nil { item.item.label = try label(request["label"]) }
      if request["note"] != nil { item.item.note = nonEmpty(request["note"]) }
      save()
      return json(item, full: full)

    case "pin", "unpin":
      let item = try find()
      if item.isPinned != (cmd == "pin") { history.togglePin(item) }
      save()
      return json(item, full: full)

    case "top":
      let item = try find()
      item.item.lastCopiedAt = .now
      save()
      try await history.load()
      return json(try find(), full: full)

    case "copy":
      let item = try find()
      // Same as the user selecting it: becomes the live clipboard and moves to top.
      // Maccy re-records the copy as a new item; dedup carries the uid over.
      Clipboard.shared.copy(item.item)
      return json(item, full: full)

    case "delete":
      history.delete(try find())
      return ["deleted": request["id"] ?? ""]

    default:
      throw APIError("Unknown history command: \(cmd).\n\(usage)")
    }
  }

  private static func nonEmpty(_ value: Any?) -> String? {
    guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !string.isEmpty else { return nil }
    return string
  }

  private static func label(_ value: Any?) throws -> String? {
    guard let label = nonEmpty(value) else { return nil }
    guard !label.contains(where: \.isNewline), label.count <= 60 else {
      throw APIError("Label must be a single line of at most 60 characters (use --note for detail).")
    }
    return label
  }

  @MainActor
  private static func json(_ item: HistoryItemDecorator, full: Bool) -> [String: Any] {
    let entry = item.item
    let kind = entry.hasImageData ? "image" : (entry.fileURLs.isEmpty ? "text" : "file")
    let text = entry.previewableText
    let iso = ISO8601DateFormatter()
    return [
      "id": entry.uid ?? "",
      "index": History.shared.all.firstIndex(of: item) ?? -1,
      "kind": kind,
      "title": entry.title,
      "text": full ? text : text.shortened(to: 500),
      "label": entry.label ?? NSNull(),
      "note": entry.note ?? NSNull(),
      "pin": entry.pin ?? NSNull(),
      "app": entry.application ?? NSNull(),
      "copies": entry.numberOfCopies,
      "firstCopiedAt": iso.string(from: entry.firstCopiedAt),
      "lastCopiedAt": iso.string(from: entry.lastCopiedAt)
    ]
  }
}
