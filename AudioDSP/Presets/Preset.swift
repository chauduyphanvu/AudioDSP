import Foundation

/// Preset model for saving and loading DSP configurations
struct Preset: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var description: String?
    var effects: [EffectPreset]
    var createdAt: Date = Date()
}

/// Individual effect preset within a preset
struct EffectPreset: Codable {
    var effectType: EffectType
    var enabled: Bool
    var wetDry: Float
    var parameters: [Float]
}

/// Preset manager for save/load operations
@MainActor
final class PresetManager: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var currentPreset: Preset?

    private let presetsURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        presetsURL = appSupport.appendingPathComponent("AudioDSP/Presets")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: presetsURL, withIntermediateDirectories: true)

        loadPresets()
        initializeBuiltInPresets()
    }

    func loadPresets() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: presetsURL, includingPropertiesForKeys: nil)
            presets = files.compactMap { url -> Preset? in
                guard url.pathExtension == "json" else { return nil }
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Preset.self, from: data)
            }
            presets.sort { $0.name < $1.name }
        } catch {
            presets = []
        }
    }

    func save(_ preset: Preset) throws {
        let filename = sanitizeFilename(preset.name) + ".json"
        let url = presetsURL.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(preset)
        try data.write(to: url)

        loadPresets()
    }

    func delete(_ preset: Preset) throws {
        let filename = sanitizeFilename(preset.name) + ".json"
        let url = presetsURL.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: url)
        loadPresets()
    }

    /// Load the previous preset in the list
    func loadPrevious(into state: DSPState) {
        guard !presets.isEmpty else { return }
        let currentIndex = presets.firstIndex(where: { $0.id == currentPreset?.id }) ?? 0
        let previousIndex = (currentIndex - 1 + presets.count) % presets.count
        load(presets[previousIndex], into: state)
    }

    /// Load the next preset in the list
    func loadNext(into state: DSPState) {
        guard !presets.isEmpty else { return }
        let currentIndex = presets.firstIndex(where: { $0.id == currentPreset?.id }) ?? -1
        let nextIndex = (currentIndex + 1) % presets.count
        load(presets[nextIndex], into: state)
    }

    func load(_ preset: Preset, into state: DSPState) {
        currentPreset = preset

        for effectPreset in preset.effects {
            switch effectPreset.effectType {
            case .parametricEQ:
                state.eqBypassed = !effectPreset.enabled
                // Parse EQ parameters (3 per band: freq, gain, q)
                for i in 0..<5 {
                    let baseIndex = i * 3
                    if baseIndex + 2 < effectPreset.parameters.count {
                        state.eqBands[i].frequency = effectPreset.parameters[baseIndex]
                        state.eqBands[i].gainDb = effectPreset.parameters[baseIndex + 1]
                        state.eqBands[i].q = effectPreset.parameters[baseIndex + 2]
                    }
                }

            case .compressor:
                state.compressorBypassed = !effectPreset.enabled
                if effectPreset.parameters.count >= 5 {
                    state.compressorThreshold = effectPreset.parameters[0]
                    state.compressorRatio = effectPreset.parameters[1]
                    state.compressorAttack = effectPreset.parameters[2]
                    state.compressorRelease = effectPreset.parameters[3]
                    state.compressorMakeup = effectPreset.parameters[4]
                }

            case .limiter:
                state.limiterBypassed = !effectPreset.enabled
                if effectPreset.parameters.count >= 2 {
                    state.limiterCeiling = effectPreset.parameters[0]
                    state.limiterRelease = effectPreset.parameters[1]
                }

            case .reverb:
                state.reverbBypassed = !effectPreset.enabled
                state.reverbMix = effectPreset.wetDry
                if effectPreset.parameters.count >= 3 {
                    state.reverbRoomSize = effectPreset.parameters[0]
                    state.reverbDamping = effectPreset.parameters[1]
                    state.reverbWidth = effectPreset.parameters[2]
                }

            case .delay:
                state.delayBypassed = !effectPreset.enabled
                state.delayMix = effectPreset.wetDry
                if effectPreset.parameters.count >= 2 {
                    state.delayTime = effectPreset.parameters[0]
                    state.delayFeedback = effectPreset.parameters[1]
                }

            case .stereoWidener:
                state.stereoWidenerBypassed = !effectPreset.enabled
                if effectPreset.parameters.count >= 1 {
                    state.stereoWidth = effectPreset.parameters[0]
                }

            case .bassEnhancer:
                state.bassEnhancerBypassed = !effectPreset.enabled
                if effectPreset.parameters.count >= 3 {
                    state.bassAmount = effectPreset.parameters[0]
                    state.bassLowFreq = effectPreset.parameters[1]
                    state.bassHarmonics = effectPreset.parameters[2]
                }

            case .vocalClarity:
                state.vocalClarityBypassed = !effectPreset.enabled
                if effectPreset.parameters.count >= 2 {
                    state.vocalClarity = effectPreset.parameters[0]
                    state.vocalAir = effectPreset.parameters[1]
                }

            case .gain:
                state.outputGainBypassed = !effectPreset.enabled
                if effectPreset.parameters.count >= 1 {
                    state.outputGain = effectPreset.parameters[0]
                }
            }
        }

        state.syncToChain()
    }

    func createPreset(from state: DSPState, name: String, description: String? = nil) -> Preset {
        Preset(
            name: name,
            description: description,
            effects: [
                EffectPreset(
                    effectType: .parametricEQ,
                    enabled: !state.eqBypassed,
                    wetDry: 1.0,
                    parameters: state.eqBands.flatMap { [$0.frequency, $0.gainDb, $0.q] }
                ),
                EffectPreset(
                    effectType: .compressor,
                    enabled: !state.compressorBypassed,
                    wetDry: 1.0,
                    parameters: [state.compressorThreshold, state.compressorRatio, state.compressorAttack, state.compressorRelease, state.compressorMakeup]
                ),
                EffectPreset(
                    effectType: .limiter,
                    enabled: !state.limiterBypassed,
                    wetDry: 1.0,
                    parameters: [state.limiterCeiling, state.limiterRelease]
                ),
                EffectPreset(
                    effectType: .reverb,
                    enabled: !state.reverbBypassed,
                    wetDry: state.reverbMix,
                    parameters: [state.reverbRoomSize, state.reverbDamping, state.reverbWidth]
                ),
                EffectPreset(
                    effectType: .delay,
                    enabled: !state.delayBypassed,
                    wetDry: state.delayMix,
                    parameters: [state.delayTime, state.delayFeedback]
                ),
                EffectPreset(
                    effectType: .stereoWidener,
                    enabled: !state.stereoWidenerBypassed,
                    wetDry: 1.0,
                    parameters: [state.stereoWidth]
                ),
                EffectPreset(
                    effectType: .bassEnhancer,
                    enabled: !state.bassEnhancerBypassed,
                    wetDry: 1.0,
                    parameters: [state.bassAmount, state.bassLowFreq, state.bassHarmonics]
                ),
                EffectPreset(
                    effectType: .vocalClarity,
                    enabled: !state.vocalClarityBypassed,
                    wetDry: 1.0,
                    parameters: [state.vocalClarity, state.vocalAir]
                ),
                EffectPreset(
                    effectType: .gain,
                    enabled: !state.outputGainBypassed,
                    wetDry: 1.0,
                    parameters: [state.outputGain]
                ),
            ]
        )
    }

    private func sanitizeFilename(_ name: String) -> String {
        name.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
    }

    private func initializeBuiltInPresets() {
        let builtIn = Preset.builtIn
        for preset in builtIn {
            let filename = sanitizeFilename(preset.name) + ".json"
            let url = presetsURL.appendingPathComponent(filename)

            if !FileManager.default.fileExists(atPath: url.path) {
                try? save(preset)
            }
        }
    }
}

