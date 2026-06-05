import AppKit
import SwiftUI

// The paired phone's clipboard history, browsed on demand from the Mac.
struct RemoteClipboardView: View {
  var onClose: () -> Void

  @State private var store = RemoteClipStore.shared
  @State private var sync = LanSyncService.shared
  @State private var query = ""
  @State private var selection = 0
  @FocusState private var searchFocused: Bool

  private var items: [ItemMeta] {
    guard !query.isEmpty else { return store.items }
    return store.items.filter { $0.preview.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      if sync.state != .connected {
        disconnected
      } else if items.isEmpty {
        empty
      } else {
        list
      }
    }
    .frame(minWidth: 380, minHeight: 360)
    .background(.regularMaterial)
    .onKeyPress(.escape) { onClose(); return .handled }
    .onKeyPress(.downArrow) { move(1); return .handled }
    .onKeyPress(.upArrow) { move(-1); return .handled }
    .onKeyPress(.return) { applySelected(); return .handled }
    .onAppear { searchFocused = true }
  }

  private var header: some View {
    HStack(spacing: 6) {
      Image(systemName: "iphone")
      Text(headerTitle).font(.headline)
      Spacer()
      Circle()
        .fill(sync.state == .connected ? Color.green : Color.secondary)
        .frame(width: 8, height: 8)
      Text(statusText).font(.caption).foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .overlay(alignment: .bottom) {
      TextField("Search", text: $query)
        .textFieldStyle(.roundedBorder)
        .focused($searchFocused)
        .padding(.horizontal, 12)
        .padding(.top, 36)
        .onChange(of: query) { selection = 0 }
    }
    .padding(.bottom, 36)
  }

  private var list: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, meta in
            RemoteClipRow(meta: meta, selected: index == selection)
              .id(index)
              .contentShape(Rectangle())
              .onTapGesture { selection = index; applySelected() }
          }
        }
        .padding(6)
      }
      .onChange(of: selection) { proxy.scrollTo(selection, anchor: .center) }
    }
  }

  private var disconnected: some View {
    VStack(spacing: 10) {
      Image(systemName: "iphone.slash").font(.largeTitle).foregroundStyle(.secondary)
      Text("No phone connected").font(.headline)
      Text(sync.isPaired
           ? "Waiting for \(sync.pairedDevice?.name ?? "your phone") to reconnect…"
           : "Pair the Maccy Android app in Sync settings.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("Open Sync Settings…") {
        onClose()
        AppState.shared.openPreferences()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private var empty: some View {
    VStack(spacing: 8) {
      Image(systemName: "clipboard").font(.largeTitle).foregroundStyle(.secondary)
      Text("No clips from \(store.peerName.isEmpty ? "phone" : store.peerName) yet")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private var headerTitle: String {
    store.peerName.isEmpty ? "Phone Clipboard" : store.peerName
  }

  private var statusText: String {
    switch sync.state {
    case .connected: return "Connected"
    case .pairing: return "Pairing…"
    case .listening: return "Waiting"
    case .off: return "Off"
    }
  }

  private func move(_ delta: Int) {
    guard !items.isEmpty else { return }
    selection = Swift.max(0, Swift.min(items.count - 1, selection + delta))
  }

  private func applySelected() {
    guard items.indices.contains(selection) else { return }
    let meta = items[selection]
    onClose()
    Task { @MainActor in
      let ok = await sync.applyRemote(meta)
      guard ok else { return }
      try? await Task.sleep(nanoseconds: 120_000_000)
      Clipboard.shared.paste()
    }
  }
}

private struct RemoteClipRow: View {
  let meta: ItemMeta
  let selected: Bool

  var body: some View {
    HStack(spacing: 10) {
      icon
      VStack(alignment: .leading, spacing: 2) {
        Text(meta.preview.isEmpty ? meta.filename ?? "Untitled" : meta.preview)
          .lineLimit(2)
          .font(.system(size: 12))
        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(selected ? Color.accentColor.opacity(0.25) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  @ViewBuilder
  private var icon: some View {
    if meta.kindEnum == .image, let thumb = meta.thumb,
       let data = Data(base64Encoded: thumb), let image = NSImage(data: data) {
      Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 4))
    } else {
      Image(systemName: symbol).frame(width: 28, height: 28).foregroundStyle(.secondary)
    }
  }

  private var symbol: String {
    switch meta.kindEnum {
    case .text: return "doc.text"
    case .image: return "photo"
    case .file: return "doc"
    }
  }

  private var subtitle: String {
    let date = Date(timeIntervalSince1970: Double(meta.createdAt) / 1000)
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    let when = formatter.localizedString(for: date, relativeTo: Date())
    switch meta.kindEnum {
    case .text: return when
    case .image: return "Image · \(when)"
    case .file: return "\(meta.filename ?? "File") · \(when)"
    }
  }
}
