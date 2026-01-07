import Foundation

/// Bass enhancement using harmonic saturation and psychoacoustic processing
/// Adds upper harmonics to low frequencies, making bass more audible on small speakers
final class BassEnhancer: Effect, @unchecked Sendable {
    private var amount: Float = 0.5    // 0.0 - 1.0 (overall intensity)
    private var lowFreq: Float = 100   // Hz (cutoff for bass extraction)
    private var harmonics: Float = 0.3 // 0.0 - 1.0 (saturation amount)

    // 2nd-order Butterworth low-pass filter state (12 dB/oct for better bass isolation)
    private var lp1StateL: Float = 0
    private var lp1StateR: Float = 0
    private var lp2StateL: Float = 0
    private var lp2StateR: Float = 0
    private var lpCoeff: Float = 0

    // DC blocking high-pass filter state (removes DC offset from saturation)
    private var dcStateL: Float = 0
    private var dcStateR: Float = 0
    private var dcPrevInL: Float = 0
    private var dcPrevInR: Float = 0
    private let dcCoeff: Float  // ~20Hz high-pass

    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    let name = "Bass Enhancer"

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        // DC blocker coefficient for ~20Hz cutoff (clamped for low sample rates)
        self.dcCoeff = max(0.9, 1.0 - (Float.pi * 2.0 * 20.0 / sampleRate))
        updateFilter()
    }

    private func updateFilter() {
        // One-pole low-pass coefficient (cascaded twice for 2nd order)
        let omega = 2.0 * Float.pi * lowFreq / sampleRate
        lpCoeff = exp(-omega)
    }

    /// Soft saturation using tanh - generates odd harmonics (3rd, 5th, etc.)
    @inline(__always)
    private func saturate(_ x: Float, drive: Float) -> Float {
        tanh(x * (1.0 + drive * 3.0))
    }

    /// DC blocking filter to remove offset introduced by saturation
    @inline(__always)
    private func dcBlock(input: Float, prevIn: inout Float, state: inout Float) -> Float {
        // y[n] = x[n] - x[n-1] + coeff * y[n-1]
        let output = input - prevIn + dcCoeff * state
        prevIn = input
        state = output
        return output
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Extract bass using cascaded one-pole filters (2nd order, 12 dB/oct)
        lp1StateL = lpCoeff * lp1StateL + (1.0 - lpCoeff) * left
        lp1StateR = lpCoeff * lp1StateR + (1.0 - lpCoeff) * right
        lp2StateL = lpCoeff * lp2StateL + (1.0 - lpCoeff) * lp1StateL
        lp2StateR = lpCoeff * lp2StateR + (1.0 - lpCoeff) * lp1StateR

        let bassL = lp2StateL
        let bassR = lp2StateR

        // Apply saturation to generate upper harmonics (makes bass audible on small speakers)
        var enhancedL = saturate(bassL, drive: harmonics)
        var enhancedR = saturate(bassR, drive: harmonics)

        // Remove DC offset introduced by saturation
        enhancedL = dcBlock(input: enhancedL, prevIn: &dcPrevInL, state: &dcStateL)
        enhancedR = dcBlock(input: enhancedR, prevIn: &dcPrevInR, state: &dcStateR)

        // Add enhanced bass to original signal
        let outL = left + enhancedL * amount
        let outR = right + enhancedR * amount

        return (outL, outR)
    }

    func reset() {
        lp1StateL = 0
        lp1StateR = 0
        lp2StateL = 0
        lp2StateR = 0
        dcStateL = 0
        dcStateR = 0
        dcPrevInL = 0
        dcPrevInR = 0
    }

    var parameters: [ParameterDescriptor] {
        [
            ParameterDescriptor("Amount", min: 0, max: 100, defaultValue: 50, unit: .percent),
            ParameterDescriptor("Low Freq", min: 60, max: 150, defaultValue: 100, unit: .hertz),
            ParameterDescriptor("Harmonics", min: 0, max: 100, defaultValue: 30, unit: .percent),
        ]
    }

    func getParameter(_ index: Int) -> Float {
        switch index {
        case 0: return amount * 100
        case 1: return lowFreq
        case 2: return harmonics * 100
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        switch index {
        case 0: amount = min(max(value / 100, 0), 1)
        case 1:
            lowFreq = min(max(value, 60), 150)
            updateFilter()
        case 2: harmonics = min(max(value / 100, 0), 1)
        default: break
        }
    }
}
