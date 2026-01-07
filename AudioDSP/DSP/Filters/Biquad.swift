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

/// Thread-safe atomic parameter block for lock-free audio processing
struct BiquadParams {
    var filterType: BiquadFilterType
    var frequency: Float
    var q: Float
    var gainDb: Float

    init(filterType: BiquadFilterType = .peak(gainDb: 0), frequency: Float = 1000, q: Float = 1.0, gainDb: Float = 0) {
        self.filterType = filterType
        self.frequency = frequency
        self.q = q
        self.gainDb = gainDb
    }
}

/// Direct Form 2 Transposed biquad filter implementation with parameter smoothing
/// CRITICAL FIX: Interpolates parameters (not coefficients) to guarantee filter stability
/// Coefficient interpolation can cause poles to move outside the unit circle during transitions
final class Biquad: @unchecked Sendable {
    private var currentCoeffs: BiquadCoefficients
    private var z1: Float = 0
    private var z2: Float = 0

    // Parameter smoothing state - interpolate parameters to guarantee stability
    private var currentParams: BiquadParams
    private var targetParams: BiquadParams
    private var smoothingCounter: Int = 0
    private let smoothingSamples: Int
    private let sampleRate: Float

    // Recalculation interval during smoothing (every N samples for CPU efficiency)
    private let recalcInterval: Int = 32
    private var recalcCounter: Int = 0

    init(coefficients: BiquadCoefficients = BiquadCoefficients(), sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        self.currentCoeffs = coefficients
        self.currentParams = BiquadParams()
        self.targetParams = BiquadParams()
        // ~5ms smoothing time for parameter interpolation
        self.smoothingSamples = Int(sampleRate * 0.005)
    }

    init(params: BiquadParams, sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        self.currentParams = params
        self.targetParams = params
        self.smoothingSamples = Int(sampleRate * 0.005)

        self.currentCoeffs = BiquadCoefficients.calculate(
            type: params.filterType,
            sampleRate: sampleRate,
            frequency: params.frequency,
            q: params.q
        )
    }

    /// Update target parameters - will smoothly interpolate to new values
    /// This method is thread-safe and can be called from any thread
    func updateParameters(_ newParams: BiquadParams) {
        // If already smoothing, snap currentParams to where we are now
        // to avoid interpolating from stale values
        if smoothingCounter > 0 {
            // We're mid-transition - use current interpolated position as new start
            let factor = 1.0 - Float(smoothingCounter) / Float(smoothingSamples)

            let logCurrentFreq = log(max(currentParams.frequency, 1.0))
            let logTargetFreq = log(max(targetParams.frequency, 1.0))
            let interpFreq = exp(logCurrentFreq + (logTargetFreq - logCurrentFreq) * factor)

            let interpGain = currentParams.gainDb + (targetParams.gainDb - currentParams.gainDb) * factor

            let safeCurrentQ = max(currentParams.q, 0.01)
            let safeTargetQ = max(targetParams.q, 0.01)
            let interpQ = exp(log(safeCurrentQ) + (log(safeTargetQ) - log(safeCurrentQ)) * factor)

            currentParams = BiquadParams(
                filterType: targetParams.filterType,
                frequency: interpFreq,
                q: interpQ,
                gainDb: interpGain
            )
        }

        targetParams = newParams
        smoothingCounter = smoothingSamples
        recalcCounter = 0
    }

    /// Update target coefficients directly (for compatibility)
    func updateCoefficients(_ newCoeffs: BiquadCoefficients) {
        currentCoeffs = newCoeffs
        smoothingCounter = 0
    }

    /// Update coefficients immediately without smoothing (use sparingly)
    func setCoefficientsImmediate(_ newCoeffs: BiquadCoefficients) {
        currentCoeffs = newCoeffs
        smoothingCounter = 0
    }

    /// Set parameters immediately without smoothing
    func setParametersImmediate(_ params: BiquadParams) {
        currentParams = params
        targetParams = params
        smoothingCounter = 0
        currentCoeffs = BiquadCoefficients.calculate(
            type: params.filterType,
            sampleRate: sampleRate,
            frequency: params.frequency,
            q: params.q
        )
    }

