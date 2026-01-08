import Foundation
import os

/// SVF filter modes
enum SVFMode: Int, Codable, CaseIterable, Sendable {
    case lowpass = 0
    case highpass = 1
    case bandpass = 2
    case notch = 3
    case peak = 4
    case lowShelf = 5
    case highShelf = 6
    case allpass = 7

    var displayName: String {
        switch self {
        case .lowpass: return "Low Pass"
        case .highpass: return "High Pass"
        case .bandpass: return "Band Pass"
        case .notch: return "Notch"
        case .peak: return "Peak"
        case .lowShelf: return "Low Shelf"
        case .highShelf: return "High Shelf"
        case .allpass: return "All Pass"
        }
    }
}

/// Filter topology selection
enum FilterTopology: Int, Codable, CaseIterable, Sendable {
    case biquad = 0
    case svf = 1

    var displayName: String {
        switch self {
        case .biquad: return "Biquad"
        case .svf: return "SVF"
        }
    }

    var description: String {
        switch self {
        case .biquad: return "Classic biquad filter"
        case .svf: return "State Variable Filter - better HF response"
        }
    }
}

/// Cytomic/Andrew Simper State Variable Filter implementation
/// Superior high-frequency behavior and more stable modulation compared to biquads
/// Reference: https://cytomic.com/files/dsp/SvfLinearTrapOptimised2.pdf
final class StateVariableFilter: @unchecked Sendable {
    // Internal state (integrator states)
    private var ic1eq: Float = 0  // First integrator state
    private var ic2eq: Float = 0  // Second integrator state

    // Coefficients
    private var g: Float = 0      // Frequency coefficient (tan of half-angle)
    private var k: Float = 0      // Damping (1/Q)
    private var a1: Float = 0
    private var a2: Float = 0
    private var a3: Float = 0

    // Mixing coefficients for different output modes
    private var m0: Float = 0
    private var m1: Float = 0
    private var m2: Float = 0

    // Current parameters
    private var currentMode: SVFMode = .lowpass
    private var currentFreq: Float = 1000
    private var currentQ: Float = 0.707
    private var currentGainDb: Float = 0
    private let sampleRate: Float

    // Parameter smoothing
    private var targetFreq: Float = 1000
    private var targetQ: Float = 0.707
    private var targetGainDb: Float = 0
    private var targetMode: SVFMode = .lowpass
    private var smoothingCounter: Int = 0
    private let smoothingSamples: Int
    private let recalcInterval: Int = 32
    private var recalcCounter: Int = 0

