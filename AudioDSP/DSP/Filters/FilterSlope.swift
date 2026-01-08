import Foundation

/// Filter slope options for LP/HP filters
enum FilterSlope: Int, Codable, CaseIterable, Sendable {
    case slope6dB = 1   // 1-pole (6dB/oct)
    case slope12dB = 2  // 1 biquad (12dB/oct)
    case slope18dB = 3  // 1 biquad + 1-pole (18dB/oct)
    case slope24dB = 4  // 2 cascaded biquads (24dB/oct)

    var displayName: String {
        switch self {
        case .slope6dB: return "6 dB/oct"
        case .slope12dB: return "12 dB/oct"
        case .slope18dB: return "18 dB/oct"
        case .slope24dB: return "24 dB/oct"
        }
    }

    var stageCount: Int { rawValue }

    /// Returns true if slope applies to the given band type
    static func appliesTo(_ bandType: BandType) -> Bool {
        bandType == .lowPass || bandType == .highPass
    }
}
