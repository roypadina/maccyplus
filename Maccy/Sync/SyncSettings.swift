import Defaults
import Foundation

// A remembered peer device (its Ed25519 id pub is its pin).
struct PairedDevice: Codable, Defaults.Serializable, Identifiable, Hashable {
  var deviceId: String
  var name: String
  var idPub: String          // base64 Ed25519 public key — the pin
  var pairedAt: Date

  var id: String { deviceId }
}

extension Defaults.Keys {
  static let syncEnabled = Key<Bool>("syncEnabled", default: true)
  static let syncDeviceName = Key<String>("syncDeviceName", default: SyncSettings.defaultDeviceName)
  static let syncDeviceId = Key<String>("syncDeviceId", default: UUID().uuidString)
  static let syncPort = Key<Int>("syncPort", default: Int(SyncProtocol.defaultPort))
  static let syncPairedDevice = Key<PairedDevice?>("syncPairedDevice", default: nil)
  // Content kinds permitted to leave this device (outbound filter).
  static let syncSendText = Key<Bool>("syncSendText", default: true)
  static let syncSendImages = Key<Bool>("syncSendImages", default: true)
  static let syncSendFiles = Key<Bool>("syncSendFiles", default: true)
}

enum SyncSettings {
  static var defaultDeviceName: String {
    Host.current().localizedName ?? "My Mac"
  }
}
