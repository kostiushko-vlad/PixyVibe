import SwiftUI
import Cocoa

// MARK: - Permission Checker

class PermissionChecker: ObservableObject {
    @Published var hasScreenRecording = false
    @Published var hasAccessibility = false

    var allGranted: Bool { hasScreenRecording && hasAccessibility }

    init() {
        refresh()
    }

    func refresh() {
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        hasAccessibility = AXIsProcessTrusted()
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        refresh()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Onboarding View (3 pages)

struct OnboardingView: View {
    @StateObject private var permissions = PermissionChecker()
    @State private var page = 0
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            PV.Colors.base.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                ZStack {
                    if page == 0 { welcomePage.transition(.opacity) }
                    if page == 1 { permissionsPage.transition(.opacity) }
                    if page == 2 { readyPage.transition(.opacity) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Page dots
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == page ? AnyShapeStyle(PV.Gradients.accent) : AnyShapeStyle(PV.Colors.border))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: 480, height: 440)
        .clipped()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(PV.Gradients.accentSolid.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36))
                    .foregroundStyle(PV.Gradients.accent)
            }

            Text("PixyVibe")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(PV.Colors.textPrimary)

            Text("Screenshots, GIFs, and diffs — supercharged.")
                .font(.system(size: 14))
                .foregroundColor(PV.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            accentButton("Get Started") {
                withAnimation(.easeInOut(duration: 0.25)) { page = 1 }
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Page 1: Permissions

    private var permissionsPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Permissions")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(PV.Colors.textPrimary)

            Text("PixyVibe needs two permissions to work properly.")
                .font(.system(size: 13))
                .foregroundColor(PV.Colors.textSecondary)
                .multilineTextAlignment(.center)

            PVCard {
                VStack(spacing: 14) {
                    permissionRow(
                        icon: "record.circle",
                        title: "Screen Recording",
                        subtitle: "Required to capture screenshots and GIFs",
                        granted: permissions.hasScreenRecording,
                        buttonLabel: "Grant",
                        action: { permissions.requestScreenRecording() }
                    )

                    Rectangle()
                        .fill(PV.Border.thinColor)
                        .frame(height: 0.5)

                    permissionRow(
                        icon: "hand.raised",
                        title: "Accessibility",
                        subtitle: "Required for global keyboard shortcuts",
                        granted: permissions.hasAccessibility,
                        buttonLabel: "Open Settings",
                        action: { permissions.openAccessibilitySettings() }
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            accentButton("Continue") {
                withAnimation(.easeInOut(duration: 0.25)) { page = 2 }
            }
            .opacity(permissions.allGranted ? 1 : 0.4)
            .disabled(!permissions.allGranted)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 40)
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        buttonLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(PV.Gradients.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PV.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(PV.Colors.textSecondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: 0x10B981))
            } else {
                PVTextButton(buttonLabel, action: action)
            }
        }
    }

    // MARK: - Page 2: Ready

    private var readyPage: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color(hex: 0x10B981).opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Color(hex: 0x10B981))
            }

            Text("You're all set!")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(PV.Colors.textPrimary)

            PVCard {
                VStack(spacing: 10) {
                    shortcutRow("Screenshot", ShortcutStore.shared.screenshot.displayString)
                    shortcutRow("GIF Recording", ShortcutStore.shared.gifRecording.displayString)
                    shortcutRow("Diff", ShortcutStore.shared.diff.displayString)
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 6) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(.system(size: 12))
                    .foregroundColor(PV.Colors.textSecondary)
                Text("Look for the camera icon in your menu bar")
                    .font(.system(size: 12))
                    .foregroundColor(PV.Colors.textSecondary)
            }

            Spacer()

            accentButton("Start Using PixyVibe") {
                onComplete()
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 40)
    }

    private func shortcutRow(_ label: String, _ shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(PV.Colors.textPrimary)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(PV.Gradients.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(PV.Colors.surfaceHigh, in: RoundedRectangle(cornerRadius: 5))
        }
    }

    // MARK: - Accent Button

    private func accentButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: 240)
                .padding(.vertical, 10)
                .background(PV.Gradients.accent, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Permission Alert View (post-onboarding, minimal)

struct PermissionAlertView: View {
    @StateObject private var permissions = PermissionChecker()
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PV.Colors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(PV.Colors.surfaceHigh, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(PV.Gradients.accent)

            Text("Permissions Required")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(PV.Colors.textPrimary)

            Text("Some permissions have been revoked. PixyVibe needs them to function properly.")
                .font(.system(size: 12))
                .foregroundColor(PV.Colors.textSecondary)
                .multilineTextAlignment(.center)

            PVCard {
                VStack(spacing: 12) {
                    if !permissions.hasScreenRecording {
                        alertPermissionRow(
                            title: "Screen Recording",
                            action: { permissions.requestScreenRecording() }
                        )
                    }
                    if !permissions.hasScreenRecording && !permissions.hasAccessibility {
                        Rectangle().fill(PV.Border.thinColor).frame(height: 0.5)
                    }
                    if !permissions.hasAccessibility {
                        alertPermissionRow(
                            title: "Accessibility",
                            action: { permissions.openAccessibilitySettings() }
                        )
                    }
                }
            }

            if permissions.allGranted {
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 200)
                        .padding(.vertical, 8)
                        .background(PV.Gradients.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private func alertPermissionRow(title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: 0xEF4444))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(PV.Colors.textPrimary)
            Spacer()
            PVTextButton("Open Settings", action: action)
        }
    }
}
