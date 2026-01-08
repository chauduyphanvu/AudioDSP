import Foundation
import Darwin

/// Lock-free Single Producer Single Consumer (SPSC) ring buffer for real-time audio
/// Uses proper atomic operations with memory barriers for thread-safe access
final class RingBuffer<T>: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<T>
    private let capacity: Int
    private let capacityMask: Int

    // Atomic indices - use Int64 for Darwin atomic functions
    // Stored as UnsafeMutablePointer to allow atomic operations
    private let writeIndex: UnsafeMutablePointer<Int64>
    private let readIndex: UnsafeMutablePointer<Int64>

    // Default value for underrun handling
    private let defaultValue: T

    // Underrun statistics (non-critical, can be racy)
    private var _underrunCount: Int = 0
    var underrunCount: Int { _underrunCount }

    /// Initialize with capacity (rounded to power of 2) and default value for underruns
    init(capacity: Int, defaultValue: T) {
        // Round up to next power of 2 for efficient masking
        let powerOf2Capacity = capacity <= 0 ? 1024 : (1 << Int(ceil(log2(Double(capacity)))))
        self.capacity = powerOf2Capacity
        self.capacityMask = powerOf2Capacity - 1
        self.defaultValue = defaultValue

        // Allocate contiguous buffer
        self.buffer = UnsafeMutablePointer<T>.allocate(capacity: powerOf2Capacity)
        self.buffer.initialize(repeating: defaultValue, count: powerOf2Capacity)

        // Allocate atomic indices (using Int64 for OSAtomic compatibility)
        self.writeIndex = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        self.writeIndex.initialize(to: 0)

        self.readIndex = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        self.readIndex.initialize(to: 0)
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
        writeIndex.deinitialize(count: 1)
        writeIndex.deallocate()
        readIndex.deinitialize(count: 1)
        readIndex.deallocate()
    }

    /// Available samples for reading
    var count: Int {
        let write = atomicLoadAcquire(writeIndex)
        let read = atomicLoadAcquire(readIndex)
        return Int((write - read + Int64(capacity)) & Int64(capacityMask))
    }

    /// Available space for writing
    var availableSpace: Int {
        return capacity - count - 1
    }

    var isEmpty: Bool {
        return count == 0
    }

    /// Push a single value (producer only - call from input thread)
    /// Returns true if successful, false if buffer is full
    @inline(__always)
    func push(_ value: T) -> Bool {
        let write = atomicLoadRelaxed(writeIndex)
        let read = atomicLoadAcquire(readIndex)

        // Check if buffer is full (leave one slot empty)
        let nextWrite = (write + 1) & Int64(capacityMask)
        if nextWrite == read {
            return false  // Buffer full
        }

        buffer[Int(write)] = value
        atomicStoreRelease(writeIndex, nextWrite)
        return true
    }

    /// Pop a single value (consumer only - call from output thread)
    /// Returns nil if buffer is empty
    @inline(__always)
    func pop() -> T? {
        let write = atomicLoadAcquire(writeIndex)
        let read = atomicLoadRelaxed(readIndex)

        if read == write {
            _underrunCount += 1
            return nil  // Buffer empty
        }

        let value = buffer[Int(read)]
        atomicStoreRelease(readIndex, (read + 1) & Int64(capacityMask))
        return value
    }

    /// Clear the buffer (call when stopping audio, not during real-time processing)
    func clear() {
        atomicStoreRelease(writeIndex, 0)
        atomicStoreRelease(readIndex, 0)
        _underrunCount = 0

        for i in 0..<capacity {
            buffer[i] = defaultValue
        }
    }

    // MARK: - Atomic Operations using Darwin primitives
    //
    // On ARM64 (Apple Silicon), loads can be speculatively reordered.
    // We use full memory barriers (OSMemoryBarrier) to ensure correctness.
    // This is slightly more conservative than minimal acquire/release but
    // guarantees correct behavior across all Apple platforms.

    /// Atomic load with acquire semantics
    /// Ensures the load completes before any subsequent memory operations
    /// Full barrier used for ARM64 correctness (prevents speculative reordering)
    @inline(__always)
    private func atomicLoadAcquire(_ ptr: UnsafeMutablePointer<Int64>) -> Int64 {
        // Full barrier before load prevents reordering with prior operations
        OSMemoryBarrier()
        let value = ptr.pointee
        // Full barrier after load prevents subsequent operations from being reordered before the load
        OSMemoryBarrier()
        return value
    }

    /// Atomic load without memory ordering (for same-thread access patterns in SPSC)
    /// Safe only when the same thread owns this index (producer reads writeIndex, consumer reads readIndex)
    @inline(__always)
    private func atomicLoadRelaxed(_ ptr: UnsafeMutablePointer<Int64>) -> Int64 {
        return ptr.pointee
    }

    /// Atomic store with release semantics
    /// Ensures all prior writes (especially buffer writes) are visible before this store
    @inline(__always)
    private func atomicStoreRelease(_ ptr: UnsafeMutablePointer<Int64>, _ value: Int64) {
        // Full barrier ensures all prior writes are visible before the index update
        OSMemoryBarrier()
        ptr.pointee = value
        // Note: A pure release barrier wouldn't need a trailing barrier,
        // but the leading barrier is critical for correctness
    }
}

