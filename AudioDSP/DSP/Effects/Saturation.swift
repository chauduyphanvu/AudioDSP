import Foundation

/// Saturation modes with different harmonic characters
enum SaturationMode: Int, Codable, CaseIterable, Sendable {
    case clean = 0      // Transparent tanh limiting
    case tube = 1       // Asymmetric soft clip, even harmonics
    case tape = 2       // Polynomial saturation with subtle compression
    case transistor = 3 // Harder clipping, odd harmonics

    var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .tube: return "Tube"
        case .tape: return "Tape"
        case .transistor: return "Transistor"
        }
    }

    var description: String {
        switch self {
        case .clean: return "Transparent limiting"
        case .tube: return "Warm, even harmonics"
        case .tape: return "Gentle compression"
        case .transistor: return "Punchy, odd harmonics"
        }
    }
}

/// Thread-safe saturation processor with multiple analog-modeled modes.
/// Uses 2x oversampling to prevent harmonic aliasing from nonlinearities.
final class Saturation: @unchecked Sendable {
    /// Bundled parameter state for atomic access
    private struct Params {
        var mode: SaturationMode = .clean
        var drive: Float = 0.0
        var mix: Float = 1.0
        var outputGain: Float = 0.0
    }

    private let params: ThreadSafeValue<Params>
    private let resetFlag: AtomicFlag

    // Soft clipping constants
    private let softClipThreshold: Float = 0.9
    private let softClipKnee: Float = 0.1

    // 2x oversampling state (audio thread only)
    private var oversamplePrevL: Float = 0
    private var oversamplePrevR: Float = 0
    private var downsamplePrevClipL: Float = 0
    private var downsamplePrevClipR: Float = 0

    // Tape mode HF rolloff state
    private var tapeLpStateL: Float = 0
    private var tapeLpStateR: Float = 0
    private let tapeLpCoeff: Float = 0.3

    init() {
        params = ThreadSafeValue(Params())
        resetFlag = AtomicFlag()
    }

    // MARK: - Parameter Access

    func setMode(_ newMode: SaturationMode) {
        params.modify { $0.mode = newMode }
    }

    func setDrive(_ newDrive: Float) {
        params.modify { $0.drive = max(0, min(24, newDrive)) }
    }

    func setMix(_ newMix: Float) {
        params.modify { $0.mix = max(0, min(1, newMix)) }
    }

    func setOutputGain(_ newGain: Float) {
        params.modify { $0.outputGain = max(-24, min(24, newGain)) }
    }

    func getMode() -> SaturationMode { params.read().mode }
    func getDrive() -> Float { params.read().drive }

    // MARK: - Saturation Algorithms

    /// Clean saturation - transparent tanh limiting (current implementation)
    @inline(__always)
    private func cleanSaturate(_ x: Float) -> Float {
        let threshold = softClipThreshold
        let absSample = abs(x)

        if absSample <= threshold {
            return x
        }

        let sign: Float = x >= 0 ? 1 : -1
        let excess = absSample - threshold
        let knee = softClipKnee
        let compressed = threshold + knee * tanh(excess / knee)
        return sign * min(compressed, 1.0)
    }

    /// Tube saturation - asymmetric soft clipping emphasizing even harmonics
    /// Positive and negative half-cycles are processed differently for asymmetry
    @inline(__always)
    private func tubeSaturate(_ x: Float, driveAmount: Float) -> Float {
        // Drive maps 0-24dB to 0-1 normalized drive
        let normalizedDrive = driveAmount / 24.0
        let k = 2.0 * normalizedDrive / max(1.0 - normalizedDrive, 0.01)

        // Asymmetric transfer function - softer on negative, harder on positive
        // This creates even harmonics characteristic of tube distortion
        if x >= 0 {
            let saturated = (1 + k) * x / (1 + k * abs(x))
            return min(saturated, 1.0)
        } else {
            // Softer compression on negative half-cycle
            let softerK = k * 0.7
            let saturated = (1 + softerK) * x / (1 + softerK * abs(x))
            return max(saturated, -1.0)
        }
    }

    /// Tape saturation - polynomial soft saturation with subtle compression
    /// Emulates magnetic tape's gentle limiting characteristics
    @inline(__always)
    private func tapeSaturate(_ x: Float, driveAmount: Float) -> Float {
        // Apply drive as input gain
        let driveLinear = powf(10.0, driveAmount / 20.0)
        let driven = x * min(driveLinear, 4.0)  // Cap at +12dB effective

        // Soft polynomial saturation: y = x - x^3/3 (classic cubic soft clipper)
        // This provides smooth limiting with predominantly odd harmonics
        let clipped = max(-1.5, min(1.5, driven))
        var y = clipped - (clipped * clipped * clipped) / 3.0

        // Normalize output to prevent level jump
        y *= 0.75

        return max(-1.0, min(1.0, y))
    }

