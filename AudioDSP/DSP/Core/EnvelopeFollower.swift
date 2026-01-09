import Foundation

/// Envelope detection mode
enum EnvelopeMode: Sendable {
    /// Standard attack/release envelope (for compressors)
    case attackRelease
    /// Instant attack with smooth release (for limiters)
    case instantAttack
}

/// Reusable envelope follower for dynamics processing.
/// Supports both standard attack/release and instant-attack modes.
final class EnvelopeFollower: @unchecked Sendable {
    private var envelope: Float
    private var attackCoeff: Float = 0
    private var releaseCoeff: Float = 0
    private let sampleRate: Float
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

        attackCoeff = timeToCoefficient(attackMs, sampleRate: sampleRate)
        releaseCoeff = timeToCoefficient(releaseMs, sampleRate: sampleRate)
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

        attackCoeff = timeToCoefficient(attackMs, sampleRate: sampleRate)
        releaseCoeff = timeToCoefficient(releaseMs, sampleRate: sampleRate)
    }

    func setAttackMs(_ ms: Float) {
        attackMs = ms
        attackCoeff = timeToCoefficient(ms, sampleRate: sampleRate)
    }

    func setReleaseMs(_ ms: Float) {
        releaseMs = ms
        releaseCoeff = timeToCoefficient(ms, sampleRate: sampleRate)
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

        envelope = flushDenormals(envelope)
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
