import Cocoa

struct ScreenshotEntry {
    let filePath: String
    let timestamp: Date
    let imageData: Data

    var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: timestamp)
    }

    func thumbnail(maxSize: CGFloat = 48) -> NSImage? {
        guard let image = NSImage(data: imageData) else { return nil }
        let aspect = image.size.width / image.size.height
        let thumbSize: NSSize
        if aspect > 1 {
            thumbSize = NSSize(width: maxSize, height: maxSize / aspect)
        } else {
            thumbSize = NSSize(width: maxSize * aspect, height: maxSize)
        }
        let thumb = NSImage(size: thumbSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: thumbSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }
}

class ScreenshotHistory {
    static let shared = ScreenshotHistory()

    private(set) var entries: [ScreenshotEntry] = []
    private let maxEntries = 10

    private var indexFileURL: URL {
        let dir = NSHomeDirectory() + "/.pixyvibe"
        return URL(fileURLWithPath: dir).appendingPathComponent("history.json")
    }

    private init() {
        loadFromDisk()
    }

    func add(imageData: Data, filePath: String) {
        let entry = ScreenshotEntry(
            filePath: filePath,
            timestamp: Date(),
            imageData: imageData
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast()
        }
        saveToDisk()
    }

    func remove(filePath: String) {
        entries.removeAll { $0.filePath == filePath }
        saveToDisk()
    }

    func clear() {
        entries.removeAll()
        saveToDisk()
    }

    // MARK: - Persistence

    private struct PersistedEntry: Codable {
        let filePath: String
        let timestamp: Date
    }

    private func saveToDisk() {
        let persisted = entries.map { PersistedEntry(filePath: $0.filePath, timestamp: $0.timestamp) }
        if let data = try? JSONEncoder().encode(persisted) {
            try? data.write(to: indexFileURL)
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let persisted = try? JSONDecoder().decode([PersistedEntry].self, from: data) else { return }

        entries = persisted.prefix(maxEntries).compactMap { entry in
            guard FileManager.default.fileExists(atPath: entry.filePath),
                  let imageData = try? Data(contentsOf: URL(fileURLWithPath: entry.filePath)) else { return nil }
            return ScreenshotEntry(filePath: entry.filePath, timestamp: entry.timestamp, imageData: imageData)
        }
    }
}

extension Notification.Name {
    static let screenshotHistoryChanged = Notification.Name("screenshotHistoryChanged")
}
