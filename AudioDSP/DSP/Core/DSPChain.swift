import Foundation
import os

/// Thread-safe DSP effect chain with level metering
/// Uses double-buffered snapshot for lock-free audio thread access
final class DSPChain: @unchecked Sendable {
    private var effects: [any Effect] = []
    let sampleRate: UInt32

    // Double-buffered snapshots for truly lock-free audio thread access
    // Main thread writes to inactive buffer, then atomically swaps the index
    private var effectsBuffers: (UnsafeMutablePointer<[any Effect]>, UnsafeMutablePointer<[any Effect]>)
    private var activeBufferIndex: UnsafeMutablePointer<Int32>  // 0 or 1, accessed atomically

    // Peak level metering with proper ballistics
    // Fast attack (~1ms) to catch transients, slow release (~300ms) for readable display
    private var _inputLevelLeft: Float = 0
    private var _inputLevelRight: Float = 0
    private var _outputLevelLeft: Float = 0
    private var _outputLevelRight: Float = 0

    // Meter envelope coefficients
    private let meterAttackCoeff: Float   // ~1ms attack
    private let meterReleaseCoeff: Float  // ~300ms release

    // Lock only for configuration changes (not used on audio thread hot path)
    private let configLock = os_unfair_lock_s()
    private var configLockPointer: UnsafeMutablePointer<os_unfair_lock_s>

    private static let meterAttackMs: Float = 1.0
    private static let meterReleaseMs: Float = 300.0

    init(sampleRate: UInt32 = 48000) {
        self.sampleRate = sampleRate

        let sr = Float(sampleRate)
        meterAttackCoeff = timeToCoefficient(Self.meterAttackMs, sampleRate: sr)
        meterReleaseCoeff = timeToCoefficient(Self.meterReleaseMs, sampleRate: sr)

        // Initialize double-buffered snapshots for lock-free access
        let buffer0 = UnsafeMutablePointer<[any Effect]>.allocate(capacity: 1)
        buffer0.initialize(to: [])
        let buffer1 = UnsafeMutablePointer<[any Effect]>.allocate(capacity: 1)
        buffer1.initialize(to: [])
        effectsBuffers = (buffer0, buffer1)

        activeBufferIndex = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        activeBufferIndex.initialize(to: 0)

        // Initialize config lock
        configLockPointer = UnsafeMutablePointer<os_unfair_lock_s>.allocate(capacity: 1)
        configLockPointer.initialize(to: os_unfair_lock_s())
    }

    deinit {
        effectsBuffers.0.deinitialize(count: 1)
        effectsBuffers.0.deallocate()
        effectsBuffers.1.deinitialize(count: 1)
        effectsBuffers.1.deallocate()
        activeBufferIndex.deinitialize(count: 1)
        activeBufferIndex.deallocate()
        configLockPointer.deinitialize(count: 1)
        configLockPointer.deallocate()
    }

    func addEffect(_ effect: any Effect) {
        os_unfair_lock_lock(configLockPointer)
        effects.append(effect)
        // Write to inactive buffer, then atomically swap
        let currentIndex = OSAtomicAdd32(0, activeBufferIndex)  // Atomic read
        let inactiveIndex = 1 - currentIndex
        let inactiveBuffer = inactiveIndex == 0 ? effectsBuffers.0 : effectsBuffers.1
        inactiveBuffer.pointee = effects
        OSMemoryBarrier()  // Ensure write completes before swap
        OSAtomicCompareAndSwap32(currentIndex, inactiveIndex, activeBufferIndex)
        os_unfair_lock_unlock(configLockPointer)
    }

    var effectList: [any Effect] {
        os_unfair_lock_lock(configLockPointer)
        defer { os_unfair_lock_unlock(configLockPointer) }
        return effects
    }

    func getEffect(at index: Int) -> (any Effect)? {
        os_unfair_lock_lock(configLockPointer)
        defer { os_unfair_lock_unlock(configLockPointer) }
        guard index >= 0, index < effects.count else { return nil }
        return effects[index]
    }

    var effectCount: Int {
        os_unfair_lock_lock(configLockPointer)
        defer { os_unfair_lock_unlock(configLockPointer) }
        return effects.count
    }

    /// Apply meter envelope: fast attack to catch peaks, slow release for readable display
    @inline(__always)
    private func updateMeter(current: Float, target: Float) -> Float {
        let coeff = target > current ? meterAttackCoeff : meterReleaseCoeff
        let result = coeff * current + (1.0 - coeff) * target
        return flushDenormals(result, threshold: 1e-10)
    }

    /// Process a stereo sample pair through the entire chain
    /// LOCK-FREE: Safe to call from audio thread - uses atomic double-buffer read
    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Update input level meters with proper ballistics
        _inputLevelLeft = updateMeter(current: _inputLevelLeft, target: abs(left))
        _inputLevelRight = updateMeter(current: _inputLevelRight, target: abs(right))

        var l = left
        var r = right

        // Lock-free atomic read from double-buffered effects snapshot
        let index = OSAtomicAdd32(0, activeBufferIndex)  // Atomic read
        let activeBuffer = index == 0 ? effectsBuffers.0 : effectsBuffers.1
        let currentEffects = activeBuffer.pointee
        for effect in currentEffects {
            if !effect.isBypassed {
                let wetDry = effect.wetDry
                let (wetL, wetR) = effect.process(left: l, right: r)

                // Apply wet/dry mix
                l = l * (1.0 - wetDry) + wetL * wetDry
                r = r * (1.0 - wetDry) + wetR * wetDry
            }
        }

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
        os_unfair_lock_lock(configLockPointer)
        defer { os_unfair_lock_unlock(configLockPointer) }
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