    /// Transistor saturation - harder clipping with odd harmonics
    /// Emulates solid-state distortion characteristics
    @inline(__always)
    private func transistorSaturate(_ x: Float, driveAmount: Float) -> Float {
        // Apply drive as input gain
        let driveLinear = powf(10.0, driveAmount / 20.0)
        let driven = x * min(driveLinear, 4.0)

        // Hard clip with cubic soft knee for smooth transition
        let threshold: Float = 0.6
        let absDriven = abs(driven)

        if absDriven < threshold {
            return driven
        }

        let sign: Float = driven >= 0 ? 1 : -1
        let excess = absDriven - threshold

        // Sharper saturation curve than tape
        let headroom = 1.0 - threshold
        let saturated = threshold + headroom * tanh(excess * 3.0 / headroom)

        return sign * min(saturated, 1.0)
    }

    /// Apply saturation based on current mode
    @inline(__always)
    private func saturateCore(_ x: Float, currentMode: SaturationMode, driveAmount: Float) -> Float {
        switch currentMode {
        case .clean:
            return cleanSaturate(x)
        case .tube:
            return tubeSaturate(x, driveAmount: driveAmount)
        case .tape:
            return tapeSaturate(x, driveAmount: driveAmount)
        case .transistor:
            return transistorSaturate(x, driveAmount: driveAmount)
        }
    }

    // MARK: - Processing

    /// Process stereo samples with 2x oversampled saturation
    @inline(__always)
    func process(left: Float, right: Float) -> (Float, Float) {
        performResetIfNeeded()

        let p = params.read()
        let currentMode = p.mode
        let currentDrive = p.drive
        let currentMix = p.mix
        let currentOutputGain = p.outputGain

        // Fast path for clean mode with no drive
        if currentMode == .clean && currentDrive < 0.1 {
            // Just apply threshold-based clean limiting
            let maxSample = max(abs(left), abs(right))
            if maxSample <= softClipThreshold {
                oversamplePrevL = left
                oversamplePrevR = right
                downsamplePrevClipL = left
                downsamplePrevClipR = right
                return (left, right)
            }
        }

        // Store dry signal for mix
        let dryL = left
        let dryR = right

        // 2x upsample using linear interpolation
        let upL0 = (oversamplePrevL + left) * 0.5
        let upL1 = left
        let upR0 = (oversamplePrevR + right) * 0.5
        let upR1 = right

        // Apply saturation at 2x rate
        var clipL0 = saturateCore(upL0, currentMode: currentMode, driveAmount: currentDrive)
        var clipL1 = saturateCore(upL1, currentMode: currentMode, driveAmount: currentDrive)
        var clipR0 = saturateCore(upR0, currentMode: currentMode, driveAmount: currentDrive)
        var clipR1 = saturateCore(upR1, currentMode: currentMode, driveAmount: currentDrive)

        // Tape mode: apply subtle HF rolloff (one-pole lowpass on oversampled signal)
        if currentMode == .tape {
            tapeLpStateL = tapeLpStateL + tapeLpCoeff * (clipL1 - tapeLpStateL)
            tapeLpStateR = tapeLpStateR + tapeLpCoeff * (clipR1 - tapeLpStateR)
            // Blend in some of the filtered signal
            clipL0 = clipL0 * 0.9 + tapeLpStateL * 0.1
            clipL1 = clipL1 * 0.9 + tapeLpStateL * 0.1
            clipR0 = clipR0 * 0.9 + tapeLpStateR * 0.1
            clipR1 = clipR1 * 0.9 + tapeLpStateR * 0.1
        }

        // Store for next interpolation
        oversamplePrevL = left
        oversamplePrevR = right

        // 3-tap downsample filter [0.25, 0.5, 0.25]
        var outL = 0.25 * downsamplePrevClipL + 0.5 * clipL0 + 0.25 * clipL1
        var outR = 0.25 * downsamplePrevClipR + 0.5 * clipR0 + 0.25 * clipR1

        // Store clipped samples for next iteration
        downsamplePrevClipL = clipL1
        downsamplePrevClipR = clipR1

        // Apply output gain compensation
        if currentOutputGain != 0 {
            let gainLinear = powf(10.0, currentOutputGain / 20.0)
            outL *= gainLinear
            outR *= gainLinear
        }

        // Apply wet/dry mix
        if currentMix < 1.0 {
            outL = dryL * (1.0 - currentMix) + outL * currentMix
            outR = dryR * (1.0 - currentMix) + outR * currentMix
        }

        return (outL, outR)
    }

    func reset() {
        resetFlag.set()
    }

    @inline(__always)
    private func performResetIfNeeded() {
        guard resetFlag.testAndClear() else { return }
        oversamplePrevL = 0
        oversamplePrevR = 0
        downsamplePrevClipL = 0
        downsamplePrevClipR = 0
        tapeLpStateL = 0
        tapeLpStateR = 0
    }
}
