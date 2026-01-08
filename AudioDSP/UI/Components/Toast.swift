import SwiftUI

/// Toast notification for visual feedback
struct Toast: Equatable {
    let id: UUID
    let message: String
    let icon: String
    let isEnabled: Bool?  // nil for non-toggle actions

    init(message: String, icon: String, isEnabled: Bool? = nil) {
        self.id = UUID()
        self.message = message
        self.icon = icon
        self.isEnabled = isEnabled
    }

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

/// Observable toast manager
@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentToast: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ toast: Toast) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentToast = toast
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)  // 1.2 seconds
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.currentToast = nil
                    }
                }
            }
        }
    }

    func show(effect: String, enabled: Bool) {
        let icon = enabled ? "checkmark.circle.fill" : "slash.circle.fill"
        let message = "\(effect) \(enabled ? "ON" : "Bypassed")"
        show(Toast(message: message, icon: icon, isEnabled: enabled))
    }

    func show(action: String, icon: String = "checkmark.circle.fill") {
        show(Toast(message: action, icon: icon, isEnabled: nil))
    }
}

/// Toast overlay view
struct ToastOverlay: View {
    @ObservedObject var manager: ToastManager = .shared

    var body: some View {
        VStack {
            Spacer()

            if let toast = manager.currentToast {
                ToastView(toast: toast)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .move(edge: .bottom))
                    ))
            }
        }
        .padding(.bottom, 40)
        .allowsHitTesting(false)
    }
}

/// Individual toast view
struct ToastView: View {
    let toast: Toast

    private var iconColor: Color {
        if let enabled = toast.isEnabled {
            return enabled ? DSPTheme.meterGreen : DSPTheme.meterOrange
        }
        return DSPTheme.accent
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .shadow(color: iconColor.opacity(0.5), radius: 4)

            Text(toast.message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(iconColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }
}

#Preview {
    ZStack {
        Color.black
        ToastView(toast: Toast(message: "EQ ON", icon: "checkmark.circle.fill", isEnabled: true))
    }
}
