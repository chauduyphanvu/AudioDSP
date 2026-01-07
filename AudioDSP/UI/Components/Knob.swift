import SwiftUI

/// Scaling mode for knob values
enum KnobScaling {
    case linear
    case logarithmic  // For frequency parameters (20Hz-20kHz)
}

/// Skeuomorphic rotary knob control
struct Knob: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let label: String
    var unit: ParameterUnit = .generic
    var size: CGFloat = 56
    var scaling: KnobScaling = .linear
    var defaultValue: Float? = nil  // For double-click reset

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartNormalized: Float = 0
    @State private var dragStartLocation: CGPoint = .zero
    @State private var modifierPressed = false

    private let sensitivity: Float = 0.005
    private let fineSensitivity: Float = 0.001  // For Option key fine adjustment

    /// Convert actual value to normalized (0-1) based on scaling mode
    private var normalizedValue: Float {
        switch scaling {
        case .linear:
            return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        case .logarithmic:
            // Log scale: normalized = log(value/min) / log(max/min)
            let logMin = log(range.lowerBound)
            let logMax = log(range.upperBound)
            let logVal = log(max(value, range.lowerBound))
            return (logVal - logMin) / (logMax - logMin)
        }
    }

    /// Convert normalized (0-1) to actual value based on scaling mode
    private func denormalize(_ normalized: Float) -> Float {
        let clamped = min(max(normalized, 0), 1)
        switch scaling {
        case .linear:
            return range.lowerBound + clamped * (range.upperBound - range.lowerBound)
        case .logarithmic:
            // Log scale: value = min * (max/min)^normalized
            return range.lowerBound * powf(range.upperBound / range.lowerBound, clamped)
        }
    }

    private var rotation: Angle {
        let angle = -135.0 + Double(normalizedValue) * 270.0
        return .degrees(angle)
    }

    private var isActive: Bool {
        isDragging || isHovered
    }

    private func handleDrag(_ gesture: DragGesture.Value, fineMode: Bool) {
        if !isDragging {
            isDragging = true
            dragStartNormalized = normalizedValue
            dragStartLocation = gesture.startLocation
        }

        let sens = fineMode ? fineSensitivity : sensitivity
        let delta = Float(dragStartLocation.y - gesture.location.y) * sens
        let newNormalized = dragStartNormalized + delta

        value = denormalize(newNormalized)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Outer ring with track
                Circle()
                    .fill(DSPTheme.knobRing)
                    .frame(width: size + 8, height: size + 8)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                // Value arc
                Circle()
                    .trim(from: 0, to: CGFloat(normalizedValue) * 0.75)
                    .stroke(
                        DSPTheme.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                    .frame(width: size + 4, height: size + 4)
                    .opacity(isActive ? 1.0 : 0.7)
                    .shadow(color: isActive ? DSPTheme.accent.opacity(0.4) : Color.clear, radius: 6)

                // Knob face
                Circle()
                    .fill(DSPTheme.knobFace)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(isActive ? 0.15 : 0.1), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)

                // Pointer indicator
                VStack {
                    Capsule()
                        .fill(isActive ? DSPTheme.highlight : DSPTheme.knobIndicator)
                        .frame(width: 3, height: size * 0.25)
                        .shadow(color: DSPTheme.accent.opacity(isActive ? 0.6 : 0), radius: 4)
                    Spacer()
                }
                .frame(height: size * 0.5)
                .rotationEffect(rotation)
            }
            .frame(width: size + 8, height: size + 8)
            .scaleEffect(isDragging ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .modifiers(.option)
                    .onChanged { gesture in
                        handleDrag(gesture, fineMode: true)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        handleDrag(gesture, fineMode: false)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onTapGesture(count: 2) {
                // Double-click to reset to default
                if let defaultVal = defaultValue {
                    withAnimation(.easeOut(duration: 0.15)) {
                        value = defaultVal
                    }
                }
            }
            .onScrollWheel { delta, modifiers in
                let sens: Float = modifiers.contains(.option) ? 0.002 : 0.01
                let newNormalized = normalizedValue + Float(delta) * sens
                value = denormalize(newNormalized)
            }
            .help("Drag or scroll to adjust. Hold ⌥ Option for fine control." + (defaultValue != nil ? " Double-click to reset." : ""))

            // Label
            Text(label)
                .font(DSPTypography.caption)
                .foregroundColor(isActive ? DSPTheme.textSecondary : DSPTheme.textTertiary)

            // Value display
            Text(unit.format(value))
                .font(DSPTypography.parameterValue)
                .foregroundColor(isActive ? DSPTheme.highlight : DSPTheme.textPrimary)
                .frame(minWidth: 50)
        }
    }
}

/// Compact knob for dense layouts
struct CompactKnob: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let label: String
    var unit: ParameterUnit = .generic
    var scaling: KnobScaling = .linear
    var defaultValue: Float? = nil

    var body: some View {
        Knob(value: $value, range: range, label: label, unit: unit, size: 40, scaling: scaling, defaultValue: defaultValue)
    }
}

#Preview {
    HStack(spacing: 32) {
        Knob(
            value: .constant(0.5),
            range: 0...1,
            label: "Mix",
            unit: .percent,
            defaultValue: 0.5
        )

        Knob(
            value: .constant(-6.0),
            range: -24...24,
            label: "Gain",
            unit: .decibels,
            defaultValue: 0
        )

        CompactKnob(
            value: .constant(1000.0),
            range: 20...20000,
            label: "Freq",
            unit: .hertz,
            scaling: .logarithmic,
            defaultValue: 1000
        )
    }
    .padding(40)
    .background(DSPTheme.background)
}
