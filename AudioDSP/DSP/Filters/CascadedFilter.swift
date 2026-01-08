import Foundation
import os

/// Butterworth Q values for maximally flat passband response
private enum ButterworthQ {
    /// 3rd order Butterworth Q for biquad section
    static let thirdOrder: Float = 1.0
    /// 4th order Butterworth Q values (Q1, Q2)
    static let fourthOrderQ1: Float = 0.541
    static let fourthOrderQ2: Float = 1.307
}

/// Cascaded filter for steeper slopes (18dB/oct, 24dB/oct)
/// Chains multiple filter stages to achieve higher-order responses
final class CascadedFilter: @unchecked Sendable {
    private var stages: [Biquad]
    private let slope: FilterSlope
    private let sampleRate: Float
    private var _isHighPass: Bool = false
    private var paramsLock = os_unfair_lock()

    private var isHighPass: Bool {
        get {
            os_unfair_lock_lock(&paramsLock)
            defer { os_unfair_lock_unlock(&paramsLock) }
            return _isHighPass
        }
        set {
            os_unfair_lock_lock(&paramsLock)
            defer { os_unfair_lock_unlock(&paramsLock) }
            _isHighPass = newValue
        }
    }

    init(slope: FilterSlope, sampleRate: Float) {
        self.slope = slope
        self.sampleRate = sampleRate

        // Create filter stages based on slope
        switch slope {
        case .slope6dB:
            // Single 1-pole filter
            stages = [Biquad(sampleRate: sampleRate)]
        case .slope12dB:
            // Single biquad (standard)
            stages = [Biquad(sampleRate: sampleRate)]
        case .slope18dB:
            // One biquad + one 1-pole
            stages = [
                Biquad(sampleRate: sampleRate),
                Biquad(sampleRate: sampleRate)
            ]
        case .slope24dB:
            // Two cascaded biquads
            stages = [
                Biquad(sampleRate: sampleRate),
                Biquad(sampleRate: sampleRate)
            ]
        }
    }

    /// Update filter parameters for all stages
    /// Uses Butterworth Q distribution for maximally flat passband
    func updateParameters(frequency: Float, q: Float, isHighPass: Bool) {
        self.isHighPass = isHighPass

        switch slope {
        case .slope6dB:
            // Single 1-pole
            let filterType: BiquadFilterType = isHighPass ? .highPass1Pole : .lowPass1Pole
            stages[0].updateParameters(BiquadParams(
                filterType: filterType,
                frequency: frequency,
                q: q,
                gainDb: 0
            ))

        case .slope12dB:
            // Single biquad with user Q
            let filterType: BiquadFilterType = isHighPass ? .highPass : .lowPass
            stages[0].updateParameters(BiquadParams(
                filterType: filterType,
                frequency: frequency,
                q: q,
                gainDb: 0
            ))

        case .slope18dB:
            // First stage: biquad with Butterworth Q
            // Second stage: 1-pole
            let filterType2p: BiquadFilterType = isHighPass ? .highPass : .lowPass
            let filterType1p: BiquadFilterType = isHighPass ? .highPass1Pole : .lowPass1Pole

            // For 3rd order Butterworth, use Q = 1.0 for the biquad section
            stages[0].updateParameters(BiquadParams(
                filterType: filterType2p,
                frequency: frequency,
                q: ButterworthQ.thirdOrder,
                gainDb: 0
            ))
            stages[1].updateParameters(BiquadParams(
                filterType: filterType1p,
                frequency: frequency,
                q: q,  // Q doesn't apply to 1-pole
                gainDb: 0
            ))

        case .slope24dB:
            // Two cascaded biquads with Butterworth Q values
            let filterType: BiquadFilterType = isHighPass ? .highPass : .lowPass

            stages[0].updateParameters(BiquadParams(
                filterType: filterType,
                frequency: frequency,
                q: ButterworthQ.fourthOrderQ1,
                gainDb: 0
            ))
            stages[1].updateParameters(BiquadParams(
                filterType: filterType,
                frequency: frequency,
                q: ButterworthQ.fourthOrderQ2,
                gainDb: 0
            ))
        }
    }

