import Foundation

/// Convert decibels to linear amplitude
@inline(__always)
func dbToLinear(_ db: Float) -> Float {
    powf(10.0, db / 20.0)
}

/// Convert linear amplitude to decibels (clamps to avoid -infinity)
@inline(__always)
func linearToDb(_ linear: Float) -> Float {
    20.0 * log10f(max(linear, 1e-10))
}

/// Compute peak value from stereo sample pair
@inline(__always)
func stereoPeak(_ left: Float, _ right: Float) -> Float {
    max(abs(left), abs(right))
}

/// Envelope detection mode
enum EnvelopeMode: Sendable {
    /// Standard attack/release envelope (for compressors)
    case attackRelease
    /// Instant attack with smooth release (for limiters)
    case instantAttack
}

/// Reusable envelope follower for dynamics processing
final class EnvelopeFollower: @unchecked Sendable {
    private var envelope: Float
    private var attackCoeff: Float = 0
    private var releaseCoeff: Float = 0
    private var sampleRate: Float
    private(set) var attackMs: Float
    private(set) var releaseMs: Float
    private let mode: EnvelopeMode

    init(sampleRate: Float, mode: EnvelopeMode) {
        self.sampleRate = sampleRate
        self.mode = mode

        switch mode {
        case .attackRelease:
            attackMs = 10.0
            releaseMs = 100.0
            envelope = 0.0
        case .instantAttack:
            attackMs = 0.0
            releaseMs = 50.0
            envelope = 1.0
        }

        updateCoefficients()
    }

    init(sampleRate: Float, attackMs: Float, releaseMs: Float, mode: EnvelopeMode) {
        self.sampleRate = sampleRate
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.mode = mode

        switch mode {
        case .attackRelease:
            envelope = 0.0
        case .instantAttack:
            envelope = 1.0
        }

        updateCoefficients()
    }

    private func updateCoefficients() {
        attackCoeff = Self.timeToCoeff(attackMs, sampleRate: sampleRate)
        releaseCoeff = Self.timeToCoeff(releaseMs, sampleRate: sampleRate)
    }

    private static func timeToCoeff(_ timeMs: Float, sampleRate: Float) -> Float {
        if timeMs <= 0 {
            return 0
        }
        return expf(-1.0 / (timeMs * 0.001 * sampleRate))
    }

    func setAttackMs(_ ms: Float) {
        attackMs = ms
        attackCoeff = Self.timeToCoeff(ms, sampleRate: sampleRate)
    }

    func setReleaseMs(_ ms: Float) {
        releaseMs = ms
        releaseCoeff = Self.timeToCoeff(ms, sampleRate: sampleRate)
    }

    /// Process input and return envelope value
    @inline(__always)
    func process(_ input: Float) -> Float {
        switch mode {
        case .attackRelease:
            let coeff = input > envelope ? attackCoeff : releaseCoeff
            envelope = coeff * envelope + (1.0 - coeff) * input

        case .instantAttack:
            if input < envelope {
                envelope = input
            } else {
                envelope = releaseCoeff * envelope + (1.0 - releaseCoeff) * input
            }
        }

        // Flush denormals to zero
        if abs(envelope) < 1e-15 {
            envelope = 0.0
        }

        return envelope
    }

    var current: Float { envelope }

    func reset() {
        switch mode {
        case .attackRelease:
            envelope = 0.0
        case .instantAttack:
            envelope = 1.0
        }
    }
}

/// Smooth parameter changes to avoid zipper noise
final class ParameterSmoother: @unchecked Sendable {
    private var current: Float
    private var target: Float
    private let smoothingCoeff: Float

    init(initialValue: Float, smoothingMs: Float = 5.0, sampleRate: Float = 48000) {
        self.current = initialValue
        self.target = initialValue
        // Calculate smoothing coefficient for ~5ms convergence
        self.smoothingCoeff = expf(-1.0 / (smoothingMs * 0.001 * sampleRate))
    }

    func setTarget(_ value: Float) {
        target = value
    }

    @inline(__always)
    func process() -> Float {
        current = smoothingCoeff * current + (1.0 - smoothingCoeff) * target
        return current
    }

    var value: Float { current }
}
