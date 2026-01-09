import Foundation

/// Filter topology selection for choosing between filter implementations
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
