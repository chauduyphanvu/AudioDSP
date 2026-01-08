import Foundation

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

    /// Returns the appropriate Q range for this filter type
    /// Shelves work well with 0.5-2.0, peaks/resonant with 0.3-10
    var qRange: ClosedRange<Float> {
        switch self {
        case .lowShelf, .highShelf:
            return 0.5...2.0
        case .peak, .lowPass, .highPass:
            return 0.3...10.0
        }
    }

    /// Returns the default Q value for this filter type
    var defaultQ: Float {
        switch self {
        case .lowShelf, .highShelf:
            return 0.707  // Butterworth Q for flat response
        case .peak:
            return 1.0
        case .lowPass, .highPass:
            return 0.707  // Butterworth Q
        }
    }
}
