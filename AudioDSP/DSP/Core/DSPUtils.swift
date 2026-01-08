import Foundation

// MARK: - Clamping Extension

extension Comparable {
    /// Clamp value to a closed range. More readable than min(max(value, lower), upper).
    @inline(__always)
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Decibel Conversions

/// Convert decibels to linear amplitude
@inline(__always)
func dbToLinear(_ db: Float) -> Float {
    powf(10.0, db / 20.0)
}

/// Convert linear amplitude to decibels (clamps to avoid -infinity)
@inline(__always)
func linearToDb(_ linear: Float) -> Float {
    20.0 * log10f(max(linear, 1e-10))
}

// MARK: - Stereo Utilities

/// Compute peak value from stereo sample pair
@inline(__always)
func stereoPeak(_ left: Float, _ right: Float) -> Float {
    max(abs(left), abs(right))
}

// MARK: - Time Constants

/// Calculate exponential smoothing coefficient from time constant in milliseconds
/// Used for envelope followers, parameter smoothers, and meter ballistics.
/// Formula: coeff = exp(-1 / (timeMs * 0.001 * sampleRate))
@inline(__always)
func timeToCoefficient(_ timeMs: Float, sampleRate: Float) -> Float {
    guard timeMs > 0 else { return 0 }
    return expf(-1.0 / (timeMs * 0.001 * sampleRate))
}

/// Calculate smoothing coefficient from time constant in seconds
@inline(__always)
func timeToCoefficient(seconds: Float, sampleRate: Float) -> Float {
    guard seconds > 0 else { return 0 }
    return expf(-1.0 / (seconds * sampleRate))
}

// MARK: - Denormal Handling

/// Flush value to zero if it's a denormal (below threshold)
/// Denormals can cause severe CPU penalties on some processors
@inline(__always)
func flushDenormals(_ value: Float) -> Float {
    abs(value) < 1e-15 ? 0 : value
}

/// Flush value to zero with custom threshold
@inline(__always)
func flushDenormals(_ value: Float, threshold: Float) -> Float {
    abs(value) < threshold ? 0 : value
}

/// Envelope detection mode
enum EnvelopeMode: Sendable {
    /// Standard attack/release envelope (for compressors)
    case attackRelease
    /// Instant attack with smooth release (for limiters)
    case instantAttack
}

/// Reusable envelope follower for dynamics processing
final class EnvelopeFollower: @unchecked Sendable {
    private var envelope: Float
    private var attackCoeff: Float = 0
    private var releaseCoeff: Float = 0
    private let sampleRate: Float
    private(set) var attackMs: Float
    private(set) var releaseMs: Float
    private let mode: EnvelopeMode

    init(sampleRate: Float, mode: EnvelopeMode) {
        self.sampleRate = sampleRate
        self.mode = mode

        switch mode {
        case .attackRelease:
            attackMs = 10.0
            releaseMs = 100.0
            envelope = 0.0
        case .instantAttack:
            attackMs = 0.0
            releaseMs = 50.0
            envelope = 1.0
        }

        attackCoeff = timeToCoefficient(attackMs, sampleRate: sampleRate)
        releaseCoeff = timeToCoefficient(releaseMs, sampleRate: sampleRate)
    }

    init(sampleRate: Float, attackMs: Float, releaseMs: Float, mode: EnvelopeMode) {
        self.sampleRate = sampleRate
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.mode = mode

        switch mode {
        case .attackRelease:
            envelope = 0.0
        case .instantAttack:
            envelope = 1.0
        }

        attackCoeff = timeToCoefficient(attackMs, sampleRate: sampleRate)
        releaseCoeff = timeToCoefficient(releaseMs, sampleRate: sampleRate)
    }

    func setAttackMs(_ ms: Float) {
        attackMs = ms
        attackCoeff = timeToCoefficient(ms, sampleRate: sampleRate)
    }

    func setReleaseMs(_ ms: Float) {
        releaseMs = ms
        releaseCoeff = timeToCoefficient(ms, sampleRate: sampleRate)
    }

    /// Process input and return envelope value
    @inline(__always)
    func process(_ input: Float) -> Float {
        switch mode {
        case .attackRelease:
            let coeff = input > envelope ? attackCoeff : releaseCoeff
            envelope = coeff * envelope + (1.0 - coeff) * input

        case .instantAttack:
            if input < envelope {
                envelope = input
            } else {
                envelope = releaseCoeff * envelope + (1.0 - releaseCoeff) * input
            }
        }

        envelope = flushDenormals(envelope)
        return envelope
    }

    var current: Float { envelope }

