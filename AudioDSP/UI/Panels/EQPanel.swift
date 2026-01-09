import SwiftUI

/// Parametric EQ panel with curve visualization and band controls
struct EQPanel: View {
    @ObservedObject var state: DSPState
    var sampleRate: Float = 48000
    var spectrumData: [Float] = []
    @State private var selectedBand: Int = 0
    @State private var showPhaseResponse: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            // Header with mode and phase toggle
            HStack(spacing: 12) {
                EffectHeader(
                    name: "Parametric EQ",
                    isEnabled: !state.eqBypassed,
                    onToggle: { state.toggleEQBypass() }
                )

                Spacer()

                // Processing controls group
                HStack(spacing: 6) {
                    // Processing mode picker (Linear vs Minimum Phase)
                    Menu {
                        ForEach(EQProcessingMode.allCases, id: \.self) { mode in
                            Button(action: { state.eqProcessingMode = mode }) {
                                HStack {
                                    Text(mode.displayName)
                                    if state.eqProcessingMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: state.eqProcessingMode == .linearPhase ? "waveform.path" : "waveform")
                                .font(.system(size: 9, weight: .medium))
                            Text(state.eqProcessingMode == .linearPhase ? "Linear" : "Min φ")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(state.eqProcessingMode == .linearPhase ? DSPTheme.accent : DSPTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(state.eqProcessingMode == .linearPhase ? DSPTheme.accent.opacity(0.15) : Color.clear)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .help(state.eqProcessingMode.description)

                    // Phase response toggle
                    HeaderButton(
                        icon: "waveform.path",
                        label: "Phase",
                        isActive: showPhaseResponse,
                        color: DSPTheme.accent,
                        action: { showPhaseResponse.toggle() }
                    )
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DSPTheme.cardBackground.opacity(0.5))
                )

                // Analyzer controls group
                HStack(spacing: 6) {
                    // Analyzer hold/freeze button
                    HeaderButton(
                        icon: state.analyzerHoldEnabled ? "pause.circle.fill" : "pause.circle",
                        label: "Hold",
                        isActive: state.analyzerHoldEnabled,
                        color: DSPTheme.meterOrange,
                        action: { state.toggleAnalyzerHold() }
                    )
                    .help("Hold/freeze spectrum for analysis")

                    // Clear solo button (shown when any band is soloed)
                    if state.hasEQSolo {
                        HeaderButton(
                            icon: "speaker.slash",
                            label: "Clear",
                            isActive: true,
                            color: DSPTheme.meterYellow,
                            action: { state.clearAllEQSolo() }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DSPTheme.cardBackground.opacity(0.5))
                )

                // Saturation controls group
                HStack(spacing: 6) {
                    // Saturation mode picker
                    Menu {
                        ForEach(SaturationMode.allCases, id: \.self) { mode in
                            Button(action: { state.eqSaturationMode = mode }) {
                                HStack {
                                    Text(mode.displayName)
                                    if state.eqSaturationMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "flame")
                                .font(.system(size: 9, weight: .medium))
                            Text(state.eqSaturationMode.displayName)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(state.eqSaturationMode != .clean ? DSPTheme.meterOrange : DSPTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(state.eqSaturationMode != .clean ? DSPTheme.meterOrange.opacity(0.15) : Color.clear)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .help(state.eqSaturationMode.description)

                    // Drive control (only shown when saturation is active)
                    if state.eqSaturationMode != .clean {
                        DriveControl(value: $state.eqSaturationDrive)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(state.eqSaturationMode != .clean ? DSPTheme.meterOrange.opacity(0.1) : DSPTheme.cardBackground.opacity(0.5))
                )
            }

            // EQ Curve visualization with spectrum overlay
            // Uses held spectrum when analyzer hold is enabled
            EQCurveView(
                bands: state.eqBands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType) },
                bandSoloStates: state.eqBands.map { $0.solo },
                selectedBand: selectedBand,
                onBandSelected: { selectedBand = $0 },
                onBandDragStarted: { _ in
                    // Register undo at drag start to capture pre-drag state
                    state.registerUndoForEQBandChange()
                },
                onBandDragged: { index, freq, gain in
                    state.eqBands[index].frequency = freq
                    state.eqBands[index].gainDb = gain
                },
                sampleRate: sampleRate,
                spectrumData: state.analyzerHoldEnabled ? state.heldSpectrumData : spectrumData,
                showPhaseResponse: showPhaseResponse
            )
            .frame(height: 160)

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

/// Individual EQ band control with solo, enable, and resonance/Q display
struct BandControl: View {
    @Binding var band: EQBandState
    let index: Int
    var isSelected: Bool
    var onSelect: () -> Void
    var onSoloToggle: () -> Void

    @State private var isHovered = false

    private let gainSliderHeight: CGFloat = 80

    private var bandName: String {
        ["LOW", "LO-MID", "MID", "HI-MID", "HIGH"][index]
    }

    private var bandColor: Color {
        DSPTheme.eqBandColors[index]
    }

    private var defaultFrequency: Float {
        [80, 250, 1000, 4000, 12000][index]
    }

    private var defaultQ: Float {
        index == 0 || index == 4 ? 0.707 : 1.0
    }

    private var qParameterLabel: String {
        band.bandType.isResonant ? "Res" : "Q"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header row with band number, name dropdown, and solo
            HStack(spacing: 6) {
                // Band number indicator
                ZStack {
                    Circle()
                        .fill(band.enabled ? bandColor : DSPTheme.textDisabled)
                        .frame(width: 20, height: 20)
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(band.enabled ? .white : DSPTheme.textTertiary)
                }
                .onTapGesture {
                    band.enabled.toggle()
                }
                .help(band.enabled ? "Click to disable band" : "Click to enable band")

                // Band name and type selector (inline)
                Menu {
                    Section("Filter Type") {
                        Button("Low Shelf") { changeBandType(to: .lowShelf) }
                        Button("Peak") { changeBandType(to: .peak) }
                        Button("High Shelf") { changeBandType(to: .highShelf) }
                        Divider()
                        Button("Low Pass") { changeBandType(to: .lowPass) }
                        Button("High Pass") { changeBandType(to: .highPass) }
                    }

                    if band.slopeApplicable {
                        Section("Slope") {
                            ForEach(FilterSlope.allCases, id: \.self) { slope in
                                Button(action: { band.slope = slope }) {
                                    HStack {
                                        Text(slope.displayName)
                                        if band.slope == slope {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Section("Stereo Mode") {
                        ForEach(MSMode.allCases, id: \.self) { mode in
                            Button(action: { band.msMode = mode }) {
                                HStack {
                                    Text(mode.displayName)
                                    if band.msMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Section("Topology") {
                        ForEach(FilterTopology.allCases, id: \.self) { topo in
                            Button(action: { band.topology = topo }) {
                                HStack {
                                    Text(topo.displayName)
                                    if band.topology == topo {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()
                    Button(action: { band.dynamicsEnabled.toggle() }) {
                        HStack {
                            Image(systemName: "waveform.path.badge.minus")
                            Text("Dynamic EQ")
                            if band.dynamicsEnabled {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(bandName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(band.enabled ? (isSelected ? bandColor : DSPTheme.textPrimary) : DSPTheme.textDisabled)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(DSPTheme.textTertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                .onTapGesture(perform: onSelect)

                Spacer()

                // Solo button
                Button(action: onSoloToggle) {
                    Text("S")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(band.solo ? .black : DSPTheme.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(band.solo ? DSPTheme.meterYellow : DSPTheme.surfaceBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(band.solo ? DSPTheme.meterYellow : DSPTheme.borderColor.opacity(0.5), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help("Solo this band")
            }

            // Filter type indicator
            Text(bandTypeLabel)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(DSPTheme.textTertiary)

            // Feature badges row
            if hasFeatureBadges {
                HStack(spacing: 4) {
                    if band.slopeApplicable && band.slope != .slope12dB {
                        FeatureBadge(text: band.slope.displayName.replacingOccurrences(of: " dB/oct", with: ""), color: DSPTheme.accent)
                    }
                    if band.msMode != .stereo {
                        FeatureBadge(text: band.msMode.displayName, color: DSPTheme.meterGreen)
                    }
                    if band.topology == .svf {
                        FeatureBadge(text: "SVF", color: DSPTheme.accent)
                    }
                    if band.dynamicsEnabled {
                        FeatureBadge(icon: "waveform.path.badge.minus", color: DSPTheme.meterYellow)
                    }
                    if band.bandType.isResonant && band.q > 2.0 {
                        FeatureBadge(icon: "exclamationmark.triangle.fill", color: DSPTheme.meterOrange)
                            .help("High resonance - may cause ringing")
                    }
                }
            }

            // Main controls section
            VStack(spacing: 10) {
                // Frequency knob
                CompactKnob(
                    value: $band.frequency,
                    range: 20...20000,
                    label: "Freq",
                    unit: .hertz,
                    scaling: .logarithmic,
                    defaultValue: defaultFrequency
                )

                // Gain slider with value display
                VStack(spacing: 4) {
                    GainSlider(
                        gainDb: $band.gainDb,
                        color: bandColor,
                        height: gainSliderHeight
                    )

                    // Gain value with color coding
                    Text(String(format: "%+.1f", band.gainDb))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(
                            abs(band.gainDb) < 0.5 ? DSPTheme.textTertiary :
                                (band.gainDb > 0 ? DSPTheme.meterGreen : DSPTheme.meterOrange)
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DSPTheme.cardBackground)
                        )
                }

                // Q/Resonance knob with bandwidth display
                VStack(spacing: 2) {
                    CompactKnob(
                        value: $band.q,
                        range: band.bandType.qRange,
                        label: qParameterLabel,
                        unit: .generic,
                        defaultValue: band.bandType.defaultQ
                    )

                    if !band.bandType.isResonant {
                        Text(String(format: "%.1f oct", band.bandwidthOctaves))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(DSPTheme.textTertiary)
                    }
                }
            }

            // Dynamics controls (expanded when enabled and selected)
            if band.dynamicsEnabled && isSelected {
                VStack(spacing: 6) {
                    Rectangle()
                        .fill(DSPTheme.borderColor.opacity(0.5))
                        .frame(height: 1)
                        .padding(.horizontal, 4)

                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.badge.minus")
                            .font(.system(size: 8))
                        Text("Dynamics")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(DSPTheme.meterYellow)

                    HStack(spacing: 12) {
                        DynamicsControl(
                            label: "Thresh",
                            value: $band.dynamicsThreshold,
                            range: -60...0,
                            format: "%.0f dB"
                        )

                        DynamicsControl(
                            label: "Ratio",
                            value: $band.dynamicsRatio,
                            range: 1...10,
                            format: "%.1f:1"
                        )
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? bandColor.opacity(0.08) : DSPTheme.cardBackground.opacity(isHovered ? 0.8 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? bandColor.opacity(0.6) : DSPTheme.borderColor.opacity(isHovered ? 0.6 : 0.3),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .opacity(band.enabled ? 1.0 : 0.6)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }

    private var hasFeatureBadges: Bool {
        (band.slopeApplicable && band.slope != .slope12dB) ||
        band.msMode != .stereo ||
        band.topology == .svf ||
        band.dynamicsEnabled ||
        (band.bandType.isResonant && band.q > 2.0)
    }

    private var bandTypeLabel: String {
        switch band.bandType {
        case .lowShelf: return "Low Shelf"
        case .highShelf: return "High Shelf"
        case .peak: return "Peak"
        case .lowPass: return "Low Pass"
        case .highPass: return "High Pass"
        }
    }

    private func changeBandType(to newType: BandType) {
        band.bandType = newType
        let newRange = newType.qRange
        if band.q < newRange.lowerBound {
            band.q = newType.defaultQ
        } else if band.q > newRange.upperBound {
            band.q = newRange.upperBound
        }
    }
}

/// Small feature badge for band controls
private struct FeatureBadge: View {
    var text: String?
    var icon: String?
    let color: Color

    var body: some View {
        Group {
            if let text = text {
                Text(text)
                    .font(.system(size: 7, weight: .bold))
            } else if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .semibold))
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.15))
        )
    }
}

/// Compact dynamics parameter control
private struct DynamicsControl: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String

    @State private var isDragging = false
    @State private var dragStartValue: Float = 0

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(DSPTheme.textTertiary)

            Text(String(format: format, value))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(isDragging ? DSPTheme.meterYellow : DSPTheme.textSecondary)
                .frame(minWidth: 36)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DSPTheme.surfaceBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isDragging ? DSPTheme.meterYellow.opacity(0.5) : DSPTheme.borderColor.opacity(0.3), lineWidth: 0.5)
                )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        dragStartValue = value
                    }
                    let sensitivity = (range.upperBound - range.lowerBound) / 100
                    let delta = Float(-gesture.translation.height) * sensitivity
                    value = max(range.lowerBound, min(range.upperBound, dragStartValue + delta))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .help("Drag vertically to adjust")
    }
}

/// Compact drive control with proper drag handling
private struct DriveControl: View {
    @Binding var value: Float

    @State private var isDragging = false
    @State private var dragStartValue: Float = 0

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.0f dB", value))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(isDragging ? DSPTheme.meterYellow : DSPTheme.meterOrange)
        }
        .frame(width: 44)
        .contentShape(Rectangle())
        .onScrollWheel { delta, modifiers in
            let sens: Float = modifiers.contains(.option) ? 0.1 : 0.5
            value = max(0, min(24, value + Float(delta) * sens))
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        dragStartValue = value
                    }
                    let delta = Float(-gesture.translation.height / 10)
                    value = max(0, min(24, dragStartValue + delta))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .help("Drive: Drag or scroll to adjust")
    }
}

/// Vertical gain slider with Option key fine adjustment and double-click reset
struct GainSlider: View {
    @Binding var gainDb: Float
    let color: Color
    var height: CGFloat = 80

    @State private var isDragging = false
    @State private var isHovered = false
    @State private var dragStartGain: Float = 0
    @State private var dragStartY: CGFloat = 0

    private let normalSensitivity: Float = 48.0 / 80.0
    private let fineSensitivity: Float = 48.0 / 800.0
    private let trackWidth: CGFloat = 6
    private let handleSize: CGFloat = 14

    private var normalizedGain: Float {
        (gainDb + 24) / 48
    }

    var body: some View {
        GeometryReader { geometry in
            let centerY = geometry.size.height / 2
            let handleY = CGFloat(1 - normalizedGain) * geometry.size.height

            ZStack {
                // Track background with rounded ends
                RoundedRectangle(cornerRadius: trackWidth / 2)
                    .fill(DSPTheme.cardBackground)
                    .frame(width: trackWidth)

                // Track border
                RoundedRectangle(cornerRadius: trackWidth / 2)
                    .stroke(DSPTheme.borderColor.opacity(0.5), lineWidth: 0.5)
                    .frame(width: trackWidth)

                // Gain fill bar with gradient
                let barHeight = abs(CGFloat(normalizedGain - 0.5)) * geometry.size.height
                let barY = gainDb >= 0
                    ? centerY - barHeight / 2
                    : centerY + barHeight / 2

                RoundedRectangle(cornerRadius: trackWidth / 2)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.9), color],
                            startPoint: gainDb >= 0 ? .bottom : .top,
                            endPoint: gainDb >= 0 ? .top : .bottom
                        )
                    )
                    .frame(width: trackWidth, height: barHeight)
                    .position(x: geometry.size.width / 2, y: barY)
                    .shadow(color: color.opacity(isDragging ? 0.5 : 0.3), radius: isDragging ? 6 : 3)

                // Center line (0 dB reference) with ticks
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(DSPTheme.textSecondary)
                        .frame(width: 4, height: 1.5)
                    Rectangle()
                        .fill(DSPTheme.textSecondary)
                        .frame(width: trackWidth + 8, height: 1.5)
                    Rectangle()
                        .fill(DSPTheme.textSecondary)
                        .frame(width: 4, height: 1.5)
                }
                .position(x: geometry.size.width / 2, y: centerY)

                // Minor tick marks
                ForEach([-18, -12, -6, 6, 12, 18], id: \.self) { db in
                    let tickY = dbToY(Float(db), height: geometry.size.height)
                    Rectangle()
                        .fill(DSPTheme.textTertiary.opacity(0.4))
                        .frame(width: 3, height: 1)
                        .position(x: geometry.size.width / 2 - trackWidth / 2 - 4, y: tickY)
                }

                // Drag handle with improved design
                ZStack {
                    // Outer glow when active
                    if isDragging || isHovered {
                        Circle()
                            .fill(color.opacity(0.25))
                            .frame(width: handleSize + 8, height: handleSize + 8)
                            .blur(radius: 2)
                    }

                    // Handle body
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [color, color.opacity(0.85)],
                                center: .center,
                                startRadius: 0,
                                endRadius: handleSize / 2
                            )
                        )
                        .frame(width: handleSize, height: handleSize)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: color.opacity(0.6), radius: isDragging ? 6 : 3)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                    // Center dot
                    Circle()
                        .fill(.white.opacity(0.4))
                        .frame(width: 3, height: 3)
                }
                .position(x: geometry.size.width / 2, y: handleY)
                .scaleEffect(isDragging ? 1.15 : (isHovered ? 1.05 : 1.0))
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
            }
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
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                gainDb = 0
            }
        }
        .help("Drag to adjust gain. Hold Option for fine control. Double-click to reset to 0 dB.")
    }

    private func dbToY(_ db: Float, height: CGFloat) -> CGFloat {
        let normalized = (db + 24) / 48
        return CGFloat(1 - normalized) * height
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

/// Reusable header button for EQ panel controls
private struct HeaderButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    var color: Color = DSPTheme.accent
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isActive ? color : (isHovered ? DSPTheme.textSecondary : DSPTheme.textTertiary))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? color.opacity(0.15) : (isHovered ? DSPTheme.surfaceBackground : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? color.opacity(0.3) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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
            ZStack {
                if isEnabled {
                    Circle()
                        .fill(DSPTheme.effectEnabled.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .blur(radius: 3)
                }
                Circle()
                    .fill(isEnabled ? DSPTheme.effectEnabled : DSPTheme.effectBypassed)
                    .frame(width: 7, height: 7)
            }

            Text(name)
                .font(DSPTypography.title)
                .foregroundColor(isEnabled ? DSPTheme.textPrimary : DSPTheme.textTertiary)

            Button(action: onToggle) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(isEnabled ? DSPTheme.effectEnabled : DSPTheme.textDisabled)
                        .frame(width: 5, height: 5)
                    Text(isEnabled ? "ON" : "BYPASS")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                .foregroundColor(isEnabled ? DSPTheme.effectEnabled : DSPTheme.textDisabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isEnabled ? DSPTheme.effectEnabled.opacity(0.12) : DSPTheme.surfaceBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isEnabled ? DSPTheme.effectEnabled.opacity(0.25) : DSPTheme.borderColor.opacity(0.3), lineWidth: 0.5)
                )
                .scaleEffect(isHovered ? 1.02 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.1)) {
                    isHovered = hovering
                }
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
