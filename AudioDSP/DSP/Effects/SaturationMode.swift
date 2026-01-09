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
