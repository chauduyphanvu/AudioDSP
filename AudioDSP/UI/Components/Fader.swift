import SwiftUI

/// Vertical fader control with LED meter
struct Fader: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let label: String
    var unit: ParameterUnit = .decibels
    var height: CGFloat = 150
    var showMeter: Bool = false
    var meterLevel: Float = 0

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartValue: Float = 0
    @State private var dragStartY: CGFloat = 0

    private let normalSensitivity: Float = 1.0
    private let fineSensitivity: Float = 0.1  // 10x finer control with Option key

    private var normalizedValue: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var valueRange: Float {
        range.upperBound - range.lowerBound
    }

    private func handleDrag(_ gesture: DragGesture.Value, fineMode: Bool) {
        if !isDragging {
            isDragging = true
            dragStartValue = value
            dragStartY = gesture.startLocation.y
        }

        let deltaY = Float(dragStartY - gesture.location.y)
        let sensitivity = (fineMode ? fineSensitivity : normalSensitivity) * valueRange / Float(height)
        let newValue = dragStartValue + deltaY * sensitivity

        value = min(max(newValue, range.lowerBound), range.upperBound)
    }

    private var isActive: Bool {
        isDragging || isHovered
    }

    var body: some View {
        VStack(spacing: 8) {
            // Value display
            Text(unit.format(value))
                .font(DSPTypography.parameterValue)
                .foregroundColor(isActive ? DSPTheme.highlight : DSPTheme.textPrimary)
                .frame(minWidth: 45)

            HStack(spacing: 6) {
                // Meter (optional)
                if showMeter {
                    MeterBar(level: meterLevel, height: height - 20)
                        .frame(width: 6)
                }

                // Fader track
                ZStack(alignment: .bottom) {
                    // Track background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DSPTheme.faderTrack)
                        .frame(width: 8, height: height)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(isActive ? DSPTheme.accent.opacity(0.5) : DSPTheme.borderColor, lineWidth: 1)
                        )

                    // Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DSPTheme.faderFill)
                        .frame(width: 6, height: max(4, CGFloat(normalizedValue) * height))
                        .padding(.bottom, 1)
                        .shadow(color: isActive ? DSPTheme.accent.opacity(0.3) : Color.clear, radius: 4)

                    // Fader cap
                    FaderCap(isDragging: isDragging, isHovered: isHovered)
                        .offset(y: -CGFloat(normalizedValue) * height + height / 2)
                }
                .frame(width: 32, height: height)
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
                        .onEnded { _ in isDragging = false }
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            handleDrag(gesture, fineMode: false)
                        }
                        .onEnded { _ in isDragging = false }
                )
                .onTapGesture(count: 2) {
                    // Double-click to reset to 0 (or center of range if 0 is not in range)
                    let defaultValue: Float = range.contains(0) ? 0 : (range.lowerBound + range.upperBound) / 2
                    withAnimation(.easeOut(duration: 0.15)) {
                        value = defaultValue
                    }
                }
                .onScrollWheel { delta, modifiers in
                    let sens: Float = modifiers.contains(.option) ? 0.002 : 0.01
                    let normalizedDelta = Float(delta) * sens
                    let newValue = value + normalizedDelta * valueRange
                    value = min(max(newValue, range.lowerBound), range.upperBound)
                }
                .help("Drag or scroll to adjust. Hold ⌥ Option for fine control. Double-click to reset.")
            }

            // Label
            Text(label)
                .font(DSPTypography.caption)
                .foregroundColor(isActive ? DSPTheme.textSecondary : DSPTheme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)")
        .accessibilityValue(unit.format(value))
        .accessibilityHint("Swipe up or down to adjust")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) * 0.05
            switch direction {
            case .increment:
                value = min(value + step, range.upperBound)
            case .decrement:
                value = max(value - step, range.lowerBound)
            @unknown default:
                break
            }
        }
    }
}

/// Fader cap/handle
struct FaderCap: View {
    var isDragging: Bool = false
    var isHovered: Bool = false

    private var isActive: Bool {
        isDragging || isHovered
    }

    private var capGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(
                    light: Color(hex: isActive ? "#BEBEC3" : "#AEAEB3"),
                    dark: Color(hex: isActive ? "#6A6A70" : "#5A5A60")
                ),
                Color(
                    light: Color(hex: isActive ? "#9E9EA3" : "#8E8E93"),
                    dark: Color(hex: isActive ? "#4A4A50" : "#3A3A40")
                )
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(capGradient)
            .frame(width: 28, height: 18)
            .overlay(
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(Color(light: .black, dark: .white).opacity(isActive ? 0.2 : 0.15))
                            .frame(width: 16, height: 1)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(light: .black, dark: .white).opacity(isActive ? 0.25 : 0.2),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: DSPTheme.shadowColor, radius: 2, y: 1)
            .shadow(color: isActive ? DSPTheme.accent.opacity(0.4) : .clear, radius: 6)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isDragging)
    }
}

/// Simple meter bar for fader
struct MeterBar: View {
    var level: Float  // 0-1 linear
    var height: CGFloat

    private var normalizedLevel: CGFloat {
        CGFloat(min(max(level, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.5))

                // Meter segments
                VStack(spacing: 1) {
                    ForEach(0..<20, id: \.self) { index in
                        let segmentPosition = Float(19 - index) / 20.0
                        let isLit = level >= segmentPosition

                        RoundedRectangle(cornerRadius: 1)
                            .fill(segmentColor(for: index, isLit: isLit))
                            .frame(height: (geometry.size.height - 19) / 20)
                    }
                }
                .padding(1)
            }
        }
        .frame(width: 6, height: height)
    }

    private func segmentColor(for index: Int, isLit: Bool) -> Color {
        if !isLit {
            return Color.gray.opacity(0.2)
        }

        if index < 2 {
            return DSPTheme.meterRed
        } else if index < 4 {
            return DSPTheme.meterOrange
        } else if index < 8 {
            return DSPTheme.meterYellow
        } else {
            return DSPTheme.meterGreen
        }
    }
}

#Preview {
    HStack(spacing: 32) {
        Fader(
            value: .constant(-6.0),
            range: -60...0,
            label: "Input",
            showMeter: true,
            meterLevel: 0.7
        )

        Fader(
            value: .constant(0.0),
            range: -24...24,
            label: "Output"
        )
    }
    .padding(40)
    .background(DSPTheme.background)
}
