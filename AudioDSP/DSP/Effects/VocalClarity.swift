import Foundation

/// Vocal clarity enhancement using presence and air boosts
final class VocalClarity: Effect, @unchecked Sendable {
    private static let presenceFreq: Float = 3500  // Hz
    private static let presenceQ: Float = 1.0
    private static let maxPresenceGain: Float = 6  // dB

    private static let airFreq: Float = 10000      // Hz
    private static let airQ: Float = 0.707
    private static let maxAirGain: Float = 4       // dB

    private var clarity: Float = 0.5  // 0.0 - 1.0 (presence boost)
    private var air: Float = 0.25     // 0.0 - 1.0 (high-frequency shimmer)

    // Presence peak filter
    private var presenceLeft: Biquad
    private var presenceRight: Biquad

    // High-shelf for "air"
    private var airLeft: Biquad
    private var airRight: Biquad

    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    let name = "Vocal Clarity"

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate

        let presenceCoeffs = Self.presenceCoefficients(sampleRate: sampleRate, clarity: 0.5)
        presenceLeft = Biquad(coefficients: presenceCoeffs)
        presenceRight = Biquad(coefficients: presenceCoeffs)

        let airCoeffs = Self.airCoefficients(sampleRate: sampleRate, air: 0.25)
        airLeft = Biquad(coefficients: airCoeffs)
        airRight = Biquad(coefficients: airCoeffs)
    }

    private static func presenceCoefficients(sampleRate: Float, clarity: Float) -> BiquadCoefficients {
        let gainDb = clarity * maxPresenceGain
        return BiquadCoefficients.calculate(
            type: .peak(gainDb: gainDb),
            sampleRate: sampleRate,
            frequency: presenceFreq,
            q: presenceQ
        )
    }

    private static func airCoefficients(sampleRate: Float, air: Float) -> BiquadCoefficients {
        let gainDb = air * maxAirGain
        return BiquadCoefficients.calculate(
            type: .highShelf(gainDb: gainDb),
            sampleRate: sampleRate,
            frequency: airFreq,
            q: airQ
        )
    }

    private func updateFilters() {
        let presenceCoeffs = Self.presenceCoefficients(sampleRate: sampleRate, clarity: clarity)
        presenceLeft.updateCoefficients(presenceCoeffs)
        presenceRight.updateCoefficients(presenceCoeffs)

        let airCoeffs = Self.airCoefficients(sampleRate: sampleRate, air: air)
        airLeft.updateCoefficients(airCoeffs)
        airRight.updateCoefficients(airCoeffs)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Apply presence peak filter
        var l = presenceLeft.process(left)
        var r = presenceRight.process(right)

        // Apply air high-shelf filter
        l = airLeft.process(l)
        r = airRight.process(r)

        return (l, r)
    }

    func reset() {
        presenceLeft.reset()
        presenceRight.reset()
        airLeft.reset()
        airRight.reset()
    }

    var parameters: [ParameterDescriptor] {
        [
            ParameterDescriptor("Clarity", min: 0, max: 100, defaultValue: 50, unit: .percent),
            ParameterDescriptor("Air", min: 0, max: 100, defaultValue: 25, unit: .percent),
        ]
    }

    func getParameter(_ index: Int) -> Float {
        switch index {
        case 0: return clarity * 100
        case 1: return air * 100
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        switch index {
        case 0:
            clarity = min(max(value / 100, 0), 1)
            updateFilters()
        case 1:
            air = min(max(value / 100, 0), 1)
            updateFilters()
        default: break
        }
    }
}
