import SwiftUI

/// Master panel with I/O meters, preset selector, and A/B toggle
struct MasterPanel: View {
    @ObservedObject var state: DSPState
    @ObservedObject var presetManager: PresetManager
    @ObservedObject var audioEngine: AudioEngine

    @State private var showSavePreset = false
    @State private var newPresetName = ""
    @State private var showSpectrum = true
    @State private var spectrumMode: SpectrumDisplayMode = .curve
    @State private var showPeakHold = true
    @State private var peakDecaySpeed: Float = 40  // dB per second

    var body: some View {
        VStack(spacing: 16) {
            // Top bar: Preset selector and controls
            HStack(spacing: 12) {
                // Preset section
                HStack(spacing: 8) {
                    Menu {
                        ForEach(presetManager.presets) { preset in
                            Button(preset.name) {
                                presetManager.load(preset, into: state)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                            Text(presetManager.currentPreset?.name ?? "Select Preset")
                                .font(DSPTypography.body)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(DSPTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minWidth: 140)
                        .background(DSPTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DSPTheme.borderColor.opacity(0.5), lineWidth: 0.5)
                        )
                    }
                    .menuStyle(.borderlessButton)

                    ToolbarIconButton(
                        icon: "square.and.arrow.down",
                        tooltip: "Save Preset"
                    ) {
                        showSavePreset = true
                    }
                }

                ToolbarDivider()

                // A/B comparison
                HStack(spacing: 2) {
                    ABSlotButton(label: "A", isSelected: state.abSlot == .a) {
                        if state.abSlot != .a { state.switchABSlot() }
                    }
                    ABSlotButton(label: "B", isSelected: state.abSlot == .b) {
                        if state.abSlot != .b { state.switchABSlot() }
                    }
                }
                .padding(2)
                .background(DSPTheme.surfaceBackground.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                // History controls
                HStack(spacing: 4) {
                    ToolbarIconButton(
                        icon: "arrow.uturn.backward",
                        tooltip: "Undo",
                        isEnabled: state.canUndo
                    ) {
                        state.undo()
                    }
                    ToolbarIconButton(
                        icon: "arrow.uturn.forward",
                        tooltip: "Redo",
                        isEnabled: state.canRedo
                    ) {
                        state.redo()
                    }
                }

                ToolbarDivider()

                // Spectrum controls
                HStack(spacing: 4) {
                    ToolbarIconButton(
                        icon: showSpectrum ? "waveform" : "waveform.slash",
                        tooltip: showSpectrum ? "Hide Spectrum" : "Show Spectrum",
                        isActive: showSpectrum
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSpectrum.toggle()
                        }
                    }

                    if showSpectrum {
                        SpectrumModeToggle(mode: $spectrumMode)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))

                        PeakHoldToggle(isEnabled: $showPeakHold)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))

                        if showPeakHold {
                            DecaySpeedControl(speed: $peakDecaySpeed)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showSpectrum)
                .animation(.easeInOut(duration: 0.2), value: showPeakHold)

                ToolbarDivider()

                // Engine status
                HStack(spacing: 6) {
                    Circle()
                        .fill(audioEngine.isRunning ? DSPTheme.meterGreen : DSPTheme.meterRed)
                        .frame(width: 6, height: 6)
                        .shadow(color: (audioEngine.isRunning ? DSPTheme.meterGreen : DSPTheme.meterRed).opacity(0.5), radius: 3)

                    Text(audioEngine.statusMessage)
                        .font(DSPTypography.caption)
                        .foregroundColor(DSPTheme.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DSPTheme.surfaceBackground.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 16)

            // Spectrum analyzer
            if showSpectrum {
                SpectrumView(
                    magnitudes: audioEngine.spectrumData,
                    height: 80,
                    displayMode: spectrumMode,
                    showPeakHold: showPeakHold,
                    peakDecayRate: peakDecaySpeed
                )
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            // I/O Section
            HStack(spacing: 32) {
                // Input meters
                VStack(spacing: 8) {
                    Text("INPUT")
                        .font(DSPTypography.caption)
                        .foregroundColor(DSPTheme.textTertiary)

                    LevelMeterView(
                        leftLevel: audioEngine.inputLevelLeft,
                        rightLevel: audioEngine.inputLevelRight,
                        height: 100
                    )
                }

                Spacer()

                // Output section
                VStack(spacing: 8) {
                    Text("OUTPUT")
                        .font(DSPTypography.caption)
                        .foregroundColor(DSPTheme.textTertiary)

                    HStack(spacing: 16) {
                        // Output gain fader
                        Fader(
                            value: $state.outputGain,
                            range: -24...24,
                            label: "Gain",
                            unit: .decibels,
                            height: 100
                        )

                        // Output meters
                        LevelMeterView(
                            leftLevel: audioEngine.outputLevelLeft,
                            rightLevel: audioEngine.outputLevelRight,
                            height: 100
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .panelStyle()
        .sheet(isPresented: $showSavePreset) {
            SavePresetSheet(
                presetName: $newPresetName,
                onSave: {
                    let preset = presetManager.createPreset(from: state, name: newPresetName)
                    try? presetManager.save(preset)
                    showSavePreset = false
                    newPresetName = ""
                },
                onCancel: {
                    showSavePreset = false
                    newPresetName = ""
                }
            )
        }
    }
}

/// Toolbar icon button with hover state
struct ToolbarIconButton: View {
    let icon: String
    var tooltip: String = ""
    var isEnabled: Bool = true
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: 28, height: 28)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }

    private var foregroundColor: Color {
        if !isEnabled { return DSPTheme.textDisabled }
        if isActive { return DSPTheme.accent }
        if isHovered { return DSPTheme.textPrimary }
        return DSPTheme.textSecondary
    }

    private var backgroundColor: Color {
        if isHovered && isEnabled {
            return DSPTheme.cardBackground
        }
        return Color.clear
    }
}

/// Toolbar divider
struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(DSPTheme.borderColor.opacity(0.5))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}

/// A/B slot button
struct ABSlotButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? DSPTheme.textPrimary : (isHovered ? DSPTheme.textSecondary : DSPTheme.textTertiary))
                .frame(width: 26, height: 22)
                .background(isSelected ? DSPTheme.accent : (isHovered ? DSPTheme.cardBackground : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Decay speed control for peak hold
struct DecaySpeedControl: View {
    @Binding var speed: Float  // 10-100 dB/s

    @State private var isHovered = false

    private let minSpeed: Float = 10
    private let maxSpeed: Float = 100

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tortoise")
                .font(.system(size: 8))
                .foregroundColor(DSPTheme.textTertiary)

            MiniSlider(value: $speed, range: minSpeed...maxSpeed)
                .frame(width: 50)

            Image(systemName: "hare")
                .font(.system(size: 8))
                .foregroundColor(DSPTheme.textTertiary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(DSPTheme.surfaceBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Peak decay speed: \(Int(speed)) dB/s")
    }
}

/// Mini slider for compact controls
struct MiniSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float>

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(DSPTheme.surfaceBackground)
                    .frame(height: 4)

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(DSPTheme.accent)
                    .frame(width: geometry.size.width * CGFloat(normalizedValue), height: 4)

                // Thumb
                Circle()
                    .fill(isDragging ? DSPTheme.accent : DSPTheme.textPrimary)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .offset(x: (geometry.size.width - 10) * CGFloat(normalizedValue))
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let normalized = Float(gesture.location.x / geometry.size.width)
                        let clamped = min(max(normalized, 0), 1)
                        value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 16)
    }

    private var normalizedValue: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

/// Peak hold toggle button
struct PeakHoldToggle: View {
    @Binding var isEnabled: Bool

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                isEnabled.toggle()
            }
        }) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isEnabled ? DSPTheme.accent : (isHovered ? DSPTheme.textSecondary : DSPTheme.textTertiary))
                .frame(width: 28, height: 26)
                .background(isEnabled ? DSPTheme.accent.opacity(0.15) : (isHovered ? DSPTheme.cardBackground : DSPTheme.surfaceBackground.opacity(0.5)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isEnabled ? "Hide peak hold" : "Show peak hold")
    }
}

