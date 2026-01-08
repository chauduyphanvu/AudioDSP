import Foundation

/// EQ band state for UI binding
struct EQBandState: Equatable, Codable {
    var frequency: Float
    var gainDb: Float
    var q: Float
    var bandType: BandType
    var solo: Bool = false
    var enabled: Bool = true

    // Advanced features
    var slope: FilterSlope = .slope12dB
    var topology: FilterTopology = .biquad
    var msMode: MSMode = .stereo

    // Dynamic EQ
    var dynamicsEnabled: Bool = false
    var dynamicsThreshold: Float = -12
    var dynamicsRatio: Float = 2.0
    var dynamicsAttack: Float = 10
    var dynamicsRelease: Float = 100

    /// Bandwidth in octaves (derived from Q)
    var bandwidthOctaves: Float {
        QBandwidthConverter.qToOctaves(q)
    }

    /// Format Q with optional bandwidth display
    func formatQ(showBandwidth: Bool = false) -> String {
        if showBandwidth {
            return String(format: "%.2f (%.1f oct)", q, bandwidthOctaves)
        }
        return String(format: "%.2f", q)
    }

    /// Returns true if slope control is applicable for this band type
    var slopeApplicable: Bool {
        FilterSlope.appliesTo(bandType)
    }
}

// MARK: - Default EQ Bands

extension EQBandState {
    /// Default 5-band EQ configuration
    static var defaultBands: [EQBandState] {
        [
            EQBandState(frequency: 80, gainDb: 0, q: 0.707, bandType: .lowShelf),
            EQBandState(frequency: 250, gainDb: 0, q: 1.0, bandType: .peak),
            EQBandState(frequency: 1000, gainDb: 0, q: 1.0, bandType: .peak),
            EQBandState(frequency: 4000, gainDb: 0, q: 1.0, bandType: .peak),
            EQBandState(frequency: 12000, gainDb: 0, q: 0.707, bandType: .highShelf),
        ]
    }
}