    /// Set parameters immediately without smoothing
    func setParametersImmediate(frequency: Float, q: Float, isHighPass: Bool) {
        self.isHighPass = isHighPass

        switch slope {
        case .slope6dB:
            let filterType: BiquadFilterType = isHighPass ? .highPass1Pole : .lowPass1Pole
            stages[0].setParametersImmediate(BiquadParams(
                filterType: filterType,
                frequency: frequency,
                q: q,
                gainDb: 0
            ))

        case .slope12dB:
            let filterType: BiquadFilterType = isHighPass ? .highPass : .lowPass
            stages[0].setParametersImmediate(BiquadParams(
                filterType: filterType,
                frequency: frequency,
                q: q,
                gainDb: 0
            ))

        case .slope18dB:
            let filterType2p: BiquadFilterType = isHighPass ? .highPass : .lowPass
            let filterType1p: BiquadFilterType = isHighPass ? .highPass1Pole : .lowPass1Pole

            stages[0].setParametersImmediate(BiquadParams(
                filterType: filterType2p,
                frequency: frequency,
                q: ButterworthQ.thirdOrder,
                gainDb: 0
            ))
            stages[1].setParametersImmediate(BiquadParams(
                filterType: filterType1p,
                frequency: frequency,
                q: q,
                gainDb: 0
            ))

        case .slope24dB:
            let filterType: BiquadFilterType = isHighPass ? .highPass : .lowPass
            stages[0].setParametersImmediate(BiquadParams(
                filterType: filterType,
                frequency: frequency,
                q: ButterworthQ.fourthOrderQ1,
                gainDb: 0
            ))
            stages[1].setParametersImmediate(BiquadParams(
                filterType: filterType,
                frequency: frequency,
                q: ButterworthQ.fourthOrderQ2,
                gainDb: 0
            ))
        }
    }

    @inline(__always)
    func process(_ input: Float) -> Float {
        var output = input
        for stage in stages {
            output = stage.process(output)
        }
        return output
    }

    func reset() {
        for stage in stages {
            stage.reset()
        }
    }

    var isSmoothing: Bool {
        stages.contains { $0.isSmoothing }
    }

    /// Calculate combined magnitude response at a frequency
    func magnitudeAt(frequency: Float) -> Float {
        var magnitude: Float = 1.0

        for (index, _) in stages.enumerated() {
            let coeffs = coefficientsForStage(index, atFrequency: frequency)
            magnitude *= FrequencyResponse.magnitude(coefficients: coeffs, atFrequency: frequency, sampleRate: sampleRate)
        }

        return magnitude
    }

    private func coefficientsForStage(_ index: Int, atFrequency frequency: Float) -> BiquadCoefficients {
        switch slope {
        case .slope6dB:
            let filterType: BiquadFilterType = isHighPass ? .highPass1Pole : .lowPass1Pole
            return BiquadCoefficients.calculate(type: filterType, sampleRate: sampleRate, frequency: frequency, q: 0.707)

        case .slope12dB:
            let filterType: BiquadFilterType = isHighPass ? .highPass : .lowPass
            return BiquadCoefficients.calculate(type: filterType, sampleRate: sampleRate, frequency: frequency, q: 0.707)

        case .slope18dB:
            if index == 0 {
                let filterType: BiquadFilterType = isHighPass ? .highPass : .lowPass
                return BiquadCoefficients.calculate(type: filterType, sampleRate: sampleRate, frequency: frequency, q: ButterworthQ.thirdOrder)
            } else {
                let filterType: BiquadFilterType = isHighPass ? .highPass1Pole : .lowPass1Pole
                return BiquadCoefficients.calculate(type: filterType, sampleRate: sampleRate, frequency: frequency, q: 0.707)
            }

        case .slope24dB:
            let filterType: BiquadFilterType = isHighPass ? .highPass : .lowPass
            let q: Float = index == 0 ? ButterworthQ.fourthOrderQ1 : ButterworthQ.fourthOrderQ2
            return BiquadCoefficients.calculate(type: filterType, sampleRate: sampleRate, frequency: frequency, q: q)
        }
    }
}
