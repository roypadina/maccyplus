import Foundation
import Observation

// Holds the *peer's* clipboard history (browse-on-demand). Persisted to disk so
// it survives relaunch. Full image/file bytes are cached lazily on fetch.
@MainActor
@Observable
final class RemoteClipStore {
  static let shared = RemoteClipStore()

  private(set) var items: [ItemMeta] = []
  /// Device name of the peer whose items these are (for UI), if known.
  var peerName: String = ""

  private let maxItems = 200

  private let dir: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MaccyActions", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }()
  private var storeURL: URL { dir.appendingPathComponent("remote-clips.json") }
  private var contentDir: URL {
    let url = dir.appendingPathComponent("remote-content", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  init() {
    load()
  }

  // MARK: - Ingest

  func replaceAll(_ metas: [ItemMeta], peerName: String) {
    self.peerName = peerName
    items = dedupe(metas).sorted { $0.createdAt > $1.createdAt }
    trim()
    save()
  }

  func add(_ meta: ItemMeta) {
    items.removeAll { $0.id == meta.id }
    items.insert(meta, at: 0)
    items.sort { $0.createdAt > $1.createdAt }
    trim()
    save()
  }

  func clear() {
    items = []
    try? FileManager.default.removeItem(at: contentDir)
    save()
  }

  // MARK: - Content cache

  func cachedContentURL(for id: String) -> URL? {
    let url = contentDir.appendingPathComponent(id)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  func cachedContent(for id: String) -> Data? {
    guard let url = cachedContentURL(for: id) else { return nil }
    return try? Data(contentsOf: url)
  }

  func storeContent(_ data: Data, for id: String) {
    try? data.write(to: contentDir.appendingPathComponent(id))
  }

  // MARK: - Persistence

  private func dedupe(_ metas: [ItemMeta]) -> [ItemMeta] {
    var seen = Set<String>()
    return metas.filter { seen.insert($0.id).inserted }
  }

  private func trim() {
    if items.count > maxItems { items = Array(items.prefix(maxItems)) }
  }

  private func load() {
    guard let data = try? Data(contentsOf: storeURL),
          let decoded = try? JSONDecoder().decode([ItemMeta].self, from: data) else { return }
    items = decoded.sorted { $0.createdAt > $1.createdAt }
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(items) else { return }
    try? data.write(to: storeURL)
  }
}
