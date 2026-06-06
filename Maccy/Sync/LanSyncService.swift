import AppKit
import Defaults
import Foundation
import Network
import Observation

// Central LAN sync orchestrator. Mac is the server: it listens, advertises via
// Bonjour, accepts one phone, runs the handshake, then exchanges history/clips.
// Conforms to the existing `SyncService` seam used by SendToAndroidAction.
@MainActor
@Observable
final class LanSyncService: SyncService {
  static let shared = LanSyncService()

  enum State: Equatable { case off, listening, pairing, connected }

  private(set) var state: State = .off
  private(set) var connectedPeerName: String = ""
  /// QR JSON to display while pairing (nil when not pairing).
  private(set) var pairingQR: String?

  var pairedDevice: PairedDevice? { Defaults[.syncPairedDevice] }
  var isPaired: Bool { pairedDevice != nil }

  let identity = SyncIdentity.loadOrCreate()

  private var listener: NWListener?
  private var peer: PeerConnection?
  private var pairingToken: String?
  private var pendingPairingIdPub: Data?

  private var announced: [String: HistoryItem] = [:]
  private var fetchBuffers: [String: Data] = [:]
  private var fetchConts: [String: CheckedContinuation<Data, Error>] = [:]
  private var pingTimer: Timer?

  // MARK: - Lifecycle

  func start() {
    guard Defaults[.syncEnabled] else { return }
    startListener()
  }

  func stop() {
    pingTimer?.invalidate()
    peer?.cancel()
    peer = nil
    listener?.cancel()
    listener = nil
    state = .off
    pairingQR = nil
    pairingToken = nil
  }

  func restart() {
    stop()
    start()
  }

  private func startListener() {
    guard listener == nil else { return }
    do {
      let params = NWParameters.tcp
      let portValue = UInt16(exactly: Defaults[.syncPort]) ?? SyncProtocol.defaultPort
      let port = NWEndpoint.Port(rawValue: portValue) ?? NWEndpoint.Port(rawValue: SyncProtocol.defaultPort)!
      let listener = try NWListener(using: params, on: port)
      listener.service = NWListener.Service(name: Defaults[.syncDeviceName], type: SyncProtocol.bonjourType)
      listener.newConnectionHandler = { [weak self] conn in
        Task { @MainActor in self?.accept(conn) }
      }
      listener.stateUpdateHandler = { [weak self] st in
        Task { @MainActor in self?.handleListenerState(st) }
      }
      listener.start(queue: .global(qos: .userInitiated))
      self.listener = listener
      if state == .off { state = .listening }
    } catch {
      state = .off
    }
  }

  private func handleListenerState(_ state: NWListener.State) {
    if case .failed = state {
      self.listener = nil
      if self.state != .connected { self.state = .off }
    }
  }

  // MARK: - Accept + wire a peer

  private func accept(_ connection: NWConnection) {
    let trust: PeerConnection.Trust
    if pairingToken != nil {
      trust = PeerConnection.Trust(expectedPeerIdPub: nil, pairingToken: pairingToken)
    } else if let paired = pairedDevice, let idPub = Data(base64Encoded: paired.idPub) {
      trust = PeerConnection.Trust(expectedPeerIdPub: idPub, pairingToken: nil)
    } else {
      connection.cancel()  // nothing paired and not pairing
      return
    }

    peer?.cancel()
    let peer = PeerConnection(role: .server, connection: connection, identity: identity, trust: trust)
    self.peer = peer

    peer.onEstablished = { [weak self] in
      Task { @MainActor in self?.onEstablished() }
    }
    peer.onControl = { [weak self] msg in
      Task { @MainActor in self?.handleControl(msg) }
    }
    peer.onContent = { [weak self] chunk in
      Task { @MainActor in self?.handleContent(chunk) }
    }
    peer.onNewPairing = { [weak self] idPub in
      Task { @MainActor in self?.pendingPairingIdPub = idPub }
    }
    peer.onClosed = { [weak self] _ in
      Task { @MainActor in self?.onPeerClosed(peer) }
    }
    peer.start()
  }

  private func onEstablished() {
    send(.hello(deviceId: Defaults[.syncDeviceId], name: Defaults[.syncDeviceName],
                platform: "macos", protocolVersion: SyncProtocol.version))
    sendHistorySync()
    startPingTimer()
  }

