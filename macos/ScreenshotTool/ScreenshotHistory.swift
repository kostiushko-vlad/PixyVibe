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

    private init() {}

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
    }

    func clear() {
        entries.removeAll()
    }
}