    func reset() {
        switch mode {
        case .attackRelease:
            envelope = 0.0
        case .instantAttack:
            envelope = 1.0
        }
    }
}

/// Smooth parameter changes to avoid zipper noise
final class ParameterSmoother: @unchecked Sendable {
    private var current: Float
    private var target: Float
    private let smoothingCoeff: Float

    init(initialValue: Float, smoothingMs: Float = 5.0, sampleRate: Float = 48000) {
        self.current = initialValue
        self.target = initialValue
        self.smoothingCoeff = timeToCoefficient(smoothingMs, sampleRate: sampleRate)
    }

    func setTarget(_ value: Float) {
        target = value
    }

    @inline(__always)
    func process() -> Float {
        current = smoothingCoeff * current + (1.0 - smoothingCoeff) * target
        current = flushDenormals(current)
        return current
    }

    var value: Float { current }
}

// MARK: - Stereo Delay Line

/// Reusable stereo delay line with configurable maximum delay.
/// Used by Delay, Limiter (lookahead), and other effects requiring audio buffering.
final class StereoDelayLine: @unchecked Sendable {
    private var bufferLeft: [Float]
    private var bufferRight: [Float]
    private var writeIndex: Int = 0
    let maxSamples: Int

    init(maxSamples: Int) {
        self.maxSamples = max(1, maxSamples)
        self.bufferLeft = [Float](repeating: 0, count: self.maxSamples)
        self.bufferRight = [Float](repeating: 0, count: self.maxSamples)
    }

    /// Convenience initializer using delay time in milliseconds
    convenience init(maxDelayMs: Float, sampleRate: Float) {
        let samples = Int(sampleRate * maxDelayMs / 1000)
        self.init(maxSamples: samples)
    }

    /// Write a stereo sample and read from a delay offset.
    /// Returns the delayed samples while storing the input.
    @inline(__always)
    func process(left: Float, right: Float, delaySamples: Int) -> (left: Float, right: Float) {
        let clampedDelay = min(delaySamples, maxSamples - 1)
        let readIndex = (writeIndex + maxSamples - clampedDelay) % maxSamples

        let delayedLeft = bufferLeft[readIndex]
        let delayedRight = bufferRight[readIndex]

        bufferLeft[writeIndex] = left
        bufferRight[writeIndex] = right
        writeIndex = (writeIndex + 1) % maxSamples

        return (delayedLeft, delayedRight)
    }

    /// Read from a specific delay offset without writing
    @inline(__always)
    func read(delaySamples: Int) -> (left: Float, right: Float) {
        let clampedDelay = min(delaySamples, maxSamples - 1)
        let readIndex = (writeIndex + maxSamples - clampedDelay) % maxSamples
        return (bufferLeft[readIndex], bufferRight[readIndex])
    }

    /// Write to the current position without advancing
    @inline(__always)
    func write(left: Float, right: Float) {
        bufferLeft[writeIndex] = left
        bufferRight[writeIndex] = right
    }

    /// Advance write position (call after write if using separate read/write)
    @inline(__always)
    func advance() {
        writeIndex = (writeIndex + 1) % maxSamples
    }

    /// Reset buffers without allocation (audio-thread safe)
    func reset() {
        bufferLeft.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        bufferRight.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        writeIndex = 0
    }
}

// MARK: - Mono Delay Line

/// Single-channel delay line for mono processing or per-channel use
final class MonoDelayLine: @unchecked Sendable {
    private var buffer: [Float]
    private var writeIndex: Int = 0
    let maxSamples: Int

    init(maxSamples: Int) {
        self.maxSamples = max(1, maxSamples)
        self.buffer = [Float](repeating: 0, count: self.maxSamples)
    }

    convenience init(maxDelayMs: Float, sampleRate: Float) {
        let samples = Int(sampleRate * maxDelayMs / 1000)
        self.init(maxSamples: samples)
    }

    @inline(__always)
    func process(_ input: Float, delaySamples: Int) -> Float {
        let clampedDelay = min(delaySamples, maxSamples - 1)
        let readIndex = (writeIndex + maxSamples - clampedDelay) % maxSamples

        let delayed = buffer[readIndex]
        buffer[writeIndex] = input
        writeIndex = (writeIndex + 1) % maxSamples

        return delayed
    }

    @inline(__always)
    func read(delaySamples: Int) -> Float {
        let clampedDelay = min(delaySamples, maxSamples - 1)
        let readIndex = (writeIndex + maxSamples - clampedDelay) % maxSamples
        return buffer[readIndex]
    }

    /// Reset buffer without allocation (audio-thread safe)
    func reset() {
        buffer.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        writeIndex = 0
    }
}
