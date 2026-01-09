import Foundation

/// SVF filter modes representing different frequency response characteristics
enum SVFMode: Int, Codable, CaseIterable, Sendable {
    case lowpass = 0
    case highpass = 1
    case bandpass = 2
    case notch = 3
    case peak = 4
    case lowShelf = 5
    case highShelf = 6
    case allpass = 7

    var displayName: String {
        switch self {
        case .lowpass: return "Low Pass"
        case .highpass: return "High Pass"
        case .bandpass: return "Band Pass"
        case .notch: return "Notch"
        case .peak: return "Peak"
        case .lowShelf: return "Low Shelf"
        case .highShelf: return "High Shelf"
        case .allpass: return "All Pass"
        }
    }
}
