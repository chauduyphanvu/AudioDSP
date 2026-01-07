import Foundation

/// Parameter unit types for display formatting
enum ParameterUnit: Codable, Sendable {
    case decibels
    case hertz
    case milliseconds
    case percent
    case ratio
    case generic

    func format(_ value: Float) -> String {
        switch self {
        case .decibels:
            return String(format: "%.1f dB", value)
        case .hertz:
            if value >= 1000 {
                return String(format: "%.1f kHz", value / 1000)
            }
            return String(format: "%.0f Hz", value)
        case .milliseconds:
            return String(format: "%.0f ms", value)
        case .percent:
            return String(format: "%.0f%%", value * 100)
        case .ratio:
            return String(format: "%.1f:1", value)
        case .generic:
            return String(format: "%.2f", value)
        }
    }
}

/// Describes a single parameter for UI display and control
struct ParameterDescriptor: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let min: Float
    let max: Float
    let defaultValue: Float
    let unit: ParameterUnit

    init(_ name: String, min: Float, max: Float, defaultValue: Float, unit: ParameterUnit) {
        self.name = name
        self.min = min
        self.max = max
        self.defaultValue = defaultValue
        self.unit = unit
    }

    func format(_ value: Float) -> String {
        unit.format(value)
    }

    func clamp(_ value: Float) -> Float {
        Swift.min(Swift.max(value, min), max)
    }

    func normalize(_ value: Float) -> Float {
        (value - min) / (max - min)
    }

    func denormalize(_ normalized: Float) -> Float {
        min + normalized * (max - min)
    }
}

/// Core protocol for all audio effects
protocol Effect: AnyObject, Sendable {
    /// Process a stereo sample pair
    func process(left: Float, right: Float) -> (left: Float, right: Float)

    /// Reset internal state (clear delay lines, envelopes, etc.)
    func reset()

    /// Effect name for UI display
    var name: String { get }

    /// Current bypass state
    var isBypassed: Bool { get set }

    /// Wet/dry mix (0.0 = dry, 1.0 = wet)
    var wetDry: Float { get set }

    /// Get parameter descriptors for UI
    var parameters: [ParameterDescriptor] { get }

    /// Get parameter value by index
    func getParameter(_ index: Int) -> Float

    /// Set parameter value by index
    func setParameter(_ index: Int, value: Float)

    /// Number of parameters
    var parameterCount: Int { get }
}

extension Effect {
    var parameterCount: Int { parameters.count }
}

/// Effect type enumeration for preset serialization
enum EffectType: String, Codable, CaseIterable, Sendable {
    case gain
    case parametricEQ
    case bassEnhancer
    case vocalClarity
    case compressor
    case limiter
    case reverb
    case delay
    case stereoWidener

    var displayName: String {
        switch self {
        case .gain: return "Output Gain"
        case .parametricEQ: return "Parametric EQ"
        case .bassEnhancer: return "Bass Enhancer"
        case .vocalClarity: return "Vocal Clarity"
        case .compressor: return "Compressor"
        case .limiter: return "Limiter"
        case .reverb: return "Reverb"
        case .delay: return "Delay"
        case .stereoWidener: return "Stereo Widener"
        }
    }
}
