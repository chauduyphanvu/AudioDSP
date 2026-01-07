import Foundation

/// Stereo delay with feedback and ping-pong mode
final class Delay: Effect, @unchecked Sendable {
    private var bufferLeft: [Float]
    private var bufferRight: [Float]
    private var writeIndex: Int = 0
    private let maxDelaySamples: Int

    private var delayMs: Float = 250
    private var feedback: Float = 0.3
    var pingPong: Bool = false

    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 0.3

    let name = "Delay"

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate

        // Max 2 seconds of delay
        let maxDelayMs: Float = 2000
        maxDelaySamples = Int(sampleRate * maxDelayMs / 1000)

        bufferLeft = [Float](repeating: 0, count: maxDelaySamples)
        bufferRight = [Float](repeating: 0, count: maxDelaySamples)
    }

    private var delaySamples: Int {
        min(Int(sampleRate * delayMs / 1000), maxDelaySamples - 1)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        let samples = delaySamples
        let readIndex = (writeIndex + maxDelaySamples - samples) % maxDelaySamples

        let delayedLeft = bufferLeft[readIndex]
        let delayedRight = bufferRight[readIndex]

        let newLeft: Float
        let newRight: Float

        if pingPong {
            // Ping-pong: left feeds right delay, right feeds left delay
            newLeft = left + delayedRight * feedback
            newRight = right + delayedLeft * feedback
        } else {
            // Standard stereo delay
            newLeft = left + delayedLeft * feedback
            newRight = right + delayedRight * feedback
        }

        bufferLeft[writeIndex] = newLeft
        bufferRight[writeIndex] = newRight
        writeIndex = (writeIndex + 1) % maxDelaySamples

        return (delayedLeft, delayedRight)
    }

    func reset() {
        bufferLeft = [Float](repeating: 0, count: maxDelaySamples)
        bufferRight = [Float](repeating: 0, count: maxDelaySamples)
        writeIndex = 0
    }

    var parameters: [ParameterDescriptor] {
        [
            ParameterDescriptor("Time", min: 1, max: 2000, defaultValue: 250, unit: .milliseconds),
            ParameterDescriptor("Feedback", min: 0, max: 0.95, defaultValue: 0.3, unit: .percent),
        ]
    }

    func getParameter(_ index: Int) -> Float {
        switch index {
        case 0: return delayMs
        case 1: return feedback
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        switch index {
        case 0: delayMs = min(max(value, 1), 2000)
        case 1: feedback = min(max(value, 0), 0.95)
        default: break
        }
    }
}
