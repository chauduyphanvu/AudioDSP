import AppKit
import SwiftUI

/// Pro audio theme colors and styles
enum DSPTheme {
    // MARK: - Background Colors

    static let background = Color(hex: "#0D0D0F")
    static let panelBackground = Color(hex: "#1A1A1E")
    static let cardBackground = Color(hex: "#232328")
    static let surfaceBackground = Color(hex: "#2A2A30")

    // MARK: - Accent Colors

    static let accent = Color(hex: "#3B82F6")
    static let accentSecondary = Color(hex: "#6366F1")
    static let highlight = Color(hex: "#60A5FA")

    // MARK: - Meter Colors

    static let meterGreen = Color(hex: "#22C55E")
    static let meterYellow = Color(hex: "#EAB308")
    static let meterOrange = Color(hex: "#F97316")
    static let meterRed = Color(hex: "#EF4444")

    // MARK: - EQ Band Colors

    static let eqBand1 = Color(hex: "#F87171")  // Low Shelf - Coral
    static let eqBand2 = Color(hex: "#FBBF24")  // Low Mid - Amber
    static let eqBand3 = Color(hex: "#34D399")  // Mid - Green
    static let eqBand4 = Color(hex: "#38BDF8")  // High Mid - Sky
    static let eqBand5 = Color(hex: "#A78BFA")  // High Shelf - Lavender

    static var eqBandColors: [Color] {
        [eqBand1, eqBand2, eqBand3, eqBand4, eqBand5]
    }

    // MARK: - Text Colors

    static let textPrimary = Color(hex: "#F4F4F5")
    static let textSecondary = Color(hex: "#A1A1AA")
    static let textTertiary = Color(hex: "#71717A")
    static let textDisabled = Color(hex: "#52525B")

    // MARK: - Knob & Control Colors

    static let knobFace = LinearGradient(
        colors: [Color(hex: "#404045"), Color(hex: "#2A2A2E")],
        startPoint: .top,
        endPoint: .bottom
    )

    static let knobRing = LinearGradient(
        colors: [Color(hex: "#3A3A40"), Color(hex: "#1F1F23")],
        startPoint: .top,
        endPoint: .bottom
    )

    static let knobIndicator = Color(hex: "#60A5FA")

    static let faderTrack = Color(hex: "#1A1A1E")
    static let faderFill = LinearGradient(
        colors: [accent, accentSecondary],
        startPoint: .bottom,
        endPoint: .top
    )

    // MARK: - Border & Shadow

    static let borderColor = Color(hex: "#3F3F46")
    static let borderColorLight = Color(hex: "#52525B")

    static let shadowColor = Color.black.opacity(0.5)
    static let glowColor = accent.opacity(0.3)

    // MARK: - Effect States

    static let effectEnabled = Color(hex: "#22C55E")
    static let effectBypassed = Color(hex: "#52525B")
    static let effectSelected = accent

    // MARK: - Spectrum Analyzer

    static let spectrumGradient = LinearGradient(
        colors: [
            Color(hex: "#3B82F6").opacity(0.1),
            Color(hex: "#3B82F6").opacity(0.5),
            Color(hex: "#60A5FA").opacity(0.8),
        ],
        startPoint: .bottom,
        endPoint: .top
    )

    static let spectrumLine = Color(hex: "#60A5FA")
    static let spectrumGrid = Color(hex: "#27272A")
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

extension View {
    func panelStyle() -> some View {
        self
            .background(DSPTheme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DSPTheme.borderColor, lineWidth: 1)
            )
    }

    func cardStyle() -> some View {
        self
            .background(DSPTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DSPTheme.borderColor, lineWidth: 0.5)
            )
    }

    func glowEffect(color: Color = DSPTheme.accent, radius: CGFloat = 8) -> some View {
        self.shadow(color: color.opacity(0.5), radius: radius)
    }

    /// Scroll wheel handler for precise control adjustments
    func onScrollWheel(_ action: @escaping (_ delta: CGFloat, _ modifiers: NSEvent.ModifierFlags) -> Void) -> some View {
        self.background(ScrollWheelHandler(action: action))
    }
}

/// NSViewRepresentable for capturing scroll wheel events
struct ScrollWheelHandler: NSViewRepresentable {
    let action: (_ delta: CGFloat, _ modifiers: NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: ScrollWheelView, context: Context) {
        nsView.action = action
    }

    class ScrollWheelView: NSView {
        var action: ((_ delta: CGFloat, _ modifiers: NSEvent.ModifierFlags) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            // Use deltaY for vertical scrolling (most common)
            let delta = event.deltaY
            if abs(delta) > 0.01 {
                action?(delta, event.modifierFlags)
            }
        }
    }
}

// MARK: - Keyboard Shortcut Handlers

struct KeyboardShortcutHandlersModifier: ViewModifier {
    let state: DSPState
    let audioEngine: AudioEngine
    let presetManager: PresetManager

    func body(content: Content) -> some View {
        content
            // Edit commands
            .onReceive(NotificationCenter.default.publisher(for: .undo)) { _ in
                state.undo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .redo)) { _ in
                state.redo()
            }
            // Audio commands
            .onReceive(NotificationCenter.default.publisher(for: .startEngine)) { _ in
                Task { await audioEngine.start() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .stopEngine)) { _ in
                audioEngine.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleAB)) { _ in
                state.switchABSlot()
            }
            .onReceive(NotificationCenter.default.publisher(for: .bypassAll)) { _ in
                state.toggleBypassAll()
            }
            // Effect bypass commands (split for type-checker)
            .effectBypassHandlers(state: state)
            // Preset commands
            .onReceive(NotificationCenter.default.publisher(for: .previousPreset)) { _ in
                presetManager.loadPrevious(into: state)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextPreset)) { _ in
                presetManager.loadNext(into: state)
            }
    }
}

struct EffectBypassHandlersModifier: ViewModifier {
    let state: DSPState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleEQ)) { _ in
                state.toggleEQBypass()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleCompressor)) { _ in
                state.toggleCompressorBypass()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleLimiter)) { _ in
                state.toggleLimiterBypass()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleReverb)) { _ in
                state.toggleReverbBypass()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleDelay)) { _ in
                state.toggleDelayBypass()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleStereoWidener)) { _ in
                state.toggleStereoWidenerBypass()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleBassEnhancer)) { _ in
                state.toggleBassEnhancerBypass()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleVocalClarity)) { _ in
                state.toggleVocalClarityBypass()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetAll)) { _ in
                state.resetAllParameters()
            }
    }
}

extension View {
    func keyboardShortcutHandlers(state: DSPState, audioEngine: AudioEngine, presetManager: PresetManager) -> some View {
        modifier(KeyboardShortcutHandlersModifier(state: state, audioEngine: audioEngine, presetManager: presetManager))
    }

    func effectBypassHandlers(state: DSPState) -> some View {
        modifier(EffectBypassHandlersModifier(state: state))
    }
}

// MARK: - Typography

enum DSPTypography {
    static let title = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let heading = Font.system(size: 12, weight: .medium, design: .rounded)
    static let body = Font.system(size: 11, weight: .regular, design: .default)
    static let caption = Font.system(size: 10, weight: .regular, design: .default)
    static let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let parameterValue = Font.system(size: 11, weight: .medium, design: .monospaced)
}
