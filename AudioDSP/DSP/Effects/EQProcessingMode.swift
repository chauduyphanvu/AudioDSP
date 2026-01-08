import Foundation

/// EQ processing mode for selecting between minimum and linear phase processing
enum EQProcessingMode: Int, Codable, CaseIterable, Sendable {
    case minimumPhase = 0
    case linearPhase = 1

    var displayName: String {
        switch self {
        case .minimumPhase: return "Minimum Phase"
        case .linearPhase: return "Linear Phase"
        }
    }

    var description: String {
        switch self {
        case .minimumPhase: return "Low latency, natural phase response"
        case .linearPhase: return "Zero phase distortion, ~43ms latency"
        }
    }
}
