import Foundation

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
