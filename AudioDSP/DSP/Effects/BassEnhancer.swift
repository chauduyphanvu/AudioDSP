import Foundation

/// Psychoacoustic bass enhancement using sub-harmonic synthesis
final class BassEnhancer: Effect, @unchecked Sendable {
    private var amount: Float = 0.5    // 0.0 - 1.0 (overall intensity)
    private var lowFreq: Float = 100   // Hz (cutoff for bass extraction)
    private var harmonics: Float = 0.3 // 0.0 - 1.0 (saturation amount)

    // One-pole low-pass filter state
    private var lpStateL: Float = 0
    private var lpStateR: Float = 0
    private var lpCoeff: Float = 0

    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    let name = "Bass Enhancer"

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        updateFilter()
    }

    private func updateFilter() {
        // One-pole low-pass coefficient: coeff = exp(-2*pi*fc/fs)
        let omega = 2.0 * Float.pi * lowFreq / sampleRate
        lpCoeff = exp(-omega)
    }

    /// Soft saturation using tanh
    @inline(__always)
    private func saturate(_ x: Float, drive: Float) -> Float {
        tanh(x * (1.0 + drive * 3.0))
    }

    /// Generate sub-harmonic (octave down) via half-wave rectification
    @inline(__always)
    private func subHarmonic(_ x: Float) -> Float {
        // Half-wave rectification creates even harmonics including octave down
        (x + abs(x)) * 0.5
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Extract bass using one-pole low-pass filter
        lpStateL = lpCoeff * lpStateL + (1.0 - lpCoeff) * left
        lpStateR = lpCoeff * lpStateR + (1.0 - lpCoeff) * right

        let bassL = lpStateL
        let bassR = lpStateR

        // Apply saturation to generate harmonics
        let saturatedL = saturate(bassL, drive: harmonics)
        let saturatedR = saturate(bassR, drive: harmonics)

        // Generate sub-harmonics
        let subL = subHarmonic(saturatedL)
        let subR = subHarmonic(saturatedR)

        // Mix enhanced bass with saturation and sub-harmonics
        let enhancedL = saturatedL * 0.6 + subL * 0.4
        let enhancedR = saturatedR * 0.6 + subR * 0.4

        // Add enhanced bass to original signal
        let outL = left + enhancedL * amount
        let outR = right + enhancedR * amount

        return (outL, outR)
    }

    func reset() {
        lpStateL = 0
        lpStateR = 0
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