// MARK: - Built-in Presets

extension Preset {
    static let flat = Preset(
        name: "Flat",
        description: "No processing - flat response",
        effects: [
            EffectPreset(effectType: .parametricEQ, enabled: true, wetDry: 1.0,
                         parameters: [80, 0, 0.707, 250, 0, 1.0, 1000, 0, 1.0, 4000, 0, 1.0, 12000, 0, 0.707]),
            EffectPreset(effectType: .compressor, enabled: false, wetDry: 1.0,
                         parameters: [-12, 4, 10, 100, 0]),
            EffectPreset(effectType: .limiter, enabled: true, wetDry: 1.0,
                         parameters: [-0.3, 50]),
            EffectPreset(effectType: .reverb, enabled: false, wetDry: 0.2,
                         parameters: [0.5, 0.5, 1.0]),
            EffectPreset(effectType: .delay, enabled: false, wetDry: 0.2,
                         parameters: [250, 0.3]),
            EffectPreset(effectType: .stereoWidener, enabled: false, wetDry: 1.0,
                         parameters: [1.0]),
            EffectPreset(effectType: .bassEnhancer, enabled: false, wetDry: 1.0,
                         parameters: [50, 100, 30]),
            EffectPreset(effectType: .vocalClarity, enabled: false, wetDry: 1.0,
                         parameters: [50, 25]),
            EffectPreset(effectType: .gain, enabled: true, wetDry: 1.0,
                         parameters: [0]),
        ]
    )

