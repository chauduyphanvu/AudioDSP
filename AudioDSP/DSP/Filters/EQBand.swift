import Foundation

/// Thread-safe parameter block for EQ band
/// Used for parameter updates between UI and audio threads
struct EQBandParams: Sendable {
    var bandType: BandType
    var frequency: Float
    var gainDb: Float
    var q: Float
    var solo: Bool

    init(bandType: BandType = .peak, frequency: Float = 1000, gainDb: Float = 0, q: Float = 1.0, solo: Bool = false) {
        self.bandType = bandType
        self.frequency = frequency
        self.gainDb = gainDb
        self.q = q
        self.solo = solo
    }
}

/// Single EQ band with stereo processing and thread-safe parameter updates.
/// Simplified version of ExtendedEQBand for basic use cases.
final class EQBand: @unchecked Sendable {
    private var filterLeft: Biquad
    private var filterRight: Biquad
    private let sampleRate: Float

    private let params: ThreadSafeValue<EQBandParams>
    private let enabledFlag: AtomicBool

    var enabled: Bool { enabledFlag.value }
    var bandType: BandType { params.read().bandType }
    var frequency: Float { params.read().frequency }
    var gainDb: Float { params.read().gainDb }
    var q: Float { params.read().q }
    var solo: Bool { params.read().solo }

    init(sampleRate: Float, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        self.sampleRate = sampleRate
        self.params = ThreadSafeValue(EQBandParams(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q))
        self.enabledFlag = AtomicBool(true)

        let biquadParams = BiquadParams(
            filterType: bandType.toBiquadType(gainDb: gainDb),
            frequency: frequency,
            q: q,
            gainDb: gainDb
        )
        self.filterLeft = Biquad(params: biquadParams, sampleRate: sampleRate)
        self.filterRight = Biquad(params: biquadParams, sampleRate: sampleRate)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        guard enabledFlag.value else { return (left, right) }
        return (filterLeft.process(left), filterRight.process(right))
    }

    func update(bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        params.modify { p in
            p = EQBandParams(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q, solo: p.solo)
        }

        let biquadParams = BiquadParams(
            filterType: bandType.toBiquadType(gainDb: gainDb),
            frequency: frequency,
            q: q,
            gainDb: gainDb
        )
        filterLeft.updateParameters(biquadParams)
        filterRight.updateParameters(biquadParams)
    }

    func setSolo(_ solo: Bool) {
        params.modify { p in
            p = EQBandParams(bandType: p.bandType, frequency: p.frequency, gainDb: p.gainDb, q: p.q, solo: solo)
        }
    }

    func setEnabled(_ enabled: Bool) {
        enabledFlag.value = enabled
        if enabled {
            filterLeft.reset()
            filterRight.reset()
        }
    }

    func reset() {
        filterLeft.reset()
        filterRight.reset()
    }
}
