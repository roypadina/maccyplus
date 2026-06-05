import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Bridges local HistoryItems to wire ItemMeta + applies remote items to the
// local pasteboard. All HistoryItem access is on the main actor.
@MainActor
enum SyncContent {
  // MARK: - Local item -> wire meta

  static func meta(
    for item: HistoryItem,
    id: String,
    sendText: Bool,
    sendImages: Bool,
    sendFiles: Bool
  ) -> ItemMeta? {
    let createdAt = Int64(item.firstCopiedAt.timeIntervalSince1970 * 1000)

    if let url = item.fileURLs.first, sendFiles {
      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
      let size = (attrs?[.size] as? Int) ?? 0
      let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
      return ItemMeta(id: id, kind: ItemMeta.Kind.file.rawValue, createdAt: createdAt,
                      size: size, mime: mime, preview: url.lastPathComponent,
                      text: nil, filename: url.lastPathComponent, thumb: nil)
    }

    if let imageData = item.imageData, sendImages, let png = pngData(imageData) {
      let thumb = thumbnail(png, maxPixel: 256)?.base64EncodedString()
      let preview = item.title.isEmpty ? "Image" : item.title
      return ItemMeta(id: id, kind: ItemMeta.Kind.image.rawValue, createdAt: createdAt,
                      size: png.count, mime: "image/png", preview: preview,
                      text: nil, filename: "image.png", thumb: thumb)
    }

    let string = item.previewableText
    if !string.isEmpty, sendText {
      let size = string.utf8.count
      let inline = size <= SyncProtocol.inlineTextCap
      return ItemMeta(id: id, kind: ItemMeta.Kind.text.rawValue, createdAt: createdAt,
                      size: size, mime: "text/plain",
                      preview: String(string.prefix(280)),
                      text: inline ? string : nil, filename: nil, thumb: nil)
    }

    return nil
  }

  // MARK: - Local item -> full content bytes (for contentRequest)

  struct FullContent {
    let data: Data
    let mime: String
    let filename: String?
    let kind: ItemMeta.Kind
  }

  static func fullContent(for item: HistoryItem) -> FullContent? {
    if let url = item.fileURLs.first, let data = try? Data(contentsOf: url) {
      let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
      return FullContent(data: data, mime: mime, filename: url.lastPathComponent, kind: .file)
    }
    if let imageData = item.imageData, let png = pngData(imageData) {
      return FullContent(data: png, mime: "image/png", filename: "image.png", kind: .image)
    }
    let string = item.previewableText
    if !string.isEmpty {
      return FullContent(data: Data(string.utf8), mime: "text/plain", filename: nil, kind: .text)
    }
    return nil
  }

  // MARK: - Remote meta -> local pasteboard

  /// Writes the remote item to the general pasteboard. `content` must be
  /// supplied for image/file (and large text); inline text uses meta.text.
  /// Returns true on success.
  @discardableResult
  static func apply(meta: ItemMeta, content: Data?) -> Bool {
    let pb = NSPasteboard.general
    pb.clearContents()

    switch meta.kindEnum {
    case .text:
      let text = meta.text ?? content.flatMap { String(data: $0, encoding: .utf8) }
      guard let text else { return false }
      pb.setString(text, forType: .string)

    case .image:
      guard let data = content else { return false }
      pb.setData(data, forType: .png)

    case .file:
      guard let data = content else { return false }
      let name = meta.filename ?? "\(meta.id).bin"
      let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      let url = dir.appendingPathComponent(name)
      do {
        try data.write(to: url)
      } catch {
        return false
      }
      pb.writeObjects([url as NSURL])
    }

    pb.setString("", forType: .fromMaccy)
    return true
  }

  // MARK: - Image helpers

  static func pngData(_ data: Data) -> Data? {
    guard let rep = NSBitmapImageRep(data: data) else { return nil }
    return rep.representation(using: .png, properties: [:])
  }

  static func thumbnail(_ data: Data, maxPixel: Int) -> Data? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
      kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    let rep = NSBitmapImageRep(cgImage: cg)
    return rep.representation(using: .png, properties: [:])
  }
}
