import Cocoa

class ClipboardManager {
    /// Copy image data (PNG/JPEG) to clipboard as an image.
    static func copyImage(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        }
    }

    /// Copy a file to clipboard mimicking Finder's behavior.
    /// Works in Notes, Claude Code, Slack, etc.
    static func copyFileAsFinderFull(_ filePath: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let url = URL(fileURLWithPath: filePath)

        // 1. File URL (public.file-url)
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)

        // 2. NSFilenamesPboardType — plist array of file paths
        let plistData = try? PropertyListSerialization.data(
            fromPropertyList: [filePath],
            format: .xml,
            options: 0
        )
        if let data = plistData {
            item.setData(data, forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        }

        // 3. Plain text — the file path as text
        item.setString(filePath, forType: .string)

        // 4. TIFF image — a rendered preview of the file content
        //    (this is what Notes, Slack, etc. read when pasting)
        if let image = NSImage(contentsOfFile: filePath),
           let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }

        pasteboard.writeObjects([item])
    }

    /// Copy file path as plain text.
    static func copyFilePath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }
}
