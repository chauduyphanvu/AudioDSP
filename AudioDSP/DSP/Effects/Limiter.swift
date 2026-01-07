import Foundation

/// Brickwall limiter with true lookahead
/// Lookahead works by detecting peaks BEFORE they reach the output,
/// giving time to smoothly reduce gain before the peak arrives.
final class Limiter: Effect, @unchecked Sendable {
    private var ceilingDb: Float = -0.3
    private var ceilingLinear: Float

    // Lookahead delay line for audio
    private let lookaheadSamples: Int
    private var audioBufferLeft: [Float]
    private var audioBufferRight: [Float]
    private var audioWriteIndex: Int = 0

    // Separate buffer to scan ahead for peaks
    private var peakBuffer: [Float]
    private var peakWriteIndex: Int = 0

    // Gain smoothing envelope
    private var currentGain: Float = 1.0
    private let attackCoeff: Float   // Instant attack (very fast)
    private let releaseCoeff: Float  // Smooth release

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
        audioBufferLeft = [Float](repeating: 0, count: lookaheadSamples)
        audioBufferRight = [Float](repeating: 0, count: lookaheadSamples)
        peakBuffer = [Float](repeating: 0, count: lookaheadSamples)

        ceilingLinear = dbToLinear(-0.3)

        // Very fast attack (~0.1ms) for brickwall limiting
        attackCoeff = expf(-1.0 / (0.1 * 0.001 * sampleRate))
        // Smooth release (~50ms default)
        releaseCoeff = expf(-1.0 / (50.0 * 0.001 * sampleRate))
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // 1. Store incoming audio in the delay line
        //    This delays the audio by lookaheadSamples
        let delayedLeft = audioBufferLeft[audioWriteIndex]
        let delayedRight = audioBufferRight[audioWriteIndex]

        audioBufferLeft[audioWriteIndex] = left
        audioBufferRight[audioWriteIndex] = right

        // 2. Store peak level of incoming audio in peak buffer
        //    This lets us "see" peaks before they exit the audio delay
        let inputPeak = stereoPeak(left, right)
        peakBuffer[peakWriteIndex] = inputPeak

        // 3. Scan the peak buffer to find the maximum upcoming peak
        //    This is the key to true lookahead - we see what's coming
        var maxUpcomingPeak: Float = 0
        for i in 0..<lookaheadSamples {
            maxUpcomingPeak = max(maxUpcomingPeak, peakBuffer[i])
        }

        // 4. Calculate target gain based on upcoming peaks
        let targetGain: Float
        if maxUpcomingPeak < 1e-10 {
            targetGain = 1.0
        } else if maxUpcomingPeak > ceilingLinear {
            targetGain = ceilingLinear / maxUpcomingPeak
        } else {
            targetGain = 1.0
        }

        // 5. Smooth the gain changes
        //    Fast attack (gain decreasing) to catch peaks
        //    Slow release (gain increasing) for smooth recovery
        let coeff = targetGain < currentGain ? attackCoeff : releaseCoeff
        currentGain = coeff * currentGain + (1.0 - coeff) * targetGain

        // Ensure gain never exceeds 1.0
        let finalGain = min(currentGain, 1.0)

        // 6. Update indices
        audioWriteIndex = (audioWriteIndex + 1) % lookaheadSamples
        peakWriteIndex = (peakWriteIndex + 1) % lookaheadSamples

        // Update metering
        gainReductionDb = linearToDb(finalGain)

        // 7. Apply gain to the DELAYED audio
        //    The audio has been delayed, giving us time to reduce gain
        //    before the peak arrives at the output
        return (delayedLeft * finalGain, delayedRight * finalGain)
    }

    func reset() {
        audioBufferLeft = [Float](repeating: 0, count: lookaheadSamples)
        audioBufferRight = [Float](repeating: 0, count: lookaheadSamples)
        peakBuffer = [Float](repeating: 0, count: lookaheadSamples)
        audioWriteIndex = 0
        peakWriteIndex = 0
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
            ceilingDb = min(max(value, -12), 0)
            ceilingLinear = dbToLinear(ceilingDb)
        default: break
        }
    }
}
