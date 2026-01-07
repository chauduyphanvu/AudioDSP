import Foundation

/// Brickwall limiter with lookahead
final class Limiter: Effect, @unchecked Sendable {
    private var ceilingDb: Float = -0.3
    private var ceilingLinear: Float

    // Lookahead buffer for brickwall limiting
    private let lookaheadSamples: Int
    private var bufferLeft: [Float]
    private var bufferRight: [Float]
    private var bufferIndex: Int = 0

    // Envelope follower with instant attack
    private var envelope: EnvelopeFollower

    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    /// Current gain reduction in dB (for metering)
    private(set) var gainReductionDb: Float = 0

    let name = "Limiter"

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate

        // 5ms lookahead
        lookaheadSamples = max(1, Int(sampleRate * 0.005))
        bufferLeft = [Float](repeating: 0, count: lookaheadSamples)
        bufferRight = [Float](repeating: 0, count: lookaheadSamples)

        ceilingLinear = dbToLinear(-0.3)

        envelope = EnvelopeFollower(
            sampleRate: sampleRate,
            attackMs: 0,
            releaseMs: 50,
            mode: .instantAttack
        )
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Store current sample in lookahead buffer
        let delayedLeft = bufferLeft[bufferIndex]
        let delayedRight = bufferRight[bufferIndex]

        bufferLeft[bufferIndex] = left
        bufferRight[bufferIndex] = right
        bufferIndex = (bufferIndex + 1) % lookaheadSamples

        // Peak detection
        let inputPeak = stereoPeak(left, right)

        // Calculate target gain
        let target: Float
        if inputPeak < 1e-10 {
            target = 1.0
        } else if inputPeak > ceilingLinear {
            target = ceilingLinear / inputPeak
        } else {
            target = 1.0
        }

        // Envelope follower (instant attack, smooth release)
        let envelopeValue = envelope.process(target)

        // Apply gain to delayed signal
        let gain = min(envelopeValue, 1.0)
        gainReductionDb = linearToDb(gain)

        return (delayedLeft * gain, delayedRight * gain)
    }

    func reset() {
        envelope.reset()
        bufferLeft = [Float](repeating: 0, count: lookaheadSamples)
        bufferRight = [Float](repeating: 0, count: lookaheadSamples)
        bufferIndex = 0
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
        case 1: return envelope.releaseMs
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        switch index {
        case 0:
            ceilingDb = min(max(value, -12), 0)
            ceilingLinear = dbToLinear(ceilingDb)
        case 1:
            envelope.setReleaseMs(min(max(value, 10), 500))
        default: break
        }
    }
}
