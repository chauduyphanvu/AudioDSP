import Foundation

/// Proportional Q calculation for analog-style EQ behavior.
///
/// Classic analog EQs (Pultec, Neve, API) exhibit gain-dependent Q behavior:
/// - Higher boost gains create narrower bandwidth (higher Q)
/// - Cuts tend to be wider and more gentle
///
/// This creates a more musical, less surgical character compared to
/// constant-Q digital EQs.
enum ProportionalQ {
    /// Default strength factor for subtle analog character
    static let defaultStrength: Float = 0.08

    /// Safe Q range to prevent filter instability
    static let minQ: Float = 0.1
    static let maxQ: Float = 50.0

    /// Calculate effective Q based on gain for analog-style behavior.
    ///
    /// - Parameters:
    ///   - baseQ: The user-specified Q value
    ///   - gainDb: Current gain in dB (positive for boost, negative for cut)
    ///   - strength: How much gain affects Q (0 = disabled, 0.08 = subtle, 0.15 = aggressive)
    ///   - bandType: Filter type (only peak filters use proportional Q)
    /// - Returns: Effective Q value clamped to safe range (0.1-50)
    static func calculate(
        baseQ: Float,
        gainDb: Float,
        strength: Float,
        bandType: BandType
    ) -> Float {
        // Only apply to peak filters - shelves have different characteristics
        guard bandType == .peak, strength > 0, abs(gainDb) > 0.1 else {
            return baseQ
        }

        let absGain = abs(gainDb)
        let effectiveQ: Float

        if gainDb > 0 {
            // Boost: increase Q (narrower bandwidth)
            // This mimics inductor-based EQs where the resonant peak sharpens with gain
            let qMultiplier = 1.0 + absGain * strength
            effectiveQ = baseQ * qMultiplier
        } else {
            // Cut: decrease Q slightly (wider bandwidth)
            // Analog cuts tend to be gentler and wider than boosts
            // Using a softer factor (0.5x strength) for cuts
            let qDivisor = 1.0 + absGain * strength * 0.5
            effectiveQ = baseQ / qDivisor
        }

        // Clamp to safe range to prevent filter instability
        return min(max(effectiveQ, minQ), maxQ)
    }

    /// Calculate effective Q with asymmetric boost/cut behavior.
    ///
    /// Some vintage EQs have dramatically different Q for boost vs cut.
    /// This version allows independent control.
    ///
    /// - Parameters:
    ///   - baseQ: The user-specified Q value
    ///   - gainDb: Current gain in dB
    ///   - boostStrength: Strength factor for boosts (0-0.2 typical, negative values treated as 0)
    ///   - cutStrength: Strength factor for cuts (0-0.1 typical, negative values treated as 0)
    ///   - bandType: Filter type
    /// - Returns: Effective Q value clamped to safe range (0.1-50)
    static func calculateAsymmetric(
        baseQ: Float,
        gainDb: Float,
        boostStrength: Float,
        cutStrength: Float,
        bandType: BandType
    ) -> Float {
        guard bandType == .peak, abs(gainDb) > 0.1 else {
            return baseQ
        }

        let absGain = abs(gainDb)
        // Clamp negative strengths to 0 to prevent division issues
        let safeBoostStrength = max(0, boostStrength)
        let safeCutStrength = max(0, cutStrength)

        let effectiveQ: Float
        if gainDb > 0 {
            effectiveQ = baseQ * (1.0 + absGain * safeBoostStrength)
        } else {
            effectiveQ = baseQ / (1.0 + absGain * safeCutStrength)
        }

        return min(max(effectiveQ, minQ), maxQ)
    }
}
