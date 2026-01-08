import SwiftUI

/// Parametric EQ panel with curve visualization and band controls
struct EQPanel: View {
    @ObservedObject var state: DSPState
    var sampleRate: Float = 48000
    var spectrumData: [Float] = []
    @State private var selectedBand: Int = 0
    @State private var showPhaseResponse: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // Header with phase toggle
            HStack {
                EffectHeader(
                    name: "Parametric EQ",
                    isEnabled: !state.eqBypassed,
                    onToggle: { state.toggleEQBypass() }
                )
                Spacer()

                // Phase response toggle
                Button(action: { showPhaseResponse.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 10))
                        Text("Phase")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(showPhaseResponse ? DSPTheme.accent : DSPTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(showPhaseResponse ? DSPTheme.accent.opacity(0.15) : DSPTheme.surfaceBackground)
                    )
                }
                .buttonStyle(.plain)

                // Clear solo button (shown when any band is soloed)
                if state.hasEQSolo {
                    Button(action: { state.clearAllEQSolo() }) {
                        Text("Clear Solo")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DSPTheme.meterYellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(DSPTheme.meterYellow.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // EQ Curve visualization with spectrum overlay
            EQCurveView(
                bands: state.eqBands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType) },
                bandSoloStates: state.eqBands.map { $0.solo },
                selectedBand: selectedBand,
                onBandSelected: { selectedBand = $0 },
                onBandDragged: { index, freq, gain in
                    state.eqBands[index].frequency = freq
                    state.eqBands[index].gainDb = gain
                },
                sampleRate: sampleRate,
                spectrumData: spectrumData,
                showPhaseResponse: showPhaseResponse
            )
            .frame(height: 140)

            // Band controls
            HStack(spacing: 16) {
                ForEach(0..<5) { index in
                    BandControl(
                        band: $state.eqBands[index],
                        index: index,
                        isSelected: selectedBand == index,
                        onSelect: { selectedBand = index },
                        onSoloToggle: { state.toggleEQBandSolo(at: index) }
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(16)
        .panelStyle()
    }
}

/// Individual EQ band control with solo and resonance/Q display
struct BandControl: View {
    @Binding var band: EQBandState
    let index: Int
    var isSelected: Bool
    var onSelect: () -> Void
    var onSoloToggle: () -> Void

    @State private var isDraggingGain = false
    @State private var dragStartGain: Float = 0
    @State private var dragStartY: CGFloat = 0

    private let gainSliderHeight: CGFloat = 72

    private var bandName: String {
        ["LOW", "LO-MID", "MID", "HI-MID", "HIGH"][index]
    }

    private var defaultFrequency: Float {
        [80, 250, 1000, 4000, 12000][index]
    }

    private var defaultQ: Float {
        index == 0 || index == 4 ? 0.707 : 1.0
    }

    /// Label for Q parameter based on filter type
    private var qParameterLabel: String {
        band.bandType.isResonant ? "Res" : "Q"
    }

    var body: some View {
        VStack(spacing: 6) {
            // Band type selector and label
            HStack(spacing: 4) {
                Menu {
                    Button("Low Shelf") { band.bandType = .lowShelf }
                    Button("Peak") { band.bandType = .peak }
                    Button("High Shelf") { band.bandType = .highShelf }
                    Divider()
                    Button("Low Pass") { band.bandType = .lowPass }
                    Button("High Pass") { band.bandType = .highPass }
                } label: {
                    HStack(spacing: 4) {
                        Text(bandName)
                            .font(DSPTypography.caption)
                            .foregroundColor(isSelected ? DSPTheme.eqBandColors[index] : DSPTheme.textSecondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(DSPTheme.textTertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                .onTapGesture(perform: onSelect)

                // Solo button
                Button(action: onSoloToggle) {
                    Text("S")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(band.solo ? .black : DSPTheme.textTertiary)
                        .frame(width: 16, height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(band.solo ? DSPTheme.meterYellow : DSPTheme.surfaceBackground)
                        )
                }
                .buttonStyle(.plain)
                .help("Solo this band")
            }

            // Band type indicator with resonance warning
            HStack(spacing: 2) {
                Text(bandTypeLabel)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(DSPTheme.textTertiary)

                // Show resonance indicator for LP/HP modes with high Q
                if band.bandType.isResonant && band.q > 2.0 {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 7))
                        .foregroundColor(DSPTheme.meterOrange)
                        .help("High resonance - may cause ringing")
                }
            }

            // Frequency knob with logarithmic scaling
            CompactKnob(
                value: $band.frequency,
                range: 20...20000,
                label: "Freq",
                unit: .hertz,
                scaling: .logarithmic,
                defaultValue: defaultFrequency
            )

            // Gain slider with fine adjustment
            VStack(spacing: 2) {
                GainSlider(
                    gainDb: $band.gainDb,
                    color: DSPTheme.eqBandColors[index],
                    height: gainSliderHeight
                )

                Text(String(format: "%.1f dB", band.gainDb))
                    .font(DSPTypography.mono)
                    .foregroundColor(DSPTheme.textSecondary)
            }

            // Q/Resonance knob with bandwidth display
            VStack(spacing: 2) {
                CompactKnob(
                    value: $band.q,
                    range: 0.1...10,
                    label: qParameterLabel,
                    unit: .generic,
                    defaultValue: defaultQ
                )

                // Show bandwidth in octaves for peak filters
                if !band.bandType.isResonant {
                    Text(String(format: "%.1f oct", band.bandwidthOctaves))
                        .font(.system(size: 8))
                        .foregroundColor(DSPTheme.textTertiary)
                }
            }
        }
        .padding(8)
        .background(isSelected ? DSPTheme.eqBandColors[index].opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? DSPTheme.eqBandColors[index].opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private var bandTypeLabel: String {
        switch band.bandType {
        case .lowShelf: return "LS"
        case .highShelf: return "HS"
        case .peak: return "PK"
        case .lowPass: return "LP"
        case .highPass: return "HP"
        }
    }
}

/// Vertical gain slider with Option key fine adjustment and double-click reset
struct GainSlider: View {
    @Binding var gainDb: Float
    let color: Color
    var height: CGFloat = 72

    @State private var isDragging = false
    @State private var dragStartGain: Float = 0
    @State private var dragStartY: CGFloat = 0

    private let normalSensitivity: Float = 48.0 / 72.0
    private let fineSensitivity: Float = 48.0 / 720.0

    private var normalizedGain: Float {
        (gainDb + 24) / 48
    }

    var body: some View {
        GeometryReader { geometry in
            let centerY = geometry.size.height / 2

            ZStack {
                // Track
                Rectangle()
                    .fill(DSPTheme.cardBackground)
                    .frame(width: 4)

                // Gain bar
                Rectangle()
                    .fill(color)
                    .frame(width: 4, height: abs(CGFloat(normalizedGain - 0.5)) * geometry.size.height)
                    .position(
                        x: geometry.size.width / 2,
                        y: gainDb >= 0
                            ? centerY - (CGFloat(normalizedGain - 0.5) * geometry.size.height / 2)
                            : centerY + (CGFloat(0.5 - normalizedGain) * geometry.size.height / 2)
                    )

                // Center line (0 dB)
                Rectangle()
                    .fill(DSPTheme.textTertiary)
                    .frame(width: 10, height: 1)
                    .position(x: geometry.size.width / 2, y: centerY)

                // Drag handle
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .position(
                        x: geometry.size.width / 2,
                        y: CGFloat(1 - normalizedGain) * geometry.size.height
                    )
                    .shadow(color: color.opacity(isDragging ? 0.6 : 0), radius: 4)
            }
        }
        .frame(width: 20, height: height)
        .contentShape(Rectangle())
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
            withAnimation(.easeOut(duration: 0.15)) {
                gainDb = 0
            }
        }
    }

    private func handleDrag(_ gesture: DragGesture.Value, fineMode: Bool) {
        if !isDragging {
            isDragging = true
            dragStartGain = gainDb
            dragStartY = gesture.startLocation.y
        }

        let sensitivity = fineMode ? fineSensitivity : normalSensitivity
        let deltaY = Float(dragStartY - gesture.location.y)
        let newGain = dragStartGain + deltaY * sensitivity

        gainDb = min(max(newGain, -24), 24)
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
    EQPanel(state: DSPState(), sampleRate: 48000)
        .frame(width: 600)
        .padding()
        .background(DSPTheme.background)
}
