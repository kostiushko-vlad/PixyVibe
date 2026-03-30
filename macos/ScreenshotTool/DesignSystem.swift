import SwiftUI
import Cocoa

// MARK: - PixyVibe Design System

enum PV {
    // MARK: Colors

    enum Colors {
        static let base = Color(hex: 0x0D0F14)
        static let surface = Color(hex: 0x161B22)
        static let surfaceHigh = Color(hex: 0x1C2333)
        static let border = Color(hex: 0x2D3548)
        static let textPrimary = Color(hex: 0xE6EDF3)
        static let textSecondary = Color(hex: 0x8B949E)

        // NS variants for AppKit
        static let nsBase = NSColor(hex: 0x0D0F14)
        static let nsSurface = NSColor(hex: 0x161B22)
        static let nsSurfaceHigh = NSColor(hex: 0x1C2333)
        static let nsBorder = NSColor(hex: 0x2D3548)
        static let nsTextPrimary = NSColor(hex: 0xE6EDF3)
        static let nsTextSecondary = NSColor(hex: 0x8B949E)
    }

    // MARK: Gradients

    enum Gradients {
        // ┌─────────────────────────────────────────────────┐
        // │  ACCENT PALETTE — change these two hex values   │
        // │  to switch the entire app's accent gradient.    │
        // │                                                 │
        // │  1  Electric Indigo:  0x6366F1, 0x8B5CF6        │
        // │  2  Neon Teal:        0x14B8A6, 0x0EA5E9        │
        // │  3  Sunset:           0xF97316, 0xEF4444        │
        // │  4  Rose:             0xEC4899, 0xA855F7        │
        // │  5  Emerald:          0x10B981, 0x06B6D4        │
        // │  6  Amber:            0xF59E0B, 0xEF4444        │
        // │  7  Ice:              0x38BDF8, 0x818CF8        │
        // │  8  Fuchsia:          0xD946EF, 0xEC4899        │
        // │  9  Copper:           0xFB923C, 0xF472B6        │
        // │  10 Slate Blue:       0x6366F1, 0x38BDF8        │
        // └─────────────────────────────────────────────────┘
        private static let _start: UInt32 = 0x38BDF8
        private static let _end:   UInt32 = 0x818CF8

        static let accent = LinearGradient(
            colors: [Color(hex: _start), Color(hex: _end)],
            startPoint: .leading, endPoint: .trailing
        )
        static let recording = LinearGradient(
            colors: [Color(hex: 0xEF4444), Color(hex: 0xF97316)],
            startPoint: .leading, endPoint: .trailing
        )
        static let success = LinearGradient(
            colors: [Color(hex: 0x10B981), Color(hex: 0x06B6D4)],
            startPoint: .leading, endPoint: .trailing
        )

        /// Primary accent color (for solid tints/shadows)
        static let accentSolid = Color(hex: _start)

        // Raw color values for CGGradient
        static let accentStart = NSColor(hex: _start)
        static let accentEnd = NSColor(hex: _end)
        static let recordingStart = NSColor(hex: 0xEF4444)
        static let recordingEnd = NSColor(hex: 0xF97316)
        static let successStart = NSColor(hex: 0x10B981)
        static let successEnd = NSColor(hex: 0x06B6D4)

        static func cgAccent() -> CGGradient? {
            makeCGGradient(colors: [accentStart, accentEnd])
        }

        static func cgRecording() -> CGGradient? {
            makeCGGradient(colors: [recordingStart, recordingEnd])
        }

        static func cgSuccess() -> CGGradient? {
            makeCGGradient(colors: [successStart, successEnd])
        }

        private static func makeCGGradient(colors: [NSColor]) -> CGGradient? {
            let cgColors = colors.compactMap { $0.cgColor } as CFArray
            return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil)
        }
    }

    // MARK: Radii

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    // MARK: Animations

    enum Anim {
        static let snappy: Animation = .spring(duration: 0.3, bounce: 0.15)
        static let smooth: Animation = .spring(duration: 0.5, bounce: 0.12)
        static let bouncy: Animation = .spring(duration: 0.6, bounce: 0.3)
        static let pulse: Animation = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        static let hover: Animation = .spring(duration: 0.2, bounce: 0.1)
    }

    // MARK: Borders

    enum Border {
        static let thin: CGFloat = 0.5
        static let focus: CGFloat = 1.0
        static let thinColor = Color.white.opacity(0.06)
        static let focusColor = Color.white.opacity(0.10)
        static let nsThinColor = NSColor.white.withAlphaComponent(0.06)
        static let nsFocusColor = NSColor.white.withAlphaComponent(0.10)
    }

    // MARK: Shadows

    enum Shadow {
        static let accentColor = Color(hex: 0x10B981).opacity(0.3)
        static let accentRadius: CGFloat = 12
        static let subtleColor = Color.black.opacity(0.4)
        static let subtleRadius: CGFloat = 8
    }
}

// MARK: - Glass Background Modifier

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = PV.Radius.medium

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(PV.Border.thinColor, lineWidth: PV.Border.thin)
            )
    }
}

extension View {
    func pvGlass(cornerRadius: CGFloat = PV.Radius.medium) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Gradient Button Background

struct GradientButtonBackground: View {
    let gradient: LinearGradient
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(gradient)
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

// MARK: - CGGradient stroke helper

extension NSBezierPath {
    /// Stroke this path with a CGGradient along its bounding box.
    func strokeWithGradient(_ gradient: CGGradient?, lineWidth: CGFloat, in ctx: CGContext) {
        guard let gradient = gradient else { return }
        ctx.saveGState()
        let strokedPath = self.copy() as! NSBezierPath
        strokedPath.lineWidth = lineWidth
        strokedPath.lineCapStyle = .round

        // Convert NSBezierPath to CGPath
        let cgPath = strokedPath.cgPathForStroke()
        ctx.addPath(cgPath)
        ctx.replacePathWithStrokedPath()
        ctx.clip()

        let box = cgPath.boundingBoxOfPath
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: box.minX, y: box.midY),
            end: CGPoint(x: box.maxX, y: box.midY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }
}

extension NSBezierPath {
    /// Convert NSBezierPath to CGPath for use with Core Graphics.
    func cgPathForStroke() -> CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }
        return path
    }
}