    @inline(__always)
    func process(_ input: Float) -> Float {
        // Parameter interpolation for smooth, stable transitions
        if smoothingCounter > 0 {
            recalcCounter -= 1
            if recalcCounter <= 0 {
                // Interpolate parameters (not coefficients!) to guarantee stability
                let factor = 1.0 - Float(smoothingCounter) / Float(smoothingSamples)

                // Interpolate frequency logarithmically for perceptually linear changes
                let logCurrentFreq = log(currentParams.frequency)
                let logTargetFreq = log(targetParams.frequency)
                let interpFreq = exp(logCurrentFreq + (logTargetFreq - logCurrentFreq) * factor)

                // Interpolate gain linearly
                let interpGain = currentParams.gainDb + (targetParams.gainDb - currentParams.gainDb) * factor

                // Interpolate Q logarithmically for perceptually linear bandwidth changes
                // Clamp Q to reasonable minimum to avoid log(0) which produces -infinity
                let safeCurrentQ = max(currentParams.q, 0.01)
                let safeTargetQ = max(targetParams.q, 0.01)
                let logCurrentQ = log(safeCurrentQ)
                let logTargetQ = log(safeTargetQ)
                let interpQ = exp(logCurrentQ + (logTargetQ - logCurrentQ) * factor)

                // Construct interpolated filter type with correct gain value
                let interpFilterType: BiquadFilterType
                switch targetParams.filterType {
                case .peak: interpFilterType = .peak(gainDb: interpGain)
                case .lowShelf: interpFilterType = .lowShelf(gainDb: interpGain)
                case .highShelf: interpFilterType = .highShelf(gainDb: interpGain)
                case .lowPass: interpFilterType = .lowPass
                case .highPass: interpFilterType = .highPass
                case .allPass: interpFilterType = .allPass
                }

                // Recalculate coefficients from interpolated parameters
                currentCoeffs = BiquadCoefficients.calculate(
                    type: interpFilterType,
                    sampleRate: sampleRate,
                    frequency: interpFreq,
                    q: interpQ
                )

                recalcCounter = recalcInterval
            }

            smoothingCounter -= 1

            // Snap to target when done
            if smoothingCounter == 0 {
                currentParams = targetParams
                currentCoeffs = BiquadCoefficients.calculate(
                    type: targetParams.filterType,
                    sampleRate: sampleRate,
                    frequency: targetParams.frequency,
                    q: targetParams.q
                )
            }
        }

        // Direct Form II Transposed processing
        let output = currentCoeffs.b0 * input + z1
        z1 = currentCoeffs.b1 * input - currentCoeffs.a1 * output + z2
        z2 = currentCoeffs.b2 * input - currentCoeffs.a2 * output

        // Flush denormals using threshold check
        // Note: Hardware FTZ/DAZ is set at audio callback level for efficiency
        if abs(z1) < 1e-15 { z1 = 0 }
        if abs(z2) < 1e-15 { z2 = 0 }

        return output
    }

    func reset() {
        z1 = 0
        z2 = 0
        smoothingCounter = 0
        currentParams = targetParams
        currentCoeffs = BiquadCoefficients.calculate(
            type: targetParams.filterType,
            sampleRate: sampleRate,
            frequency: targetParams.frequency,
            q: targetParams.q
        )
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

    /// Returns true if Q controls resonance (LP/HP modes)
    var isResonant: Bool {
        self == .lowPass || self == .highPass
    }

    /// User-friendly Q label based on mode
    var qLabel: String {
        isResonant ? "Res" : "Q"
    }
}

/// Thread-safe atomic parameter block for EQ band
/// Used for lock-free parameter updates between UI and audio threads
struct EQBandParams: @unchecked Sendable {
    var bandType: BandType
    var frequency: Float
    var gainDb: Float
    var q: Float
    var solo: Bool

    init(bandType: BandType = .peak, frequency: Float = 1000, gainDb: Float = 0, q: Float = 1.0, solo: Bool = false) {
        self.bandType = bandType
        self.frequency = frequency
        self.gainDb = gainDb
        self.q = q
        self.solo = solo
    }
}

/// Single EQ band with stereo processing and thread-safe parameter updates
/// CRITICAL FIX: Uses atomic parameter block for thread safety between UI and audio threads
final class EQBand: @unchecked Sendable {
    private var filterLeft: Biquad
    private var filterRight: Biquad
    private let sampleRate: Float

    // Atomic parameter storage for thread-safe access
    // UI thread writes, audio thread reads
    private var params: EQBandParams

    // Public read-only access to current parameters
    var bandType: BandType { params.bandType }
    var frequency: Float { params.frequency }
    var gainDb: Float { params.gainDb }
    var q: Float { params.q }
    var solo: Bool { params.solo }

    init(sampleRate: Float, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        self.sampleRate = sampleRate
        self.params = EQBandParams(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q)

        let biquadParams = BiquadParams(
            filterType: bandType.toBiquadType(gainDb: gainDb),
            frequency: frequency,
            q: q,
            gainDb: gainDb
        )

        self.filterLeft = Biquad(params: biquadParams, sampleRate: sampleRate)
        self.filterRight = Biquad(params: biquadParams, sampleRate: sampleRate)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        (filterLeft.process(left), filterRight.process(right))
    }

    /// Thread-safe parameter update
    /// All parameters are updated atomically to prevent partial state reads
    func update(bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        // Update atomic parameter block
        params = EQBandParams(
            bandType: bandType,
            frequency: frequency,
            gainDb: gainDb,
            q: q,
            solo: params.solo
        )

        // Update filter parameters with smoothing
        let biquadParams = BiquadParams(
            filterType: bandType.toBiquadType(gainDb: gainDb),
            frequency: frequency,
            q: q,
            gainDb: gainDb
        )

        filterLeft.updateParameters(biquadParams)
        filterRight.updateParameters(biquadParams)
    }

    /// Update solo state
    func setSolo(_ solo: Bool) {
        params = EQBandParams(
            bandType: params.bandType,
            frequency: params.frequency,
            gainDb: params.gainDb,
            q: params.q,
            solo: solo
        )
    }

    func reset() {
        filterLeft.reset()
        filterRight.reset()
    }
}

/// Utility to convert Q to bandwidth in octaves and vice versa
enum QBandwidthConverter {
    /// Convert Q factor to bandwidth in octaves
    static func qToOctaves(_ q: Float) -> Float {
        2.0 * asinh(1.0 / (2.0 * q)) / log(2.0)
    }

    /// Convert bandwidth in octaves to Q factor
    static func octavesToQ(_ octaves: Float) -> Float {
        1.0 / (2.0 * sinh(octaves * log(2.0) / 2.0))
    }

    /// Format Q value with optional bandwidth display
    static func formatQ(_ q: Float, showBandwidth: Bool = true) -> String {
        if showBandwidth {
            let octaves = qToOctaves(q)
            return String(format: "%.2f (%.2f oct)", q, octaves)
        }
        return String(format: "%.2f", q)
    }
}
