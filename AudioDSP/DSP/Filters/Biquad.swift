import Foundation
import os

/// Thread-safe atomic parameter block for lock-free audio processing
struct BiquadParams: Sendable {
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
/// Thread-safe: uses os_unfair_lock for parameter updates shared between UI and audio threads
final class Biquad: @unchecked Sendable {
    private var currentCoeffs: BiquadCoefficients
    private var z1: Float = 0
    private var z2: Float = 0

    // Parameter smoothing state - interpolate parameters to guarantee stability
    // Protected by paramsLock for thread-safe access between UI and audio threads
    private var currentParams: BiquadParams
    private var targetParams: BiquadParams
    private var smoothingCounter: Int = 0
    private let smoothingSamples: Int
    private let sampleRate: Float

    // Recalculation interval during smoothing (every N samples for CPU efficiency)
    private let recalcInterval: Int = 32
    private var recalcCounter: Int = 0

    // Thread-safety lock for parameter updates
    // os_unfair_lock is the fastest lock on Apple platforms, suitable for real-time audio
    private var paramsLock = os_unfair_lock()

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
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }

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
    /// Thread-safe: can be called from any thread
    func updateCoefficients(_ newCoeffs: BiquadCoefficients) {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        currentCoeffs = newCoeffs
        smoothingCounter = 0
    }

    /// Update coefficients immediately without smoothing (use sparingly)
    /// Thread-safe: can be called from any thread
    func setCoefficientsImmediate(_ newCoeffs: BiquadCoefficients) {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        currentCoeffs = newCoeffs
        smoothingCounter = 0
    }

    /// Set parameters immediately without smoothing
    /// Thread-safe: can be called from any thread
    func setParametersImmediate(_ params: BiquadParams) {
        let newCoeffs = BiquadCoefficients.calculate(
            type: params.filterType,
            sampleRate: sampleRate,
            frequency: params.frequency,
            q: params.q
        )
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        currentParams = params
        targetParams = params
        smoothingCounter = 0
        currentCoeffs = newCoeffs
    }

    @inline(__always)
    func process(_ input: Float) -> Float {
        // Acquire lock briefly to read/update smoothing state
        // This is necessary because updateParameters can be called from UI thread
        os_unfair_lock_lock(&paramsLock)

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
                case .lowPass1Pole: interpFilterType = .lowPass1Pole
                case .highPass1Pole: interpFilterType = .highPass1Pole
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

        // Release lock before filter processing (filter state is audio-thread only)
        os_unfair_lock_unlock(&paramsLock)

        // Direct Form II Transposed processing (no lock needed - audio thread only)
        let output = currentCoeffs.b0 * input + z1
        z1 = currentCoeffs.b1 * input - currentCoeffs.a1 * output + z2
        z2 = currentCoeffs.b2 * input - currentCoeffs.a2 * output

        z1 = flushDenormals(z1)
        z2 = flushDenormals(z2)

        return output
    }

    func reset() {
        os_unfair_lock_lock(&paramsLock)
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
        os_unfair_lock_unlock(&paramsLock)
    }

    /// Thread-safe check if parameter smoothing is in progress
    var isSmoothing: Bool {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        return smoothingCounter > 0
    }
}
