import Foundation

/// SVF filter coefficients computed from frequency, Q, and gain parameters.
/// Value type that can be safely passed across thread boundaries.
/// Reference: https://cytomic.com/files/dsp/SvfLinearTrapOptimised2.pdf
struct SVFCoefficients: Sendable {
    // Common denominators for SVF topology
    let a1: Float
    let a2: Float
    let a3: Float

    // Mixing coefficients for output mode selection
    let m0: Float
    let m1: Float
    let m2: Float

    /// Create coefficients for the specified mode and parameters
    /// - Parameters:
    ///   - mode: Filter mode (lowpass, highpass, etc.)
    ///   - frequency: Cutoff/center frequency in Hz
    ///   - q: Q factor (resonance)
    ///   - gainDb: Gain in dB (used for peak/shelf modes)
    ///   - sampleRate: Audio sample rate in Hz
    init(mode: SVFMode, frequency: Float, q: Float, gainDb: Float, sampleRate: Float) {
        let nyquist = sampleRate / 2.0
        let clampedFreq = min(max(frequency, 20), nyquist * 0.99)

        // Pre-warp frequency using tan for accurate response
        var g = tan(Float.pi * clampedFreq / sampleRate)

        // k is the damping coefficient (1/Q)
        let k = 1.0 / max(q, 0.01)

        // Calculate A for peak/shelf modes
        let A = powf(10.0, gainDb / 40.0)

        // Shelf modes modify g before calculating denominators
        switch mode {
        case .lowShelf:
            g = g / sqrt(A)
        case .highShelf:
            g = g * sqrt(A)
        default:
            break
        }

        // Common denominators
        let computedA1 = 1.0 / (1.0 + g * (g + k))
        let computedA2 = g * computedA1
        let computedA3 = g * computedA2

        self.a1 = computedA1
        self.a2 = computedA2
        self.a3 = computedA3

        // Calculate mixing coefficients based on mode
        switch mode {
        case .lowpass:
            m0 = 0
            m1 = 0
            m2 = 1

        case .highpass:
            m0 = 1
            m1 = -k
            m2 = -1

        case .bandpass:
            m0 = 0
            m1 = 1
            m2 = 0

        case .notch:
            m0 = 1
            m1 = -k
            m2 = 0

        case .peak:
            let peakGain = A * A
            m0 = 1
            m1 = k * (peakGain - 1)
            m2 = 0

        case .lowShelf:
            m0 = 1
            m1 = k * (A - 1)
            m2 = A * A - 1

        case .highShelf:
            m0 = A * A
            m1 = k * (1 - A) * A
            m2 = 1 - A * A

        case .allpass:
            m0 = 1
            m1 = -2 * k
            m2 = 0
        }
    }
}
