import Foundation

/// Brickwall limiter with true lookahead
/// Lookahead works by detecting peaks BEFORE they reach the output,
/// giving time to smoothly reduce gain before the peak arrives.
final class Limiter: Effect, @unchecked Sendable {
    private var ceilingDb: Float = -0.3
    private var ceilingLinear: Float

    // Lookahead delay line for audio
    private let audioDelayLine: StereoDelayLine
    private let lookaheadSamples: Int

    // Peak envelope follower (replaces expensive buffer scanning)
    private var peakEnvelope: Float = 0
    private let peakAttackCoeff: Float   // Instant attack
    private let peakReleaseCoeff: Float  // Release matched to lookahead time

    // Gain smoothing envelope
    private var currentGain: Float = 1.0
    private let attackCoeff: Float
    private let releaseCoeff: Float

    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    /// Current gain reduction in dB (for metering)
    private(set) var gainReductionDb: Float = 0

    let name = "Limiter"

    private static let lookaheadMs: Float = 5.0
    private static let attackMs: Float = 0.1
    private static let releaseMs: Float = 50.0

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate

        lookaheadSamples = max(1, Int(sampleRate * Self.lookaheadMs / 1000))
        audioDelayLine = StereoDelayLine(maxSamples: lookaheadSamples)

        ceilingLinear = dbToLinear(-0.3)

        // Peak detector: instant attack, release matches lookahead time
        peakAttackCoeff = 0.0  // Instant attack
        peakReleaseCoeff = timeToCoefficient(Self.lookaheadMs, sampleRate: sampleRate)

        // Gain smoother
        attackCoeff = timeToCoefficient(Self.attackMs, sampleRate: sampleRate)
        releaseCoeff = timeToCoefficient(Self.releaseMs, sampleRate: sampleRate)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        let (delayedLeft, delayedRight) = audioDelayLine.process(
            left: left,
            right: right,
            delaySamples: lookaheadSamples - 1
        )

        // Track peak with envelope follower (instant attack, slow release)
        let inputPeak = stereoPeak(left, right)
        if inputPeak > peakEnvelope {
            peakEnvelope = inputPeak  // Instant attack
        } else {
            peakEnvelope = peakReleaseCoeff * peakEnvelope + (1.0 - peakReleaseCoeff) * inputPeak
        }

        // Calculate target gain to keep peaks below ceiling
        let targetGain: Float
        if peakEnvelope > ceilingLinear {
            targetGain = ceilingLinear / peakEnvelope
        } else {
            targetGain = 1.0
        }

        // Smooth gain changes (fast attack, slow release)
        let coeff = targetGain < currentGain ? attackCoeff : releaseCoeff
        currentGain = coeff * currentGain + (1.0 - coeff) * targetGain
        currentGain = flushDenormals(currentGain)
        let finalGain = min(currentGain, 1.0)

        peakEnvelope = flushDenormals(peakEnvelope)
        gainReductionDb = linearToDb(finalGain)

        return (delayedLeft * finalGain, delayedRight * finalGain)
    }

    func reset() {
        audioDelayLine.reset()
        peakEnvelope = 0
        currentGain = 1.0
        gainReductionDb = 0
    }

    var parameters: [ParameterDescriptor] {
        [
            ParameterDescriptor("Ceiling", min: -12, max: 0, defaultValue: -0.3, unit: .decibels),
            ParameterDescriptor("Release", min: 10, max: 500, defaultValue: 50, unit: .milliseconds),
        ]
    }

    func getParameter(_ index: Int) -> Float {
        switch index {
        case 0: return ceilingDb
        case 1: return 50  // Fixed release for now
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        switch index {
        case 0:
            ceilingDb = value.clamped(to: -12...0)
            ceilingLinear = dbToLinear(ceilingDb)
        default: break
        }
    }
}
