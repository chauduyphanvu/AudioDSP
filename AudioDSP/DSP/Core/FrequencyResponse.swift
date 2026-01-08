import Foundation

/// Utilities for calculating filter frequency response.
/// Consolidates duplicated magnitude/phase calculation code from ParametricEQ, LinearPhaseEQ, etc.
enum FrequencyResponse {

    /// Calculate magnitude response of a biquad filter at a given frequency.
    /// Uses the transfer function H(z) evaluated on the unit circle.
    @inline(__always)
    static func magnitude(
        coefficients: BiquadCoefficients,
        atFrequency frequency: Float,
        sampleRate: Float
    ) -> Float {
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let cosOmega = cos(omega)
        let cos2Omega = cos(2.0 * omega)
        let sinOmega = sin(omega)
        let sin2Omega = sin(2.0 * omega)

        // H(e^jw) = (b0 + b1*e^-jw + b2*e^-2jw) / (1 + a1*e^-jw + a2*e^-2jw)
        let numReal = coefficients.b0 + coefficients.b1 * cosOmega + coefficients.b2 * cos2Omega
        let numImag = -coefficients.b1 * sinOmega - coefficients.b2 * sin2Omega
        let denReal = 1.0 + coefficients.a1 * cosOmega + coefficients.a2 * cos2Omega
        let denImag = -coefficients.a1 * sinOmega - coefficients.a2 * sin2Omega

        let numMag = sqrt(numReal * numReal + numImag * numImag)
        let denMag = sqrt(denReal * denReal + denImag * denImag)

        return numMag / max(denMag, 1e-10)
    }

    /// Calculate phase response of a biquad filter at a given frequency (in radians).
    @inline(__always)
    static func phase(
        coefficients: BiquadCoefficients,
        atFrequency frequency: Float,
        sampleRate: Float
    ) -> Float {
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let cosOmega = cos(omega)
        let cos2Omega = cos(2.0 * omega)
        let sinOmega = sin(omega)
        let sin2Omega = sin(2.0 * omega)

        let numReal = coefficients.b0 + coefficients.b1 * cosOmega + coefficients.b2 * cos2Omega
        let numImag = -coefficients.b1 * sinOmega - coefficients.b2 * sin2Omega
        let denReal = 1.0 + coefficients.a1 * cosOmega + coefficients.a2 * cos2Omega
        let denImag = -coefficients.a1 * sinOmega - coefficients.a2 * sin2Omega

        let numPhase = atan2(numImag, numReal)
        let denPhase = atan2(denImag, denReal)

        return numPhase - denPhase
    }

    /// Calculate combined magnitude response for a series of EQ bands.
    static func combinedMagnitude(
        bands: [(bandType: BandType, frequency: Float, gainDb: Float, q: Float)],
        atFrequency frequency: Float,
        sampleRate: Float
    ) -> Float {
        var magnitude: Float = 1.0

        for band in bands {
            let coeffs = BiquadCoefficients.calculate(
                type: band.bandType.toBiquadType(gainDb: band.gainDb),
                sampleRate: sampleRate,
                frequency: band.frequency,
                q: band.q
            )
            magnitude *= Self.magnitude(coefficients: coeffs, atFrequency: frequency, sampleRate: sampleRate)
        }

        return magnitude
    }

    /// Calculate combined phase response for a series of EQ bands (in radians).
    static func combinedPhase(
        bands: [(bandType: BandType, frequency: Float, gainDb: Float, q: Float)],
        atFrequency frequency: Float,
        sampleRate: Float
    ) -> Float {
        var totalPhase: Float = 0.0

        for band in bands {
            let coeffs = BiquadCoefficients.calculate(
                type: band.bandType.toBiquadType(gainDb: band.gainDb),
                sampleRate: sampleRate,
                frequency: band.frequency,
                q: band.q
            )
            totalPhase += Self.phase(coefficients: coeffs, atFrequency: frequency, sampleRate: sampleRate)
        }

        return totalPhase
    }
}
