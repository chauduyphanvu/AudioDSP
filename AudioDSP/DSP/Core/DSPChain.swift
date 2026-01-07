import Foundation
import os

/// Thread-safe DSP effect chain with level metering
final class DSPChain: @unchecked Sendable {
    private var effects: [any Effect] = []
    let sampleRate: UInt32

    // Peak level metering with proper ballistics
    // Fast attack (~1ms) to catch transients, slow release (~300ms) for readable display
    private var _inputLevelLeft: Float = 0
    private var _inputLevelRight: Float = 0
    private var _outputLevelLeft: Float = 0
    private var _outputLevelRight: Float = 0

    // Meter envelope coefficients
    private let meterAttackCoeff: Float   // ~1ms attack
    private let meterReleaseCoeff: Float  // ~300ms release

    private let lock = NSLock()

    init(sampleRate: UInt32 = 48000) {
        self.sampleRate = sampleRate

        // Calculate meter envelope coefficients
        // attack = exp(-1 / (attackMs * 0.001 * sampleRate))
        let sr = Float(sampleRate)
        meterAttackCoeff = expf(-1.0 / (1.0 * 0.001 * sr))      // 1ms attack
        meterReleaseCoeff = expf(-1.0 / (300.0 * 0.001 * sr))   // 300ms release
    }

    func addEffect(_ effect: any Effect) {
        lock.lock()
        defer { lock.unlock() }
        effects.append(effect)
    }

    var effectList: [any Effect] {
        lock.lock()
        defer { lock.unlock() }
        return effects
    }

    func getEffect(at index: Int) -> (any Effect)? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < effects.count else { return nil }
        return effects[index]
    }

    var effectCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return effects.count
    }

    /// Apply meter envelope: fast attack to catch peaks, slow release for readable display
    @inline(__always)
    private func updateMeter(current: Float, target: Float) -> Float {
        let coeff = target > current ? meterAttackCoeff : meterReleaseCoeff
        let result = coeff * current + (1.0 - coeff) * target
        // Flush denormals
        return result < 1e-10 ? 0 : result
    }

    /// Process a stereo sample pair through the entire chain
    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Update input level meters with proper ballistics
        _inputLevelLeft = updateMeter(current: _inputLevelLeft, target: abs(left))
        _inputLevelRight = updateMeter(current: _inputLevelRight, target: abs(right))

        var l = left
        var r = right

        lock.lock()
        for effect in effects {
            if !effect.isBypassed {
                let wetDry = effect.wetDry
                let (wetL, wetR) = effect.process(left: l, right: r)

                // Apply wet/dry mix
                l = l * (1.0 - wetDry) + wetL * wetDry
                r = r * (1.0 - wetDry) + wetR * wetDry
            }
        }
        lock.unlock()

        // Update output level meters with proper ballistics
        _outputLevelLeft = updateMeter(current: _outputLevelLeft, target: abs(l))
        _outputLevelRight = updateMeter(current: _outputLevelRight, target: abs(r))

        return (l, r)
    }

    var inputLevels: (left: Float, right: Float) {
        (_inputLevelLeft, _inputLevelRight)
    }

    var outputLevels: (left: Float, right: Float) {
        (_outputLevelLeft, _outputLevelRight)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        for effect in effects {
            effect.reset()
        }
    }

    /// Create default effect chain with all effects
    static func createDefault(sampleRate: Float) -> DSPChain {
        let chain = DSPChain(sampleRate: UInt32(sampleRate))

        // Add effects in processing order
        chain.addEffect(ParametricEQ(sampleRate: sampleRate))
        chain.addEffect(BassEnhancer(sampleRate: sampleRate))
        chain.addEffect(VocalClarity(sampleRate: sampleRate))
        chain.addEffect(Compressor(sampleRate: sampleRate))
        chain.addEffect(Reverb(sampleRate: sampleRate))
        chain.addEffect(Delay(sampleRate: sampleRate))
        chain.addEffect(StereoWidener())
        chain.addEffect(Limiter(sampleRate: sampleRate))
        chain.addEffect(Gain())

        return chain
    }
}
