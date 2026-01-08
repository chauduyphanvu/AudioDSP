import Foundation

/// Stereo delay with feedback and ping-pong mode
final class Delay: Effect, @unchecked Sendable {
    private let delayLine: StereoDelayLine

    private var delayMs: Float = 250
    private var feedback: Float = 0.3
    var pingPong: Bool = false

    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 0.3

    let name = "Delay"

    private static let maxDelayMs: Float = 2000

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        self.delayLine = StereoDelayLine(maxDelayMs: Self.maxDelayMs, sampleRate: sampleRate)
    }

    private var delaySamples: Int {
        Int(sampleRate * delayMs / 1000).clamped(to: 0...(delayLine.maxSamples - 1))
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        let (delayedLeft, delayedRight) = delayLine.read(delaySamples: delaySamples)

        let newLeft: Float
        let newRight: Float

        if pingPong {
            newLeft = left + delayedRight * feedback
            newRight = right + delayedLeft * feedback
        } else {
            newLeft = left + delayedLeft * feedback
            newRight = right + delayedRight * feedback
        }

        delayLine.write(left: newLeft, right: newRight)
        delayLine.advance()

        return (delayedLeft, delayedRight)
    }

    func reset() {
        delayLine.reset()
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
        case 0: delayMs = value.clamped(to: 1...Self.maxDelayMs)
        case 1: feedback = value.clamped(to: 0...0.95)
        default: break
        }
    }
}
