import SwiftUI

/// Main content view with all effect panels
struct ContentView: View {
    @StateObject private var state = DSPState()
    @StateObject private var presetManager = PresetManager()
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var sessionManager = SessionManager()

    @State private var selectedTab: Tab = .effects

    enum Tab: String, CaseIterable {
        case effects = "Effects"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .effects: return "slider.horizontal.3"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Master panel (always visible)
                MasterPanel(
                    state: state,
                    presetManager: presetManager,
                    audioEngine: audioEngine
                )
                .padding(16)

            // Tab selector
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(DSPTheme.panelBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DSPTheme.borderColor.opacity(0.5))
                    .frame(height: 1)
            }

            // Main content area
            ScrollView {
                switch selectedTab {
                case .effects:
                    effectsContent

                case .settings:
                    settingsContent
                }
            }
            .background(DSPTheme.background)
            }
            .background(DSPTheme.background)

            // Toast overlay for keyboard shortcut feedback
            ToastOverlay()
        }
        .onAppear {
            state.audioEngine = audioEngine
            Task {
                await audioEngine.start()
                // Restore previous session or load default preset
                if !sessionManager.restoreSession(into: state) {
                    if let firstPreset = presetManager.presets.first {
                        presetManager.load(firstPreset, into: state)
                    }
                }
                state.syncToChain()
                // Enable auto-save for future changes
                sessionManager.bindAutoSave(to: state)
            }
        }
        .onDisappear {
            audioEngine.stop()
        }
        .keyboardShortcutHandlers(
            state: state,
            audioEngine: audioEngine,
            presetManager: presetManager
        )
    }

    @ViewBuilder
    private var effectsContent: some View {
        VStack(spacing: 16) {
            // EQ Panel with spectrum overlay
            EQPanel(state: state, sampleRate: Float(audioEngine.sampleRate), spectrumData: audioEngine.spectrumData)

            HStack(alignment: .top, spacing: 16) {
                // Dynamics panel (left)
                DynamicsPanel(state: state)
                    .frame(maxWidth: 380)

                // Effects panel (right)
                EffectsPanel(state: state)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Audio Engine section
            SettingsSection(title: "Audio Engine", icon: "waveform.circle.fill") {
                VStack(spacing: 0) {
                    SettingsRow(label: "Sample Rate") {
                        Text("\(Int(audioEngine.sampleRate)) Hz")
                            .font(DSPTypography.parameterValue)
                            .foregroundColor(DSPTheme.textPrimary)
                    }

                    Divider()
                        .background(DSPTheme.borderColor.opacity(0.3))

                    SettingsRow(label: "Engine Status") {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(audioEngine.isRunning ? DSPTheme.meterGreen : DSPTheme.meterRed)
                                .frame(width: 8, height: 8)
                                .shadow(color: (audioEngine.isRunning ? DSPTheme.meterGreen : DSPTheme.meterRed).opacity(0.5), radius: 4)
                            Text(audioEngine.statusMessage)
                                .font(DSPTypography.body)
                                .foregroundColor(DSPTheme.textPrimary)
                        }
                    }

                    Divider()
                        .background(DSPTheme.borderColor.opacity(0.3))

                    SettingsRow(label: "Control") {
                        Button(action: {
                            if audioEngine.isRunning {
                                audioEngine.stop()
                            } else {
                                Task { await audioEngine.start() }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: audioEngine.isRunning ? "stop.fill" : "play.fill")
                                    .font(.system(size: 10))
                                Text(audioEngine.isRunning ? "Stop Engine" : "Start Engine")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(audioEngine.isRunning ? DSPTheme.meterRed : DSPTheme.meterGreen)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                (audioEngine.isRunning ? DSPTheme.meterRed : DSPTheme.meterGreen).opacity(0.15)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke((audioEngine.isRunning ? DSPTheme.meterRed : DSPTheme.meterGreen).opacity(0.3), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // About section
            SettingsSection(title: "About", icon: "info.circle.fill") {
                VStack(spacing: 0) {
                    SettingsRow(label: "Application") {
                        Text("AudioDSP")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DSPTheme.textPrimary)
                    }

                    Divider()
                        .background(DSPTheme.borderColor.opacity(0.3))

                    SettingsRow(label: "Description") {
                        Text("Professional audio processing")
                            .font(DSPTypography.body)
                            .foregroundColor(DSPTheme.textSecondary)
                    }

                    Divider()
                        .background(DSPTheme.borderColor.opacity(0.3))

                    SettingsRow(label: "Version") {
                        HStack(spacing: 6) {
                            Text("1.0.0")
                                .font(DSPTypography.mono)
                                .foregroundColor(DSPTheme.textSecondary)
                            Text("Build 1")
                                .font(DSPTypography.caption)
                                .foregroundColor(DSPTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DSPTheme.surfaceBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: 500, alignment: .leading)
    }
}

/// Settings section with header
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DSPTheme.accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DSPTheme.textPrimary)
            }

            content
                .background(DSPTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DSPTheme.borderColor.opacity(0.5), lineWidth: 0.5)
                )
        }
    }
}

/// Settings row with label and value
struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(DSPTypography.body)
                .foregroundColor(DSPTheme.textSecondary)
            Spacer()
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Polished tab button with underline indicator
struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                    Text(title)
                        .font(DSPTypography.heading)
                }
                .foregroundColor(isSelected ? DSPTheme.textPrimary : (isHovered ? DSPTheme.textSecondary : DSPTheme.textTertiary))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Rectangle()
                    .fill(isSelected ? DSPTheme.accent : Color.clear)
                    .frame(height: 2)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 800)
}
