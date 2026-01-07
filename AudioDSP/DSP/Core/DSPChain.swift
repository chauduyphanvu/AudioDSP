import Foundation
import os

/// Thread-safe DSP effect chain with level metering
final class DSPChain: @unchecked Sendable {
    private var effects: [any Effect] = []
    let sampleRate: UInt32

    // Atomic level metering using OSAtomicQueue would be ideal,
    // but for simplicity we use a simple approach with @MainActor publishing
    private var _inputLevelLeft: Float = 0
    private var _inputLevelRight: Float = 0
    private var _outputLevelLeft: Float = 0
    private var _outputLevelRight: Float = 0

    private let lock = NSLock()

    init(sampleRate: UInt32 = 48000) {
        self.sampleRate = sampleRate
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

    /// Process a stereo sample pair through the entire chain
    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Update input level meters
        _inputLevelLeft = abs(left)
        _inputLevelRight = abs(right)

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

        // Update output level meters
        _outputLevelLeft = abs(l)
        _outputLevelRight = abs(r)

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
