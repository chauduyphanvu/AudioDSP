import Accelerate
import Foundation

/// Lock-free SPSC (Single-Producer Single-Consumer) ring buffer for thread-safe audio data transfer
/// Audio thread writes (producer), analysis thread reads (consumer)
/// Uses atomic operations with proper memory ordering for thread safety
final class LockFreeRingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<Float>
    private let capacity: Int

    // Use UnsafeMutablePointer for atomic-like access with memory barriers
    // writeIndex is modified by producer (audio thread), read by consumer
    private let writeIndexPtr: UnsafeMutablePointer<Int>

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)

        self.writeIndexPtr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        writeIndexPtr.initialize(to: 0)
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
        writeIndexPtr.deinitialize(count: 1)
        writeIndexPtr.deallocate()
    }

    /// Write a sample to the ring buffer (audio thread - producer)
    /// Uses release semantics to ensure buffer write is visible before index update
    @inline(__always)
    func write(_ sample: Float) {
        let index = writeIndexPtr.pointee
        buffer[index] = sample

        // Memory barrier: ensure buffer write completes before index update is visible
        // On ARM64, this prevents reordering of the store to buffer and store to writeIndex
        OSMemoryBarrier()

        writeIndexPtr.pointee = (index + 1) % capacity
    }

    /// Read the entire buffer contents into a destination array (analysis thread - consumer)
    /// Uses acquire semantics to ensure we see all writes after reading the index
    func read(into destination: inout [Float]) {
        let currentWrite = writeIndexPtr.pointee

        // Memory barrier AFTER reading index: ensure subsequent buffer reads
        // see all writes that happened before the index update
        OSMemoryBarrier()

        for i in 0..<capacity {
            let srcIndex = (currentWrite + i) % capacity
            destination[i] = buffer[srcIndex]
        }
    }
}

/// Real-time FFT analyzer for spectrum visualization
/// IMPROVED: Uses lock-free ring buffer for thread-safe audio/UI communication
final class FFTAnalyzer: @unchecked Sendable {
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: vDSP_DFT_Setup

    // Lock-free ring buffer for audio input
    private let ringBuffer: LockFreeRingBuffer

    // Pre-allocated buffers for FFT processing (analysis thread only)
    private var windowedBuffer: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]
    private var magnitudes: [Float]
    private var smoothedMagnitudes: [Float]

    // Hann window for better frequency resolution
    private var window: [Float]

    /// Number of frequency bins (half of FFT size)
    var binCount: Int { fftSize / 2 }

    /// Sample rate used for frequency calculations
    var sampleRate: Float = 48000

    init(fftSize: Int = 2048) {
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))

        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .FORWARD
        ) else {
            fatalError("Failed to create FFT setup")
        }
        self.fftSetup = setup

        // Initialize lock-free ring buffer
        ringBuffer = LockFreeRingBuffer(capacity: fftSize)

        // Pre-allocate all processing buffers
        windowedBuffer = [Float](repeating: 0, count: fftSize)
        realPart = [Float](repeating: 0, count: fftSize)
        imagPart = [Float](repeating: 0, count: fftSize)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
        smoothedMagnitudes = [Float](repeating: 0, count: fftSize / 2)

        // Create Hann window
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }

    /// Push a stereo sample pair into the analyzer (audio thread - lock-free)
    @inline(__always)
    func push(left: Float, right: Float) {
        // Mix to mono for analysis
        let mono = (left + right) * 0.5
        ringBuffer.write(mono)
    }

    /// Perform FFT analysis and return smoothed magnitude spectrum
    /// Call this from the UI/analysis thread, not the audio thread
    func analyze() -> [Float] {
        // Read from lock-free ring buffer (no lock needed)
        ringBuffer.read(into: &windowedBuffer)

        // Apply window function
        vDSP_vmul(windowedBuffer, 1, window, 1, &windowedBuffer, 1, vDSP_Length(fftSize))

        // Prepare for FFT (split complex format)
        for i in 0..<fftSize {
            realPart[i] = windowedBuffer[i]
            imagPart[i] = 0
        }

        // Perform FFT
        vDSP_DFT_Execute(fftSetup, realPart, imagPart, &realPart, &imagPart)

        // Calculate magnitudes (only first half is meaningful for real input)
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(binCount))

        // Normalize
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(binCount))

        // Convert to dB
        let minDb: Float = -80
        for i in 0..<binCount {
            let db = linearToDb(magnitudes[i])
            magnitudes[i] = max(db, minDb)
        }

        // Smooth with exponential moving average
        let smoothing: Float = 0.7
        for i in 0..<binCount {
            smoothedMagnitudes[i] = smoothedMagnitudes[i] * smoothing + magnitudes[i] * (1 - smoothing)
        }

        return smoothedMagnitudes
    }

    /// Get frequency for a given bin index
    func frequencyForBin(_ bin: Int) -> Float {
        Float(bin) * sampleRate / Float(fftSize)
    }

    /// Get bin index for a given frequency
    func binForFrequency(_ frequency: Float) -> Int {
        Int(frequency * Float(fftSize) / sampleRate)
    }

    /// Normalize dB value to 0-1 range for display
    func normalizeDb(_ db: Float, minDb: Float = -80, maxDb: Float = 0) -> Float {
        (db - minDb) / (maxDb - minDb)
    }
}
