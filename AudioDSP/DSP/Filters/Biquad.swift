import Foundation

/// Filter type for biquad coefficient calculation
enum BiquadFilterType {
    case lowShelf(gainDb: Float)
    case highShelf(gainDb: Float)
    case peak(gainDb: Float)
    case lowPass
    case highPass
    case allPass
}

/// Biquad filter coefficients
struct BiquadCoefficients {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0

    /// Calculate biquad coefficients using Robert Bristow-Johnson's Audio EQ Cookbook
    static func calculate(
        type: BiquadFilterType,
        sampleRate: Float,
        frequency: Float,
        q: Float
    ) -> BiquadCoefficients {
        let omega = 2.0 * Float.pi * frequency / sampleRate
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

    /// Linear interpolation between two coefficient sets
    @inline(__always)
    func interpolated(to target: BiquadCoefficients, factor: Float) -> BiquadCoefficients {
        let inv = 1.0 - factor
        return BiquadCoefficients(
            b0: b0 * inv + target.b0 * factor,
            b1: b1 * inv + target.b1 * factor,
            b2: b2 * inv + target.b2 * factor,
            a1: a1 * inv + target.a1 * factor,
            a2: a2 * inv + target.a2 * factor
        )
    }
}

/// Direct Form 2 Transposed biquad filter implementation with coefficient smoothing
/// Interpolates coefficients over ~5ms to avoid zipper noise during parameter changes
final class Biquad: @unchecked Sendable {
    private var currentCoeffs: BiquadCoefficients
    private var targetCoeffs: BiquadCoefficients
    private var z1: Float = 0
    private var z2: Float = 0

    // Smoothing state
    private var smoothingCounter: Int = 0
    private let smoothingSamples: Int  // ~5ms at given sample rate

    init(coefficients: BiquadCoefficients = BiquadCoefficients(), sampleRate: Float = 48000) {
        self.currentCoeffs = coefficients
        self.targetCoeffs = coefficients
        // ~5ms smoothing time for coefficient interpolation
        self.smoothingSamples = Int(sampleRate * 0.005)
    }

    /// Update target coefficients - will smoothly interpolate to new values
    func updateCoefficients(_ newCoeffs: BiquadCoefficients) {
        targetCoeffs = newCoeffs
        smoothingCounter = smoothingSamples
    }

    /// Update coefficients immediately without smoothing (use sparingly)
    func setCoefficientsImmediate(_ newCoeffs: BiquadCoefficients) {
        currentCoeffs = newCoeffs
        targetCoeffs = newCoeffs
        smoothingCounter = 0
    }

    @inline(__always)
    func process(_ input: Float) -> Float {
        // Update coefficients with smoothing if needed
        if smoothingCounter > 0 {
            let factor = 1.0 - Float(smoothingCounter) / Float(smoothingSamples)
            currentCoeffs = currentCoeffs.interpolated(to: targetCoeffs, factor: factor)
            smoothingCounter -= 1

            // Snap to target when done
            if smoothingCounter == 0 {
                currentCoeffs = targetCoeffs
            }
        }

        let output = currentCoeffs.b0 * input + z1
        z1 = currentCoeffs.b1 * input - currentCoeffs.a1 * output + z2
        z2 = currentCoeffs.b2 * input - currentCoeffs.a2 * output

        // Flush denormals
        if abs(z1) < 1e-15 { z1 = 0 }
        if abs(z2) < 1e-15 { z2 = 0 }

        return output
    }

    func reset() {
        z1 = 0
        z2 = 0
        smoothingCounter = 0
        currentCoeffs = targetCoeffs
    }

    var isSmoothing: Bool {
        smoothingCounter > 0
    }
}

/// Band type for EQ bands
enum BandType: Int, Codable, Sendable {
    case lowShelf = 0
    case highShelf = 1
    case peak = 2
    case lowPass = 3
    case highPass = 4

    func toBiquadType(gainDb: Float) -> BiquadFilterType {
        switch self {
        case .lowShelf: return .lowShelf(gainDb: gainDb)
        case .highShelf: return .highShelf(gainDb: gainDb)
        case .peak: return .peak(gainDb: gainDb)
        case .lowPass: return .lowPass
        case .highPass: return .highPass
        }
    }
}

/// Single EQ band with stereo processing and parameter smoothing
final class EQBand: @unchecked Sendable {
    private var filterLeft: Biquad
    private var filterRight: Biquad
    private(set) var bandType: BandType
    private(set) var frequency: Float
    private(set) var gainDb: Float
    private(set) var q: Float
    private let sampleRate: Float

    init(sampleRate: Float, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        self.sampleRate = sampleRate
        self.bandType = bandType
        self.frequency = frequency
        self.gainDb = gainDb
        self.q = q

        let coeffs = BiquadCoefficients.calculate(
            type: bandType.toBiquadType(gainDb: gainDb),
            sampleRate: sampleRate,
            frequency: frequency,
            q: q
        )

        self.filterLeft = Biquad(coefficients: coeffs, sampleRate: sampleRate)
        self.filterRight = Biquad(coefficients: coeffs, sampleRate: sampleRate)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        (filterLeft.process(left), filterRight.process(right))
    }

    func update(bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        self.bandType = bandType
        self.frequency = frequency
        self.gainDb = gainDb
        self.q = q

        let coeffs = BiquadCoefficients.calculate(
            type: bandType.toBiquadType(gainDb: gainDb),
            sampleRate: sampleRate,
            frequency: frequency,
            q: q
        )

        // Use smoothed coefficient update to avoid zipper noise
        filterLeft.updateCoefficients(coeffs)
        filterRight.updateCoefficients(coeffs)
    }

    func reset() {
        filterLeft.reset()
        filterRight.reset()
    }
}
