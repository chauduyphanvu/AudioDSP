import Foundation

/// Biquad filter coefficients
struct BiquadCoefficients: Sendable {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0

    /// Calculate biquad coefficients using Robert Bristow-Johnson's Audio EQ Cookbook
    /// with frequency pre-warping compensation for accurate response near Nyquist
    static func calculate(
        type: BiquadFilterType,
        sampleRate: Float,
        frequency: Float,
        q: Float,
        usePrewarping: Bool = true
    ) -> BiquadCoefficients {
        // Apply frequency pre-warping compensation for accurate filter response near Nyquist
        // This corrects the frequency cramping inherent in the bilinear transform
        let actualFreq: Float
        if usePrewarping {
            let nyquist = sampleRate / 2.0
            // Clamp frequency to avoid issues at Nyquist
            let clampedFreq = min(frequency, nyquist * 0.99)
            // Pre-warp the analog frequency to compensate for bilinear transform
            actualFreq = sampleRate / Float.pi * tan(Float.pi * clampedFreq / sampleRate)
        } else {
            actualFreq = frequency
        }

        let omega = 2.0 * Float.pi * actualFreq / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * q)

        var b0: Float = 1, b1: Float = 0, b2: Float = 0
        var a0: Float = 1, a1: Float = 0, a2: Float = 0

        switch type {
        case .lowShelf(let gainDb):
            let A = powf(10.0, gainDb / 40.0)
            let sqrtA = sqrt(A)
            let sqrtA2Alpha = 2.0 * sqrtA * alpha

            b0 = A * ((A + 1) - (A - 1) * cosOmega + sqrtA2Alpha)
            b1 = 2.0 * A * ((A - 1) - (A + 1) * cosOmega)
            b2 = A * ((A + 1) - (A - 1) * cosOmega - sqrtA2Alpha)
            a0 = (A + 1) + (A - 1) * cosOmega + sqrtA2Alpha
            a1 = -2.0 * ((A - 1) + (A + 1) * cosOmega)
            a2 = (A + 1) + (A - 1) * cosOmega - sqrtA2Alpha

        case .highShelf(let gainDb):
            let A = powf(10.0, gainDb / 40.0)
            let sqrtA = sqrt(A)
            let sqrtA2Alpha = 2.0 * sqrtA * alpha

            b0 = A * ((A + 1) + (A - 1) * cosOmega + sqrtA2Alpha)
            b1 = -2.0 * A * ((A - 1) + (A + 1) * cosOmega)
            b2 = A * ((A + 1) + (A - 1) * cosOmega - sqrtA2Alpha)
            a0 = (A + 1) - (A - 1) * cosOmega + sqrtA2Alpha
            a1 = 2.0 * ((A - 1) - (A + 1) * cosOmega)
            a2 = (A + 1) - (A - 1) * cosOmega - sqrtA2Alpha

        case .peak(let gainDb):
            let A = powf(10.0, gainDb / 40.0)

            b0 = 1.0 + alpha * A
            b1 = -2.0 * cosOmega
            b2 = 1.0 - alpha * A
            a0 = 1.0 + alpha / A
            a1 = -2.0 * cosOmega
            a2 = 1.0 - alpha / A

        case .lowPass:
            b0 = (1.0 - cosOmega) / 2.0
            b1 = 1.0 - cosOmega
            b2 = (1.0 - cosOmega) / 2.0
            a0 = 1.0 + alpha
            a1 = -2.0 * cosOmega
            a2 = 1.0 - alpha

        case .highPass:
            b0 = (1.0 + cosOmega) / 2.0
            b1 = -(1.0 + cosOmega)
            b2 = (1.0 + cosOmega) / 2.0
            a0 = 1.0 + alpha
            a1 = -2.0 * cosOmega
            a2 = 1.0 - alpha

        case .allPass:
            b0 = 1.0 - alpha
            b1 = -2.0 * cosOmega
            b2 = 1.0 + alpha
            a0 = 1.0 + alpha
            a1 = -2.0 * cosOmega
            a2 = 1.0 - alpha

        case .lowPass1Pole:
            // Simple 1-pole lowpass (6dB/oct)
            // Bilinear transform of H(s) = ωc/(s + ωc)
            // Note: omega = ωc*T where T = 1/sampleRate (reusing pre-warped omega from above)
            let denom1p = 2.0 + omega
            b0 = omega / denom1p
            b1 = omega / denom1p
            b2 = 0
            a0 = 1.0
            a1 = (omega - 2.0) / denom1p
            a2 = 0

        case .highPass1Pole:
            // Simple 1-pole highpass (6dB/oct)
            // Bilinear transform of H(s) = s/(s + ωc)
            // Note: omega = ωc*T where T = 1/sampleRate (reusing pre-warped omega from above)
            let denom1p = 2.0 + omega
            b0 = 2.0 / denom1p
            b1 = -2.0 / denom1p
            b2 = 0
            a0 = 1.0
            a1 = (omega - 2.0) / denom1p
            a2 = 0
        }

        // Normalize coefficients
        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}
