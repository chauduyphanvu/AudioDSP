import Foundation

/// Dynamic range compressor with soft knee
final class Compressor: Effect, @unchecked Sendable {
    private var thresholdDb: Float = -12
    private var ratio: Float = 4
    private let kneeDb: Float = 6
    private var makeupGainDb: Float = 0

    // Envelope follower for gain reduction smoothing (operates in dB domain)
    private var gainEnvelopeDb: Float = 0
    private var attackCoeff: Float = 0
    private var releaseCoeff: Float = 0
    private var sampleRate: Float

    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    /// Current gain reduction in dB (for metering)
    private(set) var gainReductionDb: Float = 0

    let name = "Compressor"

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        updateCoefficients(attackMs: 10, releaseMs: 100)
    }

    private func updateCoefficients(attackMs: Float, releaseMs: Float) {
        // Time constant: coeff = exp(-1 / (time_ms * 0.001 * sampleRate))
        attackCoeff = attackMs > 0 ? expf(-1.0 / (attackMs * 0.001 * sampleRate)) : 0
        releaseCoeff = releaseMs > 0 ? expf(-1.0 / (releaseMs * 0.001 * sampleRate)) : 0
    }

    private var attackMs: Float = 10 {
        didSet { updateCoefficients(attackMs: attackMs, releaseMs: releaseMs) }
    }
    private var releaseMs: Float = 100 {
        didSet { updateCoefficients(attackMs: attackMs, releaseMs: releaseMs) }
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
        // Peak detection (stereo linked) and convert to dB
        let inputPeak = stereoPeak(left, right)
        let inputDb = linearToDb(inputPeak)

        // Compute instantaneous gain reduction in dB domain
        let targetGainDb = computeGain(inputDb)
        let targetReductionDb = targetGainDb - makeupGainDb  // Negative when compressing

        // Smooth gain reduction in dB domain
        // Use attack when gain needs to decrease (more compression), release when increasing
        let coeff = targetReductionDb < gainEnvelopeDb ? attackCoeff : releaseCoeff
        gainEnvelopeDb = coeff * gainEnvelopeDb + (1.0 - coeff) * targetReductionDb

        // Flush denormals (in linear domain equivalent, ~-300dB)
        if abs(gainEnvelopeDb) < 1e-15 {
            gainEnvelopeDb = 0
        }

        gainReductionDb = gainEnvelopeDb

        // Apply smoothed gain + makeup
        let finalGainDb = gainEnvelopeDb + makeupGainDb
        let gainLinear = dbToLinear(finalGainDb)

        return (left * gainLinear, right * gainLinear)
    }

    func reset() {
        gainEnvelopeDb = 0
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
        case 2: return attackMs
        case 3: return releaseMs
        case 4: return makeupGainDb
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        switch index {
        case 0: thresholdDb = min(max(value, -60), 0)
        case 1: ratio = min(max(value, 1), 20)
        case 2: attackMs = min(max(value, 0.1), 100)
        case 3: releaseMs = min(max(value, 10), 1000)
        case 4: makeupGainDb = min(max(value, 0), 24)
        default: break
        }
    }
}