    static let bassBoost = Preset(
        name: "Bass Boost",
        description: "Enhanced low frequencies",
        effects: [
            EffectPreset(effectType: .parametricEQ, enabled: true, wetDry: 1.0,
                         parameters: [80, 6, 0.707, 250, 3, 1.0, 1000, 0, 1.0, 4000, 0, 1.0, 12000, 0, 0.707]),
            EffectPreset(effectType: .compressor, enabled: false, wetDry: 1.0,
                         parameters: [-12, 4, 10, 100, 0]),
            EffectPreset(effectType: .limiter, enabled: true, wetDry: 1.0,
                         parameters: [-0.3, 50]),
            EffectPreset(effectType: .reverb, enabled: false, wetDry: 0.2,
                         parameters: [0.5, 0.5, 1.0]),
            EffectPreset(effectType: .delay, enabled: false, wetDry: 0.2,
                         parameters: [250, 0.3]),
            EffectPreset(effectType: .stereoWidener, enabled: false, wetDry: 1.0,
                         parameters: [1.0]),
            EffectPreset(effectType: .bassEnhancer, enabled: true, wetDry: 1.0,
                         parameters: [60, 100, 40]),
            EffectPreset(effectType: .vocalClarity, enabled: false, wetDry: 1.0,
                         parameters: [50, 25]),
            EffectPreset(effectType: .gain, enabled: true, wetDry: 1.0,
                         parameters: [0]),
        ]
    )

    static let vocalClarityPreset = Preset(
        name: "Vocal Clarity",
        description: "Enhanced mid frequencies for vocals",
        effects: [
            EffectPreset(effectType: .parametricEQ, enabled: true, wetDry: 1.0,
                         parameters: [80, -2, 0.707, 250, -1, 1.0, 1000, 2, 1.0, 4000, 3, 1.0, 12000, 2, 0.707]),
            EffectPreset(effectType: .compressor, enabled: true, wetDry: 1.0,
                         parameters: [-18, 3, 15, 150, 2]),
            EffectPreset(effectType: .limiter, enabled: true, wetDry: 1.0,
                         parameters: [-0.3, 50]),
            EffectPreset(effectType: .reverb, enabled: false, wetDry: 0.2,
                         parameters: [0.5, 0.5, 1.0]),
            EffectPreset(effectType: .delay, enabled: false, wetDry: 0.2,
                         parameters: [250, 0.3]),
            EffectPreset(effectType: .stereoWidener, enabled: false, wetDry: 1.0,
                         parameters: [1.0]),
            EffectPreset(effectType: .bassEnhancer, enabled: false, wetDry: 1.0,
                         parameters: [50, 100, 30]),
            EffectPreset(effectType: .vocalClarity, enabled: true, wetDry: 1.0,
                         parameters: [70, 40]),
            EffectPreset(effectType: .gain, enabled: true, wetDry: 1.0,
                         parameters: [0]),
        ]
    )

    static let loudness = Preset(
        name: "Loudness",
        description: "Increased perceived loudness",
        effects: [
            EffectPreset(effectType: .parametricEQ, enabled: true, wetDry: 1.0,
                         parameters: [80, 4, 0.707, 250, 0, 1.0, 1000, 0, 1.0, 4000, 2, 1.0, 12000, 3, 0.707]),
            EffectPreset(effectType: .compressor, enabled: true, wetDry: 1.0,
                         parameters: [-20, 4, 5, 80, 6]),
            EffectPreset(effectType: .limiter, enabled: true, wetDry: 1.0,
                         parameters: [-0.3, 30]),
            EffectPreset(effectType: .reverb, enabled: false, wetDry: 0.2,
                         parameters: [0.5, 0.5, 1.0]),
            EffectPreset(effectType: .delay, enabled: false, wetDry: 0.2,
                         parameters: [250, 0.3]),
            EffectPreset(effectType: .stereoWidener, enabled: true, wetDry: 1.0,
                         parameters: [1.3]),
            EffectPreset(effectType: .bassEnhancer, enabled: false, wetDry: 1.0,
                         parameters: [50, 100, 30]),
            EffectPreset(effectType: .vocalClarity, enabled: false, wetDry: 1.0,
                         parameters: [50, 25]),
            EffectPreset(effectType: .gain, enabled: true, wetDry: 1.0,
                         parameters: [0]),
        ]
    )

    static var builtIn: [Preset] {
        [flat, bassBoost, vocalClarityPreset, loudness]
    }
}
