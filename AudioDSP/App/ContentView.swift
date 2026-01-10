import SwiftUI

/// Main content view with all effect panels
struct ContentView: View {
    @StateObject private var state = DSPState()
    @StateObject private var presetManager = PresetManager()
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var sessionManager = SessionManager()

    private var windowTitle: String {
        var title = "Audio DSP"
        if let currentPreset = presetManager.currentPreset {
            title += " — \(currentPreset.name)"
        }
        if !audioEngine.isRunning {
            title += " (Stopped)"
        }
        return title
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MasterPanel(
                    state: state,
                    presetManager: presetManager,
                    audioEngine: audioEngine
                )
                .padding(16)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Master Controls")

                ScrollView {
                    effectsContent
                }
                .accessibilityLabel("Effects")
                .background(DSPTheme.background)
            }
            .background(DSPTheme.background)

            ToastOverlay()
        }
        .navigationTitle(windowTitle)
        .toolbar {
            MainToolbar(
                state: state,
                presetManager: presetManager,
                audioEngine: audioEngine
            )
        }
        .onAppear {
            state.audioEngine = audioEngine
            Task {
                await audioEngine.start()
                if !sessionManager.restoreSession(into: state) {
                    if let firstPreset = presetManager.presets.first {
                        presetManager.load(firstPreset, into: state)
                    }
                }
                state.syncToChain()
                sessionManager.bindAutoSave(to: state)
            }
        }
        .onDisappear {
            audioEngine.stop()
        }
        .focusable()
        .focusEffectDisabled()
        .keyboardShortcutHandlers(
            state: state,
            audioEngine: audioEngine,
            presetManager: presetManager
        )
    }

    @ViewBuilder
    private var effectsContent: some View {
        VStack(spacing: 16) {
            EQPanel(state: state, sampleRate: Float(audioEngine.sampleRate), spectrumData: audioEngine.spectrumData)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Equalizer")

            HStack(alignment: .top, spacing: 16) {
                DynamicsPanel(state: state)
                    .frame(maxWidth: 380)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Dynamics")

                EffectsPanel(state: state)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Effects")
            }
        }
        .padding(16)
    }
}

// MARK: - Main Toolbar

struct MainToolbar: ToolbarContent {
    @ObservedObject var state: DSPState
    @ObservedObject var presetManager: PresetManager
    @ObservedObject var audioEngine: AudioEngine

    private var isAllBypassed: Bool {
        state.eqBypassed && state.compressorBypassed && state.limiterBypassed &&
        state.reverbBypassed && state.delayBypassed && state.stereoWidenerBypassed &&
        state.bassEnhancerBypassed && state.vocalClarityBypassed
    }

    var body: some ToolbarContent {
        // Leading: Engine control and status
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                // Engine toggle button
                Button {
                    Task {
                        if audioEngine.isRunning {
                            audioEngine.stop()
                        } else {
                            await audioEngine.start()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: audioEngine.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(audioEngine.isRunning ? "Stop" : "Start")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(audioEngine.isRunning ? .red : .green)
                }
                .buttonStyle(.bordered)
                .help(audioEngine.isRunning ? "Stop Engine (⌘.)" : "Start Engine (⌘R)")

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(audioEngine.isRunning ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(audioEngine.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }

        // Principal: Preset selector
        ToolbarItem(placement: .principal) {
            HStack(spacing: 12) {
                // Previous preset
                Button {
                    presetManager.loadPrevious(into: state)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(presetManager.presets.isEmpty)
                .help("Previous Preset (⌘[)")

                // Preset menu
                Menu {
                    ForEach(presetManager.presets) { preset in
                        Button {
                            presetManager.load(preset, into: state)
                        } label: {
                            HStack {
                                Text(preset.name)
                                if preset.id == presetManager.currentPreset?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    if !presetManager.presets.isEmpty {
                        Divider()
                    }

                    Button {
                        NotificationCenter.default.post(name: .savePreset, object: nil)
                    } label: {
                        Label("Save Preset...", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                        Text(presetManager.currentPreset?.name ?? "No Preset")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .frame(minWidth: 100, maxWidth: 150)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .menuStyle(.borderlessButton)
                .help("Select Preset")

                // Next preset
                Button {
                    presetManager.loadNext(into: state)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(presetManager.presets.isEmpty)
                .help("Next Preset (⌘])")
            }
        }

        // Trailing: A/B, Bypass, Undo/Redo
        ToolbarItemGroup(placement: .primaryAction) {
            // A/B Toggle
            ToolbarABToggle(currentSlot: state.abSlot) {
                state.switchABSlot()
            }

            Divider()

            // Bypass All
            Button {
                state.toggleBypassAll()
            } label: {
                Image(systemName: isAllBypassed ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isAllBypassed ? .orange : .primary)
            }
            .buttonStyle(.bordered)
            .tint(isAllBypassed ? .orange : nil)
            .help(isAllBypassed ? "Enable All Effects (⌥⌘0)" : "Bypass All Effects (⌥⌘0)")

            Divider()

            // Undo
            Button {
                state.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .disabled(!state.canUndo)
            .help("Undo (⌘Z)")

            // Redo
            Button {
                state.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .disabled(!state.canRedo)
            .help("Redo (⇧⌘Z)")
        }
    }
}

// MARK: - Toolbar A/B Toggle

struct ToolbarABToggle: View {
    let currentSlot: ABSlot
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text("A")
                    .font(.system(size: 11, weight: currentSlot == .a ? .bold : .regular, design: .rounded))
                    .foregroundColor(currentSlot == .a ? .white : .secondary)
                    .frame(width: 20, height: 20)
                    .background(currentSlot == .a ? Color.accentColor : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("B")
                    .font(.system(size: 11, weight: currentSlot == .b ? .bold : .regular, design: .rounded))
                    .foregroundColor(currentSlot == .b ? .white : .secondary)
                    .frame(width: 20, height: 20)
                    .background(currentSlot == .b ? Color.accentColor : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(2)
            .background(Color.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Toggle A/B Comparison (⌘B)")
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 800)
}
