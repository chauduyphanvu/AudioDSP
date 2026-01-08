import Foundation

/// Simple output gain control
final class Gain: Effect, @unchecked Sendable {
    private var gainDb: Float = 0
    private var gainLinear: Float = 1
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    let name = "Output Gain"

    init() {}

    init(gainDb: Float) {
        setGainDb(gainDb)
    }

    private func setGainDb(_ db: Float) {
        self.gainDb = db
        self.gainLinear = dbToLinear(db)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        (left * gainLinear, right * gainLinear)
    }

    func reset() {
        // No state to reset
    }

    var parameters: [ParameterDescriptor] {
        [
            ParameterDescriptor("Gain", min: -24, max: 24, defaultValue: 0, unit: .decibels),
        ]
    }

    func getParameter(_ index: Int) -> Float {
        switch index {
        case 0: return gainDb
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        if index == 0 {
            setGainDb(value.clamped(to: -24...24))
        }
    }
}
