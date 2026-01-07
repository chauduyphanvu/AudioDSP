import Foundation

/// Dynamic range compressor with soft knee
final class Compressor: Effect, @unchecked Sendable {
    private var thresholdDb: Float = -12
    private var ratio: Float = 4
    private let kneeDb: Float = 6
    private var makeupGainDb: Float = 0

    private var envelope: EnvelopeFollower
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    /// Current gain reduction in dB (for metering)
    private(set) var gainReductionDb: Float = 0

    let name = "Compressor"

    init(sampleRate: Float = 48000) {
        self.envelope = EnvelopeFollower(
            sampleRate: sampleRate,
            attackMs: 10,
            releaseMs: 100,
            mode: .attackRelease
        )
    }

    @inline(__always)
    private func computeGain(_ inputDb: Float) -> Float {
        let overThreshold = inputDb - thresholdDb

        // Soft knee computation
        if kneeDb > 0 && overThreshold > -kneeDb / 2 && overThreshold < kneeDb / 2 {
            let kneeFactor = (overThreshold + kneeDb / 2) / kneeDb
            let kneeGain = kneeFactor * kneeFactor * kneeDb / 2 * (1 / ratio - 1)
            return kneeGain + makeupGainDb
        }

        if overThreshold <= 0 {
            return makeupGainDb
        } else {
            let gainReduction = overThreshold * (1 - 1 / ratio)
            return -gainReduction + makeupGainDb
        }
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Peak detection (stereo linked)
        let inputPeak = stereoPeak(left, right)

        // Envelope follower
        let envelopeValue = envelope.process(inputPeak)

        let envelopeDb = linearToDb(envelopeValue)
        let gainDb = computeGain(envelopeDb)

        gainReductionDb = gainDb - makeupGainDb

        let gainLinear = dbToLinear(gainDb)

        return (left * gainLinear, right * gainLinear)
    }

    func reset() {
        envelope.reset()
        gainReductionDb = 0
    }

    var parameters: [ParameterDescriptor] {
        [
            ParameterDescriptor("Threshold", min: -60, max: 0, defaultValue: -12, unit: .decibels),
            ParameterDescriptor("Ratio", min: 1, max: 20, defaultValue: 4, unit: .ratio),
            ParameterDescriptor("Attack", min: 0.1, max: 100, defaultValue: 10, unit: .milliseconds),
            ParameterDescriptor("Release", min: 10, max: 1000, defaultValue: 100, unit: .milliseconds),
            ParameterDescriptor("Makeup", min: 0, max: 24, defaultValue: 0, unit: .decibels),
        ]
    }

    func getParameter(_ index: Int) -> Float {
        switch index {
        case 0: return thresholdDb
        case 1: return ratio
        case 2: return envelope.attackMs
        case 3: return envelope.releaseMs
        case 4: return makeupGainDb
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        switch index {
        case 0: thresholdDb = min(max(value, -60), 0)
        case 1: ratio = min(max(value, 1), 20)
        case 2: envelope.setAttackMs(min(max(value, 0.1), 100))
        case 3: envelope.setReleaseMs(min(max(value, 10), 1000))
        case 4: makeupGainDb = min(max(value, 0), 24)
        default: break
        }
    }
}
