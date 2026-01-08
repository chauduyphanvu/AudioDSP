import Foundation

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