  private func onPeerClosed(_ closed: PeerConnection) {
    guard peer === closed else { return }
    peer = nil
    pingTimer?.invalidate()
    connectedPeerName = ""
    // Resume any pending fetches with failure.
    for (_, cont) in fetchConts { cont.resume(throwing: SyncCryptoError.openFailed) }
    fetchConts.removeAll()
    fetchBuffers.removeAll()
    state = listener != nil ? .listening : .off
  }

  private func send(_ message: SyncMessage) {
    peer?.send(message)
  }

  // MARK: - Inbound control

  private func handleControl(_ message: SyncMessage) {
    switch message {
    case let .hello(deviceId, name, _, _):
      connectedPeerName = name
      RemoteClipStore.shared.peerName = name
      state = .connected
      if let idPub = pendingPairingIdPub {
        Defaults[.syncPairedDevice] = PairedDevice(
          deviceId: deviceId, name: name, idPub: idPub.base64EncodedString(), pairedAt: Date())
        pendingPairingIdPub = nil
        pairingToken = nil
        pairingQR = nil
      }

    case let .historySync(items):
      RemoteClipStore.shared.replaceAll(items, peerName: connectedPeerName)

    case let .clipAdded(item):
      RemoteClipStore.shared.add(item)

    case let .contentRequest(id):
      serveContent(id: id)

    case let .contentBegin(id, _, _, _, _):
      fetchBuffers[id] = Data()

    case let .contentError(id, _):
      if let cont = fetchConts.removeValue(forKey: id) {
        cont.resume(throwing: SyncCryptoError.openFailed)
      }
      fetchBuffers[id] = nil

    case .ping:
      send(.pong)

    case .pong, .hs1, .hs2, .hs3:
      break
    }
  }

  private func handleContent(_ chunk: ContentChunk) {
    let id = chunk.id.uuidString.lowercased()
    var buffer = fetchBuffers[id] ?? Data()
    buffer.append(chunk.bytes)
    fetchBuffers[id] = buffer
    guard chunk.last else { return }
    RemoteClipStore.shared.storeContent(buffer, for: id)
    fetchBuffers[id] = nil
    if let cont = fetchConts.removeValue(forKey: id) {
      cont.resume(returning: buffer)
    }
  }

  // MARK: - Serving content to the peer

  private func serveContent(id: String) {
    guard let item = announced[id], let full = SyncContent.fullContent(for: item) else {
      send(.contentError(id: id, reason: "not_found"))
      return
    }
    guard full.data.count <= SyncProtocol.maxContent else {
      send(.contentError(id: id, reason: "too_large"))
      return
    }
    send(.contentBegin(id: id, kind: full.kind.rawValue, size: full.data.count,
                       mime: full.mime, filename: full.filename))
    guard let uuid = UUID(uuidString: id) else { return }
    let data = full.data
    var seq: UInt32 = 0
    var offset = 0
    if data.isEmpty {
      peer?.send(ContentChunk(id: uuid, seq: 0, last: true, bytes: Data()))
      return
    }
    while offset < data.count {
      let end = Swift.min(offset + SyncProtocol.chunkSize, data.count)
      let slice = data.subdata(in: offset..<end)
      let last = end >= data.count
      peer?.send(ContentChunk(id: uuid, seq: seq, last: last, bytes: slice))
      seq += 1
      offset = end
    }
  }

  // MARK: - Fetching content from the peer

  func fetchContent(id: String) async throws -> Data {
    if let cached = RemoteClipStore.shared.cachedContent(for: id) { return cached }
    return try await withCheckedThrowingContinuation { cont in
      fetchConts[id] = cont
      fetchBuffers[id] = Data()
      send(.contentRequest(id: id))
    }
  }

  /// Pull a remote item to the local pasteboard. Returns true on success.
  func applyRemote(_ meta: ItemMeta) async -> Bool {
    var content: Data?
    if meta.kindEnum == .text, meta.text != nil {
      content = nil
    } else {
      content = try? await fetchContent(id: meta.id)
      if content == nil { return false }
    }
    return SyncContent.apply(meta: meta, content: content)
  }

  // MARK: - Outbound (local copy -> peer)

