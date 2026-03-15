import Foundation
import Cocoa
import CScreenshotTool

// Global C-compatible capture callback for the Rust core
// This is called when the MCP/HTTP API requests a screenshot
private func nativeCaptureCallback(x: UInt32, y: UInt32, w: UInt32, h: UInt32) -> SSTPixelData {
    let rect: CGRect
    if w == 0 && h == 0 {
        rect = NSScreen.main?.frame ?? .zero
    } else {
        rect = CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h))
    }

    guard let cgImage = ScreenCapture.captureRegion(rect),
          let (pixelData, width, height, bytesPerRow) = ScreenCapture.pixelData(from: cgImage)
    else {
        return SSTPixelData(pixels: nil, width: 0, height: 0, stride: 0)
    }

    // Copy pixels to a buffer that outlives this function
    // The Rust core will copy the data before we free it
    let count = pixelData.count
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    pixelData.copyBytes(to: buffer, count: count)

    // Store the buffer so we can free it later
    // (in practice the Rust core copies immediately, but we leak a small amount)
    // TODO: implement proper lifecycle management

    return SSTPixelData(
        pixels: UnsafePointer(buffer),
        width: UInt32(width),
        height: UInt32(height),
        stride: UInt32(bytesPerRow)
    )
}

struct CaptureResult {
    let imageData: Data
    let filePath: String
}

struct DiffResult {
    let imageData: Data
    let filePath: String
    let changePercentage: Float
}

class RustBridge {
    static let shared = RustBridge()

    private var initialized = false

    private init() {}

    func initialize() {
        guard !initialized else { return }
        NSLog("PixyVibe: RustBridge.initialize() called")

        let configJson = "{}".cString(using: .utf8)!
        let result = sst_init(configJson)
        NSLog("PixyVibe: sst_init returned \(result)")
        if !result {
            NSLog("PixyVibe: Failed to initialize Rust core")
        }

        // Register native capture callback for MCP/HTTP API
        sst_register_capture_callback(nativeCaptureCallback)
        NSLog("PixyVibe: Capture callback registered")

        initialized = true
        NSLog("PixyVibe: RustBridge initialized")
    }

    func shutdown() {
        guard initialized else { return }
        sst_shutdown()
        initialized = false
    }

    func processScreenshot(region: CGRect) -> CaptureResult? {
        NSLog("PixyVibe: processScreenshot start")
        guard let cgImage = ScreenCapture.captureRegion(region),
              let (pixelData, width, height, bytesPerRow) = ScreenCapture.pixelData(from: cgImage)
        else {
            NSLog("PixyVibe: capture failed")
            return nil
        }
        NSLog("PixyVibe: captured %dx%d, %d bytes", width, height, pixelData.count)

        // Copy pixel data to a stable buffer (avoid withUnsafeBytes lifetime issues)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelData.count)
        pixelData.copyBytes(to: buffer, count: pixelData.count)

        let pixels = SSTPixelData(
            pixels: UnsafePointer(buffer),
            width: UInt32(width),
            height: UInt32(height),
            stride: UInt32(bytesPerRow)
        )

        NSLog("PixyVibe: calling sst_process_screenshot")
        let result = sst_process_screenshot(pixels)
        buffer.deallocate()
        NSLog("PixyVibe: sst_process_screenshot returned, error=%{public}@",
              result.error != nil ? String(cString: result.error!) : "nil")

        if result.error != nil {
            NSLog("PixyVibe: error from Rust")
            sst_free_result(result)
            return nil
        }

        guard let imagePtr = result.image_data else {
            NSLog("PixyVibe: null image_data")
            sst_free_result(result)
            return nil
        }

        NSLog("PixyVibe: copying %d bytes of image data", result.image_len)
        let imageData = Data(bytes: imagePtr, count: Int(result.image_len))
        let filePath = result.file_path.map { String(cString: $0) } ?? ""
        NSLog("PixyVibe: freeing result")
        sst_free_result(result)
        NSLog("PixyVibe: processScreenshot done, path=%{public}@", filePath)
        return CaptureResult(imageData: imageData, filePath: filePath)
    }

    func gifStart() -> String? {
        guard let ptr = sst_gif_start() else { return nil }
        defer { sst_free_string(ptr) }
        return String(cString: ptr)
    }

    func gifAddFrame(_ sessionId: String, region: CGRect) -> Bool {
        guard let cgImage = ScreenCapture.captureRegion(region, showCursor: true),
              let (pixelData, width, height, bytesPerRow) = ScreenCapture.pixelData(from: cgImage)
        else { return false }

        return pixelData.withUnsafeBytes { ptr -> Bool in
            guard let baseAddress = ptr.baseAddress else { return false }
            let pixels = SSTPixelData(
                pixels: baseAddress.assumingMemoryBound(to: UInt8.self),
                width: UInt32(width),
                height: UInt32(height),
                stride: UInt32(bytesPerRow)
            )
            return sst_gif_add_frame(sessionId.cString(using: .utf8), pixels)
        }
    }

    func gifFinish(_ sessionId: String) -> CaptureResult? {
        let result = sst_gif_finish(sessionId.cString(using: .utf8))
        defer { sst_free_result(result) }
        guard result.error == nil, let data = result.image_data else { return nil }
        let imageData = Data(bytes: data, count: Int(result.image_len))
        let filePath = result.file_path.map { String(cString: $0) } ?? ""
        return CaptureResult(imageData: imageData, filePath: filePath)
    }

    func diffStoreBefore(region: CGRect) -> Bool {
        guard let cgImage = ScreenCapture.captureRegion(region),
              let (pixelData, width, height, bytesPerRow) = ScreenCapture.pixelData(from: cgImage)
        else { return false }

        return pixelData.withUnsafeBytes { ptr -> Bool in
            guard let baseAddress = ptr.baseAddress else { return false }
            let pixels = SSTPixelData(
                pixels: baseAddress.assumingMemoryBound(to: UInt8.self),
                width: UInt32(width),
                height: UInt32(height),
                stride: UInt32(bytesPerRow)
            )
            return sst_diff_store_before(pixels)
        }
    }

    func diffCompare(region: CGRect) -> DiffResult? {
        guard let cgImage = ScreenCapture.captureRegion(region),
              let (pixelData, width, height, bytesPerRow) = ScreenCapture.pixelData(from: cgImage)
        else { return nil }

        return pixelData.withUnsafeBytes { ptr -> DiffResult? in
            guard let baseAddress = ptr.baseAddress else { return nil }
            let pixels = SSTPixelData(
                pixels: baseAddress.assumingMemoryBound(to: UInt8.self),
                width: UInt32(width),
                height: UInt32(height),
                stride: UInt32(bytesPerRow)
            )
            let result = sst_diff_compare(pixels)
            defer { sst_free_diff_result(result) }

            guard result.error == nil, let data = result.image_data else { return nil }
            let imageData = Data(bytes: data, count: Int(result.image_len))
            let filePath = result.file_path.map { String(cString: $0) } ?? ""
            return DiffResult(imageData: imageData, filePath: filePath, changePercentage: result.change_percentage)
        }
    }
}