/// Spectrum display mode toggle
struct SpectrumModeToggle: View {
    @Binding var mode: SpectrumDisplayMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SpectrumDisplayMode.allCases, id: \.self) { displayMode in
                SpectrumModeButton(
                    icon: displayMode == .curve ? "waveform.path" : "chart.bar.fill",
                    isSelected: mode == displayMode
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        mode = displayMode
                    }
                }
            }
        }
        .padding(2)
        .background(DSPTheme.surfaceBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help("Switch spectrum display mode")
    }
}

/// Individual spectrum mode button
struct SpectrumModeButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? DSPTheme.textPrimary : (isHovered ? DSPTheme.textSecondary : DSPTheme.textTertiary))
                .frame(width: 24, height: 22)
                .background(isSelected ? DSPTheme.accent : (isHovered ? DSPTheme.cardBackground : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Save preset sheet
struct SavePresetSheet: View {
    @Binding var presetName: String
    var onSave: () -> Void
    var onCancel: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Save Preset")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DSPTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(DSPTheme.cardBackground)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preset Name")
                        .font(DSPTypography.caption)
                        .foregroundColor(DSPTheme.textSecondary)

                    TextField("", text: $presetName, prompt: Text("Enter preset name...").foregroundColor(DSPTheme.textTertiary))
                        .textFieldStyle(.plain)
                        .font(DSPTypography.body)
                        .foregroundColor(DSPTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(DSPTheme.surfaceBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isTextFieldFocused ? DSPTheme.accent : DSPTheme.borderColor, lineWidth: 1)
                        )
                        .focused($isTextFieldFocused)
                }

                // Actions
                HStack(spacing: 10) {
                    Spacer()

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DSPTheme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(DSPTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(DSPTheme.borderColor, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onSave) {
                        Text("Save Preset")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(presetName.isEmpty ? DSPTheme.textDisabled : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(presetName.isEmpty ? DSPTheme.cardBackground : DSPTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(presetName.isEmpty)
                }
            }
            .padding(20)
        }
        .frame(width: 320)
        .background(DSPTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DSPTheme.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

#Preview {
    MasterPanel(
        state: DSPState(),
        presetManager: PresetManager(),
        audioEngine: AudioEngine()
    )
    .frame(width: 600)
    .background(DSPTheme.background)
}
