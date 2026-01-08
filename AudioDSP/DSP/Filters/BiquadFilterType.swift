import Foundation

/// Filter type for biquad coefficient calculation
enum BiquadFilterType: Sendable {
    case lowShelf(gainDb: Float)
    case highShelf(gainDb: Float)
    case peak(gainDb: Float)
    case lowPass
    case highPass
    case allPass
    case lowPass1Pole   // 6dB/oct single-pole lowpass
    case highPass1Pole  // 6dB/oct single-pole highpass

    /// Returns a copy of this filter type with the specified gain value
    /// For filter types without gain (lowPass, highPass, etc.), returns self unchanged
    func withGain(_ gainDb: Float) -> BiquadFilterType {
        switch self {
        case .peak: return .peak(gainDb: gainDb)
        case .lowShelf: return .lowShelf(gainDb: gainDb)
        case .highShelf: return .highShelf(gainDb: gainDb)
        case .lowPass, .highPass, .allPass, .lowPass1Pole, .highPass1Pole:
            return self
        }
    }
}
