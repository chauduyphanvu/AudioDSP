import Foundation

/// Smooth parameter changes to avoid zipper noise.
/// Uses exponential smoothing with configurable time constant.
final class ParameterSmoother: @unchecked Sendable {
    private var current: Float
    private var target: Float
    private let smoothingCoeff: Float

    init(initialValue: Float, smoothingMs: Float = 5.0, sampleRate: Float = 48000) {
        self.current = initialValue
        self.target = initialValue
        self.smoothingCoeff = timeToCoefficient(smoothingMs, sampleRate: sampleRate)
    }

    func setTarget(_ value: Float) {
        target = value
    }

    @inline(__always)
    func process() -> Float {
        current = smoothingCoeff * current + (1.0 - smoothingCoeff) * target
        current = flushDenormals(current)
        return current
    }

    var value: Float { current }
}