// MARK: - Stereo Sample for Interleaved Audio

/// Interleaved stereo sample to ensure L/R channels stay synchronized
struct StereoSample: Sendable {
    var left: Float
    var right: Float

    static let zero = StereoSample(left: 0, right: 0)
}

/// Lock-free stereo ring buffer using interleaved samples
/// Guarantees L/R channel synchronization by storing samples as atomic pairs
final class StereoRingBuffer: @unchecked Sendable {
    private let buffer: RingBuffer<StereoSample>

    // Underrun handling - fade out to avoid clicks
    // These are ONLY written by the audio (consumer) thread during normal operation
    // clear() signals reset via atomic flag, audio thread handles actual state reset
    private var lastValidSample: StereoSample = .zero
    private var fadeOutCounter: Int = 0
    private let fadeOutSamples: Int = 64  // ~1.3ms at 48kHz

    // Atomic flag to signal fade state reset (main thread sets, audio thread reads and clears)
    private let resetFadeState: UnsafeMutablePointer<Int32>

    init(capacity: Int) {
        buffer = RingBuffer<StereoSample>(capacity: capacity, defaultValue: .zero)
        resetFadeState = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        resetFadeState.initialize(to: 0)
    }

    deinit {
        resetFadeState.deinitialize(count: 1)
        resetFadeState.deallocate()
    }

    var count: Int {
        buffer.count
    }

    var underrunCount: Int {
        buffer.underrunCount
    }

    /// Push a stereo sample pair (producer thread only)
    @inline(__always)
    func push(left: Float, right: Float) {
        _ = buffer.push(StereoSample(left: left, right: right))
    }

    /// Pop a stereo sample pair with graceful underrun handling (consumer thread only)
    /// Returns fade-out samples during underrun to avoid clicks
    @inline(__always)
    func pop() -> (left: Float, right: Float) {
        // Check if main thread signaled a fade state reset
        if OSAtomicCompareAndSwap32(1, 0, resetFadeState) {
            lastValidSample = .zero
            fadeOutCounter = 0
        }

        if let sample = buffer.pop() {
            // Valid sample - reset fade counter and store for potential underrun
            fadeOutCounter = 0
            lastValidSample = sample
            return (sample.left, sample.right)
        }

        // Underrun - return graceful fade-out
        return handleUnderrun()
    }

    /// Handle underrun with exponential fade-out to avoid clicks
    @inline(__always)
    private func handleUnderrun() -> (left: Float, right: Float) {
        if fadeOutCounter >= fadeOutSamples {
            // Fully faded out - return silence
            return (0, 0)
        }

        // Exponential fade-out from last valid sample
        let fadeProgress = Float(fadeOutCounter) / Float(fadeOutSamples)
        fadeOutCounter += 1

        // Quadratic fade for smoother decay
        let fadeMultiplier = (1.0 - fadeProgress) * (1.0 - fadeProgress)

        return (
            lastValidSample.left * fadeMultiplier,
            lastValidSample.right * fadeMultiplier
        )
    }

    /// Clear the buffer (call when stopping audio - safe from any thread)
    /// Signals fade state reset to audio thread to avoid data race
    func clear() {
        buffer.clear()
        // Signal audio thread to reset fade state on next pop()
        OSAtomicCompareAndSwap32(0, 1, resetFadeState)
    }
}
