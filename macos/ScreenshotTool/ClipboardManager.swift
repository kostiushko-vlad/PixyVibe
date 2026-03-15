import Cocoa

class ClipboardManager {
    static func copyImage(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        }
    }

    static func copyFilePath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    static func copyGif(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // GIF type for pasteboard
        let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
        pasteboard.setData(data, forType: gifType)
    }
}
