import SwiftUI
import ReplayKit

/// Singleton that can trigger the broadcast picker from anywhere in the app.
/// MUST call `initialize()` from the main thread at app startup.
class BroadcastManager {
    static let shared = BroadcastManager()

    private var picker: RPSystemBroadcastPickerView?

    private init() {}

    /// Call this once from the main thread (e.g., in app's init or onAppear).
    func initialize() {
        assert(Thread.isMainThread, "BroadcastManager.initialize() must be called on main thread")
        guard picker == nil else { return }
        let p = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        p.preferredExtension = "com.pixyvibe.companion.broadcast"
        p.showsMicrophoneButton = false
        picker = p
    }

    /// Programmatically trigger the system broadcast picker.
    func triggerBroadcast() {
        DispatchQueue.main.async { [weak self] in
            guard let picker = self?.picker else {
                print("BroadcastManager not initialized")
                return
            }
            for subview in picker.subviews {
                if let button = subview as? UIButton {
                    button.sendActions(for: .touchUpInside)
                    return
                }
            }
        }
    }
}

/// SwiftUI wrapper that shows a visible "Start Broadcast" button.
struct BroadcastSetupUI: UIViewRepresentable {
    func makeUIView(context: Context) -> BroadcastButtonView {
        return BroadcastButtonView()
    }

    func updateUIView(_ uiView: BroadcastButtonView, context: Context) {}
}

class BroadcastButtonView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .systemRed
        layer.cornerRadius = 12

        let icon = UIImageView(image: UIImage(systemName: "record.circle"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        let label = UILabel()
        label.text = "Start Broadcast"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.trailingAnchor.constraint(equalTo: label.leadingAnchor, constant: -8),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            label.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 15),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    @objc private func tapped() {
        BroadcastManager.shared.triggerBroadcast()
    }
}
