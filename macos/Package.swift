// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenshotTool",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CScreenshotTool",
            path: "CScreenshotTool",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "ScreenshotTool",
            dependencies: ["CScreenshotTool"],
            path: "ScreenshotTool",
            swiftSettings: [
                .define("LINK_RUST_CORE")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "../core/target/release",
                    "-lscreenshottool",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../lib",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "../core/target/release"
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
