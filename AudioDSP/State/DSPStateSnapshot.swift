import Foundation

/// Complete snapshot of DSP state for undo/redo and A/B comparison
struct DSPStateSnapshot {
    // EQ
    var eqBands: [EQBandState]
    var eqBypassed: Bool
    var eqProcessingMode: EQProcessingMode
    var eqSaturationMode: SaturationMode
    var eqSaturationDrive: Float

    // Compressor
    var compressorThreshold: Float
    var compressorRatio: Float
    var compressorAttack: Float
    var compressorRelease: Float
    var compressorMakeup: Float
    var compressorBypassed: Bool

    // Limiter
    var limiterCeiling: Float
    var limiterRelease: Float
    var limiterBypassed: Bool

    // Reverb
    var reverbRoomSize: Float
    var reverbDamping: Float
    var reverbWidth: Float
    var reverbMix: Float
    var reverbBypassed: Bool

    // Delay
    var delayTime: Float
    var delayFeedback: Float
    var delayMix: Float
    var delayBypassed: Bool

    // Stereo Widener
    var stereoWidth: Float
    var stereoWidenerBypassed: Bool

    // Bass Enhancer
    var bassAmount: Float
    var bassLowFreq: Float
    var bassHarmonics: Float
    var bassEnhancerBypassed: Bool

    // Vocal Clarity
    var vocalClarity: Float
    var vocalAir: Float
    var vocalClarityBypassed: Bool

    // Output
    var outputGain: Float
    var outputGainBypassed: Bool
}

// MARK: - DSPState Snapshot Operations

extension DSPState {
    /// Create a snapshot of the current state
    func createSnapshot() -> DSPStateSnapshot {
        DSPStateSnapshot(
            eqBands: eqBands,
            eqBypassed: eqBypassed,
            eqProcessingMode: eqProcessingMode,
            eqSaturationMode: eqSaturationMode,
            eqSaturationDrive: eqSaturationDrive,
            compressorThreshold: compressorThreshold,
            compressorRatio: compressorRatio,
            compressorAttack: compressorAttack,
            compressorRelease: compressorRelease,
            compressorMakeup: compressorMakeup,
            compressorBypassed: compressorBypassed,
            limiterCeiling: limiterCeiling,
            limiterRelease: limiterRelease,
            limiterBypassed: limiterBypassed,
            reverbRoomSize: reverbRoomSize,
            reverbDamping: reverbDamping,
            reverbWidth: reverbWidth,
            reverbMix: reverbMix,
            reverbBypassed: reverbBypassed,
            delayTime: delayTime,
            delayFeedback: delayFeedback,
            delayMix: delayMix,
            delayBypassed: delayBypassed,
            stereoWidth: stereoWidth,
            stereoWidenerBypassed: stereoWidenerBypassed,
            bassAmount: bassAmount,
            bassLowFreq: bassLowFreq,
            bassHarmonics: bassHarmonics,
            bassEnhancerBypassed: bassEnhancerBypassed,
            vocalClarity: vocalClarity,
            vocalAir: vocalAir,
            vocalClarityBypassed: vocalClarityBypassed,
            outputGain: outputGain,
            outputGainBypassed: outputGainBypassed
        )
    }

    /// Restore state from a snapshot
    func restoreSnapshot(_ snapshot: DSPStateSnapshot) {
        // EQ
        eqBands = snapshot.eqBands
        eqBypassed = snapshot.eqBypassed
        eqProcessingMode = snapshot.eqProcessingMode
        eqSaturationMode = snapshot.eqSaturationMode
        eqSaturationDrive = snapshot.eqSaturationDrive

        // Compressor
        compressorThreshold = snapshot.compressorThreshold
        compressorRatio = snapshot.compressorRatio
        compressorAttack = snapshot.compressorAttack
        compressorRelease = snapshot.compressorRelease
        compressorMakeup = snapshot.compressorMakeup
        compressorBypassed = snapshot.compressorBypassed

        // Limiter
        limiterCeiling = snapshot.limiterCeiling
        limiterRelease = snapshot.limiterRelease
        limiterBypassed = snapshot.limiterBypassed

        // Reverb
        reverbRoomSize = snapshot.reverbRoomSize
        reverbDamping = snapshot.reverbDamping
        reverbWidth = snapshot.reverbWidth
        reverbMix = snapshot.reverbMix
        reverbBypassed = snapshot.reverbBypassed

        // Delay
        delayTime = snapshot.delayTime
        delayFeedback = snapshot.delayFeedback
        delayMix = snapshot.delayMix
        delayBypassed = snapshot.delayBypassed

        // Stereo Widener
        stereoWidth = snapshot.stereoWidth
        stereoWidenerBypassed = snapshot.stereoWidenerBypassed

        // Bass Enhancer
        bassAmount = snapshot.bassAmount
        bassLowFreq = snapshot.bassLowFreq
        bassHarmonics = snapshot.bassHarmonics
        bassEnhancerBypassed = snapshot.bassEnhancerBypassed

        // Vocal Clarity
        vocalClarity = snapshot.vocalClarity
        vocalAir = snapshot.vocalAir
        vocalClarityBypassed = snapshot.vocalClarityBypassed

        // Output
        outputGain = snapshot.outputGain
        outputGainBypassed = snapshot.outputGainBypassed
    }
}
