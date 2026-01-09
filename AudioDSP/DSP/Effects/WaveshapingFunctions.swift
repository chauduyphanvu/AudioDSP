import Foundation

/// Collection of waveshaping functions for saturation processing.
/// Each function implements a different analog-modeled saturation characteristic.
/// All functions are designed to be inlined for real-time audio performance.
enum WaveshapingFunctions {

    // MARK: - Clean Saturation

    /// Clean saturation - transparent tanh limiting
    /// Applies soft clipping above threshold with smooth knee transition.
    /// - Parameters:
    ///   - x: Input sample
    ///   - threshold: Level above which saturation begins (typically 0.9)
    ///   - knee: Width of the soft knee region (typically 0.1)
    /// - Returns: Saturated sample
    @inline(__always)
    static func clean(_ x: Float, threshold: Float, knee: Float) -> Float {
        let absSample = abs(x)

        if absSample <= threshold {
            return x
        }

        let sign: Float = x >= 0 ? 1 : -1
        let excess = absSample - threshold
        let compressed = threshold + knee * tanh(excess / knee)
        return sign * min(compressed, 1.0)
    }

    // MARK: - Tube Saturation

    /// Tube saturation - asymmetric soft clipping emphasizing even harmonics
    /// Positive and negative half-cycles are processed differently for asymmetry.
    /// - Parameters:
    ///   - x: Input sample
    ///   - driveAmount: Drive in dB (0-24)
    /// - Returns: Saturated sample with even harmonic content
    @inline(__always)
    static func tube(_ x: Float, driveAmount: Float) -> Float {
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

    // MARK: - Tape Saturation

    /// Tape saturation - polynomial soft saturation with subtle compression
    /// Emulates magnetic tape's gentle limiting characteristics.
    /// - Parameters:
    ///   - x: Input sample
    ///   - driveAmount: Drive in dB (0-24)
    /// - Returns: Saturated sample with tape-like character
    @inline(__always)
    static func tape(_ x: Float, driveAmount: Float) -> Float {
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

    // MARK: - Transistor Saturation

    /// Transistor saturation - harder clipping with odd harmonics
    /// Emulates solid-state distortion characteristics.
    /// - Parameters:
    ///   - x: Input sample
    ///   - driveAmount: Drive in dB (0-24)
    /// - Returns: Saturated sample with transistor-like character
    @inline(__always)
    static func transistor(_ x: Float, driveAmount: Float) -> Float {
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

    // MARK: - Mode Dispatcher

    /// Apply saturation based on mode selection
    /// - Parameters:
    ///   - x: Input sample
    ///   - mode: Saturation mode to apply
    ///   - driveAmount: Drive amount in dB
    ///   - threshold: Clean mode threshold
    ///   - knee: Clean mode knee width
    /// - Returns: Saturated sample
    @inline(__always)
    static func saturate(
        _ x: Float,
        mode: SaturationMode,
        driveAmount: Float,
        threshold: Float = 0.9,
        knee: Float = 0.1
    ) -> Float {
        switch mode {
        case .clean:
            return clean(x, threshold: threshold, knee: knee)
        case .tube:
            return tube(x, driveAmount: driveAmount)
        case .tape:
            return tape(x, driveAmount: driveAmount)
        case .transistor:
            return transistor(x, driveAmount: driveAmount)
        }
    }
}
