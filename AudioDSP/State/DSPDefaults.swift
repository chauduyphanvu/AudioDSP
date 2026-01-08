import Foundation

/// Centralized default values for DSP parameters
enum DSPDefaults {
    // MARK: - EQ
    static let eqBypassed = false
    static let eqProcessingMode = EQProcessingMode.minimumPhase
    static let eqSaturationMode = SaturationMode.clean
    static let eqSaturationDrive: Float = 0.0

    // MARK: - Compressor
    static let compressorThreshold: Float = -12
    static let compressorRatio: Float = 4
    static let compressorAttack: Float = 10
    static let compressorRelease: Float = 100
    static let compressorMakeup: Float = 0
    static let compressorBypassed = false

    // MARK: - Limiter
    static let limiterCeiling: Float = -0.3
    static let limiterRelease: Float = 50
    static let limiterBypassed = false

    // MARK: - Reverb
    static let reverbRoomSize: Float = 0.5
    static let reverbDamping: Float = 0.5
    static let reverbWidth: Float = 1.0
    static let reverbMix: Float = 0.3
    static let reverbBypassed = false

    // MARK: - Delay
    static let delayTime: Float = 250
    static let delayFeedback: Float = 0.3
    static let delayMix: Float = 0.3
    static let delayBypassed = false

    // MARK: - Stereo Widener
    static let stereoWidth: Float = 1.0
    static let stereoWidenerBypassed = false

    // MARK: - Bass Enhancer
    static let bassAmount: Float = 50
    static let bassLowFreq: Float = 100
    static let bassHarmonics: Float = 30
    static let bassEnhancerBypassed = false

    // MARK: - Vocal Clarity
    static let vocalClarity: Float = 50
    static let vocalAir: Float = 25
    static let vocalClarityBypassed = false

    // MARK: - Output
    static let outputGain: Float = 0
    static let outputGainBypassed = false
}
