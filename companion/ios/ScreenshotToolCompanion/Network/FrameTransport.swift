import Foundation
import CoreVideo
import UIKit

class FrameTransport {
    private let client: WebSocketClient
    private var lastFrameTime: CFAbsoluteTime = 0
    private let minFrameInterval: CFAbsoluteTime

    init(client: WebSocketClient, fps: Int = 10) {
        self.client = client
        self.minFrameInterval = 1.0 / Double(fps)
    }

    /// Convert a CVPixelBuffer to JPEG and send via WebSocket to all connected desktops.
    /// Rate-limited to configured fps.
    func sendFrame(from pixelBuffer: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime >= minFrameInterval else { return }
        lastFrameTime = now

        guard let jpegData = pixelBufferToJpeg(pixelBuffer, quality: 0.7) else { return }
        client.sendFrameToAll(jpegData)
    }

    /// Convert a CGImage to JPEG and send.
    func sendFrame(from cgImage: CGImage) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime >= minFrameInterval else { return }
        lastFrameTime = now

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else { return }
        client.sendFrameToAll(jpegData)
    }

    /// Convert a CGImage to PNG and send as screenshot result.
    func sendScreenshot(from cgImage: CGImage) {
        let uiImage = UIImage(cgImage: cgImage)
        guard let pngData = uiImage.pngData() else { return }
        client.sendScreenshotToAll(pngData)
    }

    private func pixelBufferToJpeg(_ pixelBuffer: CVPixelBuffer, quality: CGFloat) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }
}
