import SwiftUI

/// Parametric EQ panel with curve visualization and band controls
struct EQPanel: View {
    @ObservedObject var state: DSPState
    @State private var selectedBand: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                EffectHeader(
                    name: "Parametric EQ",
                    isEnabled: !state.eqBypassed,
                    onToggle: { state.toggleEQBypass() }
                )
                Spacer()
            }

            // EQ Curve visualization
            EQCurveView(
                bands: state.eqBands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType) },
                selectedBand: selectedBand,
                onBandSelected: { selectedBand = $0 }
            )
            .frame(height: 140)

            // Band controls
            HStack(spacing: 16) {
                ForEach(0..<5) { index in
                    BandControl(
                        band: $state.eqBands[index],
                        index: index,
                        isSelected: selectedBand == index,
                        onSelect: { selectedBand = index }
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(16)
        .panelStyle()
    }
}

/// Individual EQ band control
struct BandControl: View {
    @Binding var band: EQBandState
    let index: Int
    var isSelected: Bool
    var onSelect: () -> Void

    private var bandName: String {
        ["LOW", "LO-MID", "MID", "HI-MID", "HIGH"][index]
    }

    var body: some View {
        VStack(spacing: 6) {
            // Band label
            Text(bandName)
                .font(DSPTypography.caption)
                .foregroundColor(isSelected ? DSPTheme.eqBandColors[index] : DSPTheme.textSecondary)
                .onTapGesture(perform: onSelect)

            // Frequency knob
            CompactKnob(
                value: $band.frequency,
                range: 20...20000,
                label: "Freq",
                unit: .hertz
            )

            // Gain slider
            VStack(spacing: 2) {
                // Mini gain bar
                GeometryReader { geometry in
                    let normalizedGain = (band.gainDb + 24) / 48
                    let centerY = geometry.size.height / 2

                    ZStack {
                        // Track
                        Rectangle()
                            .fill(DSPTheme.cardBackground)
                            .frame(width: 4)

                        // Gain bar
                        Rectangle()
                            .fill(DSPTheme.eqBandColors[index])
                            .frame(width: 4, height: abs(CGFloat(normalizedGain - 0.5)) * geometry.size.height)
                            .position(
                                x: geometry.size.width / 2,
                                y: band.gainDb >= 0 ? centerY - (CGFloat(normalizedGain - 0.5) * geometry.size.height / 2) : centerY + (CGFloat(0.5 - normalizedGain) * geometry.size.height / 2)
                            )

                        // Center line
                        Rectangle()
                            .fill(DSPTheme.textTertiary)
                            .frame(width: 8, height: 1)
                            .position(x: geometry.size.width / 2, y: centerY)
                    }
                }
                .frame(width: 20, height: 50)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let normalized = 1 - Float(gesture.location.y / 50)
                            band.gainDb = (normalized * 48) - 24
                        }
                )

                Text(String(format: "%.1f dB", band.gainDb))
                    .font(DSPTypography.mono)
                    .foregroundColor(DSPTheme.textSecondary)
            }

            // Q knob
            CompactKnob(
                value: $band.q,
                range: 0.1...10,
                label: "Q",
                unit: .generic
            )
        }
        .padding(8)
        .background(isSelected ? DSPTheme.eqBandColors[index].opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? DSPTheme.eqBandColors[index].opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}

/// Effect header with bypass toggle
struct EffectHeader: View {
    let name: String
    var isEnabled: Bool
    var onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator with glow
            Circle()
                .fill(isEnabled ? DSPTheme.effectEnabled : DSPTheme.effectBypassed)
                .frame(width: 6, height: 6)
                .shadow(color: isEnabled ? DSPTheme.effectEnabled.opacity(0.6) : Color.clear, radius: 4)

            Text(name)
                .font(DSPTypography.title)
                .foregroundColor(isEnabled ? DSPTheme.textPrimary : DSPTheme.textTertiary)

            Spacer()

            Button(action: onToggle) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isEnabled ? DSPTheme.effectEnabled : DSPTheme.textDisabled)
                        .frame(width: 4, height: 4)
                    Text(isEnabled ? "ON" : "BYPASS")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                .foregroundColor(isEnabled ? DSPTheme.effectEnabled : DSPTheme.textDisabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isEnabled ? DSPTheme.effectEnabled.opacity(0.15) : DSPTheme.surfaceBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isEnabled ? DSPTheme.effectEnabled.opacity(0.3) : DSPTheme.borderColor.opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
}

#Preview {
    EQPanel(state: DSPState())
        .frame(width: 600)
        .padding()
        .background(DSPTheme.background)
}