    // Thread-safety
    private var paramsLock = os_unfair_lock()

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        self.smoothingSamples = Int(sampleRate * 0.005)  // 5ms smoothing
        updateCoefficients(mode: .lowpass, frequency: 1000, q: 0.707, gainDb: 0)
    }

    // MARK: - Parameter Updates

    /// Update filter parameters with smoothing
    func setParameters(mode: SVFMode, frequency: Float, q: Float, gainDb: Float = 0) {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }

        // If already smoothing, snap to current interpolated position
        if smoothingCounter > 0 {
            let factor = 1.0 - Float(smoothingCounter) / Float(smoothingSamples)

            let logCurrent = log(max(currentFreq, 1.0))
            let logTarget = log(max(targetFreq, 1.0))
            currentFreq = exp(logCurrent + (logTarget - logCurrent) * factor)

            currentGainDb = currentGainDb + (targetGainDb - currentGainDb) * factor

            let safeCurrentQ = max(currentQ, 0.01)
            let safeTargetQ = max(targetQ, 0.01)
            currentQ = exp(log(safeCurrentQ) + (log(safeTargetQ) - log(safeCurrentQ)) * factor)

            currentMode = targetMode
        }

        targetMode = mode
        targetFreq = frequency
        targetQ = q
        targetGainDb = gainDb
        smoothingCounter = smoothingSamples
        recalcCounter = 0
    }

    /// Set parameters immediately without smoothing
    func setParametersImmediate(mode: SVFMode, frequency: Float, q: Float, gainDb: Float = 0) {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }

        currentMode = mode
        currentFreq = frequency
        currentQ = q
        currentGainDb = gainDb
        targetMode = mode
        targetFreq = frequency
        targetQ = q
        targetGainDb = gainDb
        smoothingCounter = 0

        updateCoefficients(mode: mode, frequency: frequency, q: q, gainDb: gainDb)
    }

    // MARK: - Coefficient Calculation

    /// Update SVF coefficients based on Cytomic formulas
    private func updateCoefficients(mode: SVFMode, frequency: Float, q: Float, gainDb: Float) {
        // Clamp frequency to safe range
        let nyquist = sampleRate / 2.0
        let clampedFreq = min(max(frequency, 20), nyquist * 0.99)

        // Pre-warp frequency using tan for accurate response
        // g = tan(pi * freq / sampleRate)
        g = tan(Float.pi * clampedFreq / sampleRate)

        // k is the damping coefficient (1/Q)
        k = 1.0 / max(q, 0.01)

        // Common denominators
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2

        // Calculate mixing coefficients based on mode
        let A = powf(10.0, gainDb / 40.0)  // For peak/shelf modes

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
            // Peak EQ: boost/cut at center frequency
            // For boost: increase bandpass, for cut: decrease
            let peakGain = A * A  // Squared for proper dB scaling
            m0 = 1
            m1 = k * (peakGain - 1)
            m2 = 0

        case .lowShelf:
            // Low shelf using modified SVF approach
            // Adjust g for shelf corner frequency
            let gShelf = g / sqrt(A)
            let kShelf = k

            // Recalculate with shelf-adjusted g
            let a1Shelf = 1.0 / (1.0 + gShelf * (gShelf + kShelf))
            let a2Shelf = gShelf * a1Shelf

            // Store for use in processing (we'll handle this specially)
            a1 = a1Shelf
            a2 = a2Shelf
            a3 = gShelf * a2Shelf

            // Shelf mixing coefficients
            m0 = 1
            m1 = kShelf * (A - 1)
            m2 = A * A - 1

        case .highShelf:
            // High shelf using modified SVF approach
            let gShelf = g * sqrt(A)
            let kShelf = k

            let a1Shelf = 1.0 / (1.0 + gShelf * (gShelf + kShelf))
            let a2Shelf = gShelf * a1Shelf

            a1 = a1Shelf
            a2 = a2Shelf
            a3 = gShelf * a2Shelf

            // Shelf mixing coefficients
            m0 = A * A
            m1 = kShelf * (1 - A) * A
            m2 = 1 - A * A

        case .allpass:
            m0 = 1
            m1 = -2 * k
            m2 = 0
        }
    }

    // MARK: - Processing

    @inline(__always)
    func process(_ input: Float) -> Float {
        // Handle parameter smoothing
        os_unfair_lock_lock(&paramsLock)

        if smoothingCounter > 0 {
            recalcCounter -= 1
            if recalcCounter <= 0 {
                let factor = 1.0 - Float(smoothingCounter) / Float(smoothingSamples)

                // Logarithmic frequency interpolation
                let logCurrent = log(currentFreq)
                let logTarget = log(targetFreq)
                let interpFreq = exp(logCurrent + (logTarget - logCurrent) * factor)

                // Linear gain interpolation
                let interpGain = currentGainDb + (targetGainDb - currentGainDb) * factor

                // Logarithmic Q interpolation
                let safeCurrentQ = max(currentQ, 0.01)
                let safeTargetQ = max(targetQ, 0.01)
                let interpQ = exp(log(safeCurrentQ) + (log(safeTargetQ) - log(safeCurrentQ)) * factor)

                updateCoefficients(mode: targetMode, frequency: interpFreq, q: interpQ, gainDb: interpGain)
                recalcCounter = recalcInterval
            }

            smoothingCounter -= 1

            if smoothingCounter == 0 {
                currentMode = targetMode
                currentFreq = targetFreq
                currentQ = targetQ
                currentGainDb = targetGainDb
                updateCoefficients(mode: currentMode, frequency: currentFreq, q: currentQ, gainDb: currentGainDb)
            }
        }

        // Copy coefficients to local variables while holding lock
        let localA1 = a1
        let localA2 = a2
        let localA3 = a3
        let localM0 = m0
        let localM1 = m1
        let localM2 = m2

        os_unfair_lock_unlock(&paramsLock)

        // SVF processing (Cytomic topology)
        // v3 = input - ic2eq
        // v1 = a1 * ic1eq + a2 * v3
        // v2 = ic2eq + a2 * ic1eq + a3 * v3
        let v3 = input - ic2eq
        let v1 = localA1 * ic1eq + localA2 * v3
        let v2 = ic2eq + localA2 * ic1eq + localA3 * v3

        // Update integrator states
        ic1eq = 2 * v1 - ic1eq
        ic2eq = 2 * v2 - ic2eq

        ic1eq = flushDenormals(ic1eq)
        ic2eq = flushDenormals(ic2eq)

        // Mix outputs based on mode
        // v1 = bandpass, v2 = lowpass
        // highpass = input - k*v1 - v2
        let output = localM0 * input + localM1 * v1 + localM2 * v2

        return output
    }

    func reset() {
        os_unfair_lock_lock(&paramsLock)
        ic1eq = 0
        ic2eq = 0
        smoothingCounter = 0
        currentFreq = targetFreq
        currentQ = targetQ
        currentGainDb = targetGainDb
        currentMode = targetMode
        updateCoefficients(mode: currentMode, frequency: currentFreq, q: currentQ, gainDb: currentGainDb)
        os_unfair_lock_unlock(&paramsLock)
    }

    var isSmoothing: Bool {
        smoothingCounter > 0
    }

    // MARK: - Frequency Response

    /// Calculate magnitude response at a given frequency
    func magnitudeAt(frequency: Float) -> Float {
        // Approximate SVF frequency response using analog prototype
        let kVal = 1.0 / max(currentQ, 0.01)
        let freqRatio = frequency / max(currentFreq, 1.0)

        switch currentMode {
        case .lowpass:
            // Second-order lowpass response
            let s2 = freqRatio * freqRatio
            let denom = sqrt((1 - s2) * (1 - s2) + (kVal * freqRatio) * (kVal * freqRatio))
            return 1.0 / max(denom, 1e-10)

        case .highpass:
            let s2 = freqRatio * freqRatio
            let denom = sqrt((1 - s2) * (1 - s2) + (kVal * freqRatio) * (kVal * freqRatio))
            return s2 / max(denom, 1e-10)

        case .bandpass:
            let s2 = freqRatio * freqRatio
            let denom = sqrt((1 - s2) * (1 - s2) + (kVal * freqRatio) * (kVal * freqRatio))
            return (kVal * freqRatio) / max(denom, 1e-10)

        case .notch:
            let s2 = freqRatio * freqRatio
            let num = sqrt((1 - s2) * (1 - s2))
            let denom = sqrt((1 - s2) * (1 - s2) + (kVal * freqRatio) * (kVal * freqRatio))
            return num / max(denom, 1e-10)

        case .peak:
            let A = powf(10.0, currentGainDb / 40.0)
            let s2 = freqRatio * freqRatio
            let baseResponse = (kVal * freqRatio) / sqrt((1 - s2) * (1 - s2) + (kVal * freqRatio) * (kVal * freqRatio))
            return 1.0 + (A * A - 1) * baseResponse

        case .lowShelf, .highShelf:
            let A = powf(10.0, currentGainDb / 40.0)
            // Simplified shelf response
            if currentMode == .lowShelf {
                if frequency < currentFreq * 0.5 {
                    return A
                } else if frequency > currentFreq * 2 {
                    return 1.0
                }
            } else {
                if frequency > currentFreq * 2 {
                    return A
                } else if frequency < currentFreq * 0.5 {
                    return 1.0
                }
            }
            // Transition region
            let logRatio = log(freqRatio) / log(2.0)
            let blend = ((logRatio + 1) / 2).clamped(to: 0...1)
            return currentMode == .lowShelf
                ? A * (1 - blend) + blend
                : (1 - blend) + A * blend

        case .allpass:
            return 1.0
        }
    }
}
