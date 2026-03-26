import Foundation

struct PairedDevice: Codable {
    let deviceId: String
    var deviceName: String
    var lastSeen: Date
}

/// Persists known companion devices so they always show in the tray,
/// even when not currently connected.
class PairedDeviceStore {
    static let shared = PairedDeviceStore()

    private let key = "paired_companion_devices"
    private let defaults = UserDefaults.standard

    private init() {}

    var devices: [PairedDevice] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([PairedDevice].self, from: data) else { return [] }
        return list
    }

    /// Update or add a device (call when a companion connects).
    func upsert(deviceId: String, deviceName: String) {
        var list = devices
        if let idx = list.firstIndex(where: { $0.deviceId == deviceId }) {
            list[idx].deviceName = deviceName
            list[idx].lastSeen = Date()
        } else {
            list.append(PairedDevice(deviceId: deviceId, deviceName: deviceName, lastSeen: Date()))
        }
        save(list)
    }

    /// Remove a device (user explicitly unpairs).
    func remove(deviceId: String) {
        var list = devices
        list.removeAll { $0.deviceId == deviceId }
        save(list)
    }

    private func save(_ list: [PairedDevice]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: key)
        }
    }
}
