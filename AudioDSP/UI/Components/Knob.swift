import SwiftUI

/// Skeuomorphic rotary knob control
struct Knob: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let label: String
    var unit: ParameterUnit = .generic
    var size: CGFloat = 56

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartValue: Float = 0
    @State private var dragStartLocation: CGPoint = .zero

    private let sensitivity: Float = 0.005

    private var normalizedValue: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var rotation: Angle {
        let angle = -135.0 + Double(normalizedValue) * 270.0
        return .degrees(angle)
    }

    private var isActive: Bool {
        isDragging || isHovered
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
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            dragStartValue = value
                            dragStartLocation = gesture.startLocation
                        }

                        let delta = Float(dragStartLocation.y - gesture.location.y) * sensitivity
                        let rangeSize = range.upperBound - range.lowerBound
                        let newValue = dragStartValue + delta * rangeSize

                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )

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

    var body: some View {
        Knob(value: $value, range: range, label: label, unit: unit, size: 40)
    }
}

#Preview {
    HStack(spacing: 32) {
        Knob(
            value: .constant(0.5),
            range: 0...1,
            label: "Mix",
            unit: .percent
        )

        Knob(
            value: .constant(-6.0),
            range: -24...24,
            label: "Gain",
            unit: .decibels
        )

        CompactKnob(
            value: .constant(1000.0),
            range: 20...20000,
            label: "Freq",
            unit: .hertz
        )
    }
    .padding(40)
    .background(DSPTheme.background)
}
