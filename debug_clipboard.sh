#!/bin/bash
# Run this right after copying a GIF to debug clipboard contents
swift -e '
import Cocoa

let pb = NSPasteboard.general
print("=== Clipboard Contents ===")
print("Types (\(pb.types?.count ?? 0)):")
for type in pb.types ?? [] {
    let data = pb.data(forType: type)
    let size = data?.count ?? 0
    var info = "\(size) bytes"
    if let d = data, size > 0 {
        if d.prefix(4) == Data([0x47, 0x49, 0x46, 0x38]) { info += " [GIF]" }
        else if d.prefix(4) == Data([0x89, 0x50, 0x4e, 0x47]) { info += " [PNG]" }
        else if d.prefix(2) == Data([0x4d, 0x4d]) || d.prefix(2) == Data([0x49, 0x49]) { info += " [TIFF]" }
    }
    print("  \(type.rawValue) — \(info)")
}
if let url = pb.string(forType: .fileURL) { print("\nFile URL: \(url)") }
'
