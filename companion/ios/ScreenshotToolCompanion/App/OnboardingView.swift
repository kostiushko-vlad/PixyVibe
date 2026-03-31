import SwiftUI

struct CompanionOnboardingView: View {
    @State private var page = 0
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            PVi.base.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch page {
                    case 0: welcomePage
                    case 1: setupPage
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Page dots
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { i in
                        Circle()
                            .fill(i == page ? AnyShapeStyle(PVi.accent) : AnyShapeStyle(PVi.border))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(PVi.accentSolid.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 40))
                    .foregroundStyle(PVi.accent)
            }

            VStack(spacing: 4) {
                Text("PixyVibe")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(PVi.textPrimary)
                Text("Companion")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PVi.accent)
            }

            Text("Connect to your Mac for wireless iPhone screenshots and live previews.")
                .font(.system(size: 15))
                .foregroundColor(PVi.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()

            accentButton("Get Started") {
                withAnimation(PVi.snappy) { page = 1 }
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 1: Setup

    private var setupPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("How It Works")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(PVi.textPrimary)

            VStack(alignment: .leading, spacing: 16) {
                setupRow("1", "camera.viewfinder", "Open PixyVibe on your Mac")
                setupRow("2", "wifi", "Make sure both devices are on the same Wi-Fi")
                setupRow("3", "link", "Your devices will connect automatically")
            }
            .padding(18)
            .background(PVi.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PVi.border, lineWidth: 0.5))

            HStack(spacing: 6) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(.system(size: 12))
                    .foregroundColor(PVi.textSecondary)
                Text("Your iPhone will appear in the PixyVibe menu bar on your Mac.")
                    .font(.system(size: 13))
                    .foregroundColor(PVi.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)

            Spacer()

            accentButton("Done") {
                onComplete()
            }
        }
        .padding(.horizontal, 32)
    }

    private func setupRow(_ number: String, _ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(PVi.accentSolid.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))

            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(PVi.accent)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(PVi.textSecondary)
        }
    }

    // MARK: - Accent Button

    private func accentButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(PVi.accent, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
}
