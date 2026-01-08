import Combine
import Foundation
import SwiftUI

/// Main observable state for DSP parameters
/// Extensions in separate files handle: bindings, chain sync, undo/redo, A/B comparison, bypass toggles
@MainActor
final class DSPState: ObservableObject {
    // MARK: - Audio Engine

    var audioEngine: AudioEngine?

    // MARK: - EQ Parameters

    @Published var eqBands: [EQBandState] = EQBandState.defaultBands
    @Published var eqBypassed: Bool = DSPDefaults.eqBypassed
    @Published var eqProcessingMode: EQProcessingMode = DSPDefaults.eqProcessingMode
    @Published var eqSaturationMode: SaturationMode = DSPDefaults.eqSaturationMode
    @Published var eqSaturationDrive: Float = DSPDefaults.eqSaturationDrive

    // MARK: - Compressor Parameters

    @Published var compressorThreshold: Float = DSPDefaults.compressorThreshold
    @Published var compressorRatio: Float = DSPDefaults.compressorRatio
    @Published var compressorAttack: Float = DSPDefaults.compressorAttack
    @Published var compressorRelease: Float = DSPDefaults.compressorRelease
    @Published var compressorMakeup: Float = DSPDefaults.compressorMakeup
    @Published var compressorBypassed: Bool = DSPDefaults.compressorBypassed
    @Published var compressorGainReduction: Float = 0

    // MARK: - Limiter Parameters

    @Published var limiterCeiling: Float = DSPDefaults.limiterCeiling
    @Published var limiterRelease: Float = DSPDefaults.limiterRelease
    @Published var limiterBypassed: Bool = DSPDefaults.limiterBypassed
    @Published var limiterGainReduction: Float = 0

    // MARK: - Reverb Parameters

    @Published var reverbRoomSize: Float = DSPDefaults.reverbRoomSize
    @Published var reverbDamping: Float = DSPDefaults.reverbDamping
    @Published var reverbWidth: Float = DSPDefaults.reverbWidth
    @Published var reverbMix: Float = DSPDefaults.reverbMix
    @Published var reverbBypassed: Bool = DSPDefaults.reverbBypassed

    // MARK: - Delay Parameters

    @Published var delayTime: Float = DSPDefaults.delayTime
    @Published var delayFeedback: Float = DSPDefaults.delayFeedback
    @Published var delayMix: Float = DSPDefaults.delayMix
    @Published var delayBypassed: Bool = DSPDefaults.delayBypassed

    // MARK: - Stereo Widener Parameters

    @Published var stereoWidth: Float = DSPDefaults.stereoWidth
    @Published var stereoWidenerBypassed: Bool = DSPDefaults.stereoWidenerBypassed

    // MARK: - Bass Enhancer Parameters

    @Published var bassAmount: Float = DSPDefaults.bassAmount
    @Published var bassLowFreq: Float = DSPDefaults.bassLowFreq
    @Published var bassHarmonics: Float = DSPDefaults.bassHarmonics
    @Published var bassEnhancerBypassed: Bool = DSPDefaults.bassEnhancerBypassed

    // MARK: - Vocal Clarity Parameters

    @Published var vocalClarity: Float = DSPDefaults.vocalClarity
    @Published var vocalAir: Float = DSPDefaults.vocalAir
    @Published var vocalClarityBypassed: Bool = DSPDefaults.vocalClarityBypassed

    // MARK: - Output Gain

    @Published var outputGain: Float = DSPDefaults.outputGain
    @Published var outputGainBypassed: Bool = DSPDefaults.outputGainBypassed

    // MARK: - Metering

    @Published var inputLevelLeft: Float = 0
    @Published var inputLevelRight: Float = 0
    @Published var outputLevelLeft: Float = 0
    @Published var outputLevelRight: Float = 0
    @Published var spectrumData: [Float] = []

    // MARK: - Analyzer Hold

    @Published var analyzerHoldEnabled: Bool = false
    @Published var heldSpectrumData: [Float] = []

    /// Toggle analyzer hold - when enabled, freezes the current spectrum display
    func toggleAnalyzerHold() {
        if !analyzerHoldEnabled {
            heldSpectrumData = spectrumData
        }
        analyzerHoldEnabled.toggle()
        ToastManager.shared.show(
            action: analyzerHoldEnabled ? "Analyzer Held" : "Analyzer Released",
            icon: analyzerHoldEnabled ? "pause.circle.fill" : "play.circle.fill"
        )
    }

    /// Get the spectrum data to display (held or live)
    var displaySpectrumData: [Float] {
        analyzerHoldEnabled ? heldSpectrumData : spectrumData
    }

    // MARK: - A/B Comparison

    @Published var abSlot: ABSlot = .a
    var slotA: DSPStateSnapshot?
    var slotB: DSPStateSnapshot?

    // MARK: - Undo/Redo

    let undoManager = UndoManager()
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    // MARK: - Cancellables

    var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupBindings()
    }
}