  private func sendHistorySync() {
    let recent = recentLocalItems()
    var metas: [ItemMeta] = []
    for item in recent {
      let id = UUID().uuidString
      guard let meta = SyncContent.meta(
        for: item, id: id,
        sendText: Defaults[.syncSendText],
        sendImages: Defaults[.syncSendImages],
        sendFiles: Defaults[.syncSendFiles]) else { continue }
      announced[id] = item
      metas.append(meta)
    }
    send(.historySync(items: metas))
  }

  func pushClip(_ item: HistoryItem) {
    guard peer != nil, !item.fromMaccy else { return }
    let id = UUID().uuidString
    guard let meta = SyncContent.meta(
      for: item, id: id,
      sendText: Defaults[.syncSendText],
      sendImages: Defaults[.syncSendImages],
      sendFiles: Defaults[.syncSendFiles]) else { return }
    announced[id] = item
    send(.clipAdded(item: meta))
  }

  // Explicit "Send to Phone" — sends any kind including files, ignoring the
  // auto-send filters. This is the only path that pushes a file to the phone.
  func sendItem(_ item: HistoryItem) {
    guard peer != nil else { return }
    let id = UUID().uuidString
    guard let meta = SyncContent.meta(
      for: item, id: id, sendText: true, sendImages: true, sendFiles: true) else { return }
    announced[id] = item
    send(.clipAdded(item: meta))
  }

  private func recentLocalItems() -> [HistoryItem] {
    Array(AppState.shared.history.all.prefix(SyncProtocol.historySyncCount).map { $0.item })
  }

  // MARK: - SyncService (used by SendToAndroidAction)

  func send(_ value: String) async throws {
    guard peer != nil else { return }
    let id = UUID().uuidString
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let meta = ItemMeta(id: id, kind: "text", createdAt: now, size: value.utf8.count,
                        mime: "text/plain", preview: String(value.prefix(280)),
                        text: value, filename: nil, thumb: nil)
    send(.clipAdded(item: meta))
  }

  // MARK: - Pairing

  func enterPairingMode() {
    if Defaults[.syncEnabled] == false { Defaults[.syncEnabled] = true }
    startListener()
    let token = Self.randomToken()
    pairingToken = token
    pendingPairingIdPub = nil
    state = .pairing
    pairingQR = buildQRPayload(token: token)
  }

  func cancelPairing() {
    pairingToken = nil
    pairingQR = nil
    pendingPairingIdPub = nil
    state = (peer != nil) ? .connected : (listener != nil ? .listening : .off)
  }

  func unpair() {
    Defaults[.syncPairedDevice] = nil
    peer?.cancel()
    peer = nil
    RemoteClipStore.shared.clear()
    state = listener != nil ? .listening : .off
  }

  private func buildQRPayload(token: String) -> String {
    let hosts = Self.localIPv4Addresses()
    let payload: [String: Any] = [
      "v": 1,
      "host": hosts.first ?? "",
      "hosts": hosts,
      "port": Defaults[.syncPort],
      "idpub": identity.pin,
      "token": token,
      "name": Defaults[.syncDeviceName],
      "deviceId": Defaults[.syncDeviceId]
    ]
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return String(data: data, encoding: .utf8) ?? ""
  }

  // MARK: - Keepalive

  private func startPingTimer() {
    pingTimer?.invalidate()
    pingTimer = Timer.scheduledTimer(withTimeInterval: SyncProtocol.pingInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.send(.ping) }
    }
  }

  // MARK: - Helpers

  static func randomToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64EncodedString()
  }

  static func localIPv4Addresses() -> [String] {
    var addresses: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return addresses }
    defer { freeifaddrs(ifaddr) }
    var pointer: UnsafeMutablePointer<ifaddrs>? = first
    while let current = pointer {
      let flags = Int32(current.pointee.ifa_flags)
      let addr = current.pointee.ifa_addr.pointee
      if (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
         (flags & IFF_LOOPBACK) == 0,
         addr.sa_family == UInt8(AF_INET) {
        let name = String(cString: current.pointee.ifa_name)
        if name.hasPrefix("en") {
          var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
          if getnameinfo(current.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname,
                         socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
            let ip = String(cString: hostname)
            if !ip.isEmpty, !addresses.contains(ip) { addresses.append(ip) }
          }
        }
      }
      pointer = current.pointee.ifa_next
    }
    return addresses
  }
}
