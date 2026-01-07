import Accelerate
import Foundation

/// Real-time FFT analyzer for spectrum visualization
final class FFTAnalyzer: @unchecked Sendable {
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: vDSP_DFT_Setup

    private var inputBuffer: [Float]
    private var windowedBuffer: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]
    private var magnitudes: [Float]
    private var smoothedMagnitudes: [Float]

    private var writeIndex: Int = 0
    private let lock = NSLock()

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

        inputBuffer = [Float](repeating: 0, count: fftSize)
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

    /// Push a stereo sample pair into the analyzer
    func push(left: Float, right: Float) {
        lock.lock()
        defer { lock.unlock() }

        // Mix to mono for analysis
        let mono = (left + right) * 0.5

        inputBuffer[writeIndex] = mono
        writeIndex = (writeIndex + 1) % fftSize
    }

    /// Perform FFT analysis and return smoothed magnitude spectrum
    func analyze() -> [Float] {
        lock.lock()

        // Copy input buffer with correct ordering (unwrap circular buffer)
        for i in 0..<fftSize {
            let srcIndex = (writeIndex + i) % fftSize
            windowedBuffer[i] = inputBuffer[srcIndex]
        }

        lock.unlock()

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
        var minDb: Float = -80
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
