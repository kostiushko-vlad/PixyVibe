import Cocoa
import ScreenCaptureKit

class ScreenCapture {
    /// Capture a specific region of the screen using ScreenCaptureKit.
    /// `rect` is in AppKit global coordinates (origin at bottom-left of main screen).
    /// `showCursor` includes the mouse pointer in the capture (useful for GIF recording).
    static func captureRegion(_ rect: CGRect, showCursor: Bool = false) -> CGImage? {
        var resultImage: CGImage?
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            resultImage = await captureRegionAsync(rect, showCursor: showCursor)
            semaphore.signal()
        }

        semaphore.wait()
        return resultImage
    }

    private static func captureRegionAsync(_ rect: CGRect, showCursor: Bool) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let display = content.displays.first(where: { display in
                let displayFrame = CGRect(
                    x: CGFloat(display.frame.origin.x),
                    y: CGFloat(display.frame.origin.y),
                    width: CGFloat(display.width),
                    height: CGFloat(display.height)
                )
                return displayFrame.intersects(rect)
            }) ?? content.displays.first else {
                NSLog("PixyVibe: No display found for rect")
                return nil
            }

            let ourApp = content.applications.first(where: {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier ?? "com.pixyvibe.screenshottool"
            })
            let excludedApps = ourApp.map { [$0] } ?? []

            let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.scalesToFit = false
            config.width = display.width * 2
            config.height = display.height * 2
            config.showsCursor = showCursor
            config.captureResolution = .best

            guard let mainScreen = NSScreen.screens.first else { return nil }
            let mainHeight = mainScreen.frame.height

            let quartzRect = CGRect(
                x: rect.origin.x - display.frame.origin.x,
                y: mainHeight - rect.origin.y - rect.height - display.frame.origin.y,
                width: rect.width,
                height: rect.height
            )

            config.sourceRect = quartzRect
            config.width = Int(rect.width) * 2
            config.height = Int(rect.height) * 2

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return image

        } catch {
            NSLog("PixyVibe: ScreenCaptureKit error: %@", error.localizedDescription)
            return nil
        }
    }

    /// Capture the entire main screen.
    static func captureFullScreen() -> CGImage? {
        guard let mainScreen = NSScreen.main else { return nil }
        return captureRegion(mainScreen.frame)
    }

    /// Extract raw RGBA pixel data from a CGImage for passing to the Rust core.
    /// Returns (pixelData, width, height, bytesPerRow).
    static func pixelData(from image: CGImage) -> (Data, Int, Int, Int)? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = Data(count: height * bytesPerRow)

        let drawn = pixelData.withUnsafeMutableBytes { ptr -> Bool in
            guard let baseAddress = ptr.baseAddress else { return false }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drawn else { return nil }
        return (pixelData, width, height, bytesPerRow)
    }
}
