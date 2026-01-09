import Accelerate
import Foundation
import os

// MARK: - Overlap-Add Convolver

/// Stereo FFT convolver using overlap-add for real-time processing.
/// Applies a frequency-domain kernel to audio using 50% overlap.
///
/// Thread Safety:
/// - `process` must only be called from the audio thread
/// - `setKernel` can be called from any thread (uses double-buffering)
/// - `reset` signals a deferred reset that executes on the audio thread
final class OverlapAddConvolver: @unchecked Sendable {
    let fftSize: Int
    let hopSize: Int

    // FFT setup
    private let fftSetup: vDSP_DFT_Setup
    private let ifftSetup: vDSP_DFT_Setup

    // Input/output buffers for overlap-add
    private var inputBufferL: [Float]
    private var inputBufferR: [Float]
    private var outputBufferL: [Float]
    private var outputBufferR: [Float]
    private var overlapBufferL: [Float]
    private var overlapBufferR: [Float]
    private var writePosition: Int = 0

    // Double-buffered FIR kernels (frequency domain) for lock-free audio thread
    private var kernelBufferA_Real: [Float]
    private var kernelBufferA_Imag: [Float]
    private var kernelBufferB_Real: [Float]
    private var kernelBufferB_Imag: [Float]
    private var activeKernelIsA: Bool = true
    private var kernelSwapLock = os_unfair_lock()

    // Processing buffers (pre-allocated, no allocation during process)
    private var windowedInput: [Float]
    private var fftReal: [Float]
    private var fftImag: [Float]
    private var productReal: [Float]
    private var productImag: [Float]
    private var ifftOutput: [Float]
    private var ifftScratch: [Float]

    // Window functions (Hann for overlap-add)
    private let analysisWindow: [Float]
    private let synthesisWindow: [Float]

    // Reset flag for deferred reset on audio thread
    private let resetFlag = AtomicFlag()

    /// Latency in samples (fftSize/2 for 50% overlap)
    var latencySamples: Int { fftSize / 2 }

    /// Initialize convolver with given FFT size.
    /// - Parameter fftSize: FFT size (must be power of 2, typically 2048-8192)
    init(fftSize: Int = 4096) {
        self.fftSize = fftSize
        self.hopSize = fftSize / 2  // 50% overlap

        // Create FFT setups
        guard let fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .FORWARD
        ) else {
            fatalError("Failed to create FFT setup")
        }
        self.fftSetup = fftSetup

        guard let ifftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .INVERSE
        ) else {
            fatalError("Failed to create IFFT setup")
        }
        self.ifftSetup = ifftSetup

        // Initialize buffers
        inputBufferL = [Float](repeating: 0, count: fftSize)
        inputBufferR = [Float](repeating: 0, count: fftSize)
        outputBufferL = [Float](repeating: 0, count: fftSize)
        outputBufferR = [Float](repeating: 0, count: fftSize)
        overlapBufferL = [Float](repeating: 0, count: hopSize)
        overlapBufferR = [Float](repeating: 0, count: hopSize)

        // Double-buffered kernels (start with flat response = 1.0 real, 0.0 imag)
        kernelBufferA_Real = [Float](repeating: 1.0, count: fftSize)
        kernelBufferA_Imag = [Float](repeating: 0, count: fftSize)
        kernelBufferB_Real = [Float](repeating: 1.0, count: fftSize)
        kernelBufferB_Imag = [Float](repeating: 0, count: fftSize)

        // Processing buffers
        windowedInput = [Float](repeating: 0, count: fftSize)
        fftReal = [Float](repeating: 0, count: fftSize)
        fftImag = [Float](repeating: 0, count: fftSize)
        productReal = [Float](repeating: 0, count: fftSize)
        productImag = [Float](repeating: 0, count: fftSize)
        ifftOutput = [Float](repeating: 0, count: fftSize)
        ifftScratch = [Float](repeating: 0, count: fftSize)

        // Create Hann windows
        var analysis = [Float](repeating: 0, count: fftSize)
        var synthesis = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&analysis, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_hann_window(&synthesis, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        analysisWindow = analysis
        synthesisWindow = synthesis
    }

    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
        vDSP_DFT_DestroySetup(ifftSetup)
    }

    // MARK: - Kernel Management

    /// Set frequency-domain kernel for convolution.
    /// Thread-safe: can be called from any thread.
    /// - Parameters:
    ///   - real: Real part of frequency-domain kernel
    ///   - imag: Imaginary part of frequency-domain kernel
    func setKernel(real: [Float], imag: [Float]) {
        precondition(real.count == fftSize && imag.count == fftSize,
                     "Kernel size must match FFT size")

        // Hold lock during entire update to prevent race with concurrent calls
        // This is acceptable since kernel updates are infrequent (parameter changes only)
        os_unfair_lock_lock(&kernelSwapLock)
        defer { os_unfair_lock_unlock(&kernelSwapLock) }

        // Write to inactive buffer, then swap
        let targetIsA = !activeKernelIsA
        if targetIsA {
            for i in 0..<fftSize {
                kernelBufferA_Real[i] = real[i]
                kernelBufferA_Imag[i] = imag[i]
            }
        } else {
            for i in 0..<fftSize {
                kernelBufferB_Real[i] = real[i]
                kernelBufferB_Imag[i] = imag[i]
            }
        }
        activeKernelIsA = targetIsA
    }

    /// Get read-only access to the FFT setup for external kernel computation.
    var forwardFFTSetup: vDSP_DFT_Setup { fftSetup }

    /// Copy kernel directly to inactive buffer and swap.
    /// For use when caller has already computed FFT of kernel.
    /// - Parameters:
    ///   - computeKernel: Closure that writes kernel to provided buffers
    func updateKernel(_ computeKernel: (_ realBuffer: inout [Float], _ imagBuffer: inout [Float], _ fftSetup: vDSP_DFT_Setup) -> Void) {
        // Hold lock during entire update to prevent race with concurrent calls
        // This is acceptable since kernel updates are infrequent (parameter changes only)
        os_unfair_lock_lock(&kernelSwapLock)
        defer { os_unfair_lock_unlock(&kernelSwapLock) }

        // Write to inactive buffer, then swap
        let targetIsA = !activeKernelIsA
        if targetIsA {
            computeKernel(&kernelBufferA_Real, &kernelBufferA_Imag, fftSetup)
        } else {
            computeKernel(&kernelBufferB_Real, &kernelBufferB_Imag, fftSetup)
        }
        activeKernelIsA = targetIsA
    }

    // MARK: - Processing (audio thread only)

    /// Process a single stereo sample.
    /// Returns the output with latency of fftSize/2 samples.
    /// - Parameters:
    ///   - left: Left channel input
    ///   - right: Right channel input
    /// - Returns: Processed stereo output
    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Handle deferred reset on audio thread
        performResetIfNeeded()

        // Add input to buffer (write to second half for correct overlap-add)
        inputBufferL[hopSize + writePosition] = left
        inputBufferR[hopSize + writePosition] = right

        // Get output from previous processing
        let outL = outputBufferL[writePosition]
        let outR = outputBufferR[writePosition]

        writePosition += 1

        // Process when we have a full hop
        if writePosition >= hopSize {
            processBlock()
            writePosition = 0
        }

        return (outL, outR)
    }

    /// Process a block using overlap-add convolution.
    private func processBlock() {
        // Get active kernel pointers (very brief lock)
        os_unfair_lock_lock(&kernelSwapLock)
        let useA = activeKernelIsA
        os_unfair_lock_unlock(&kernelSwapLock)

        let kernelReal = useA ? kernelBufferA_Real : kernelBufferB_Real
        let kernelImag = useA ? kernelBufferA_Imag : kernelBufferB_Imag

        // Process left channel
        processChannel(input: inputBufferL, output: &outputBufferL, overlap: &overlapBufferL,
                       kernelReal: kernelReal, kernelImag: kernelImag)

        // Process right channel
        processChannel(input: inputBufferR, output: &outputBufferR, overlap: &overlapBufferR,
                       kernelReal: kernelReal, kernelImag: kernelImag)

        // Shift input buffers (keep second half for next frame's overlap)
        for i in 0..<hopSize {
            inputBufferL[i] = inputBufferL[i + hopSize]
            inputBufferR[i] = inputBufferR[i + hopSize]
        }
    }

    private func processChannel(input: [Float], output: inout [Float], overlap: inout [Float],
                                 kernelReal: [Float], kernelImag: [Float]) {
        // Apply analysis window
        vDSP_vmul(input, 1, analysisWindow, 1, &windowedInput, 1, vDSP_Length(fftSize))

        // Clear fftImag (no allocation)
        vDSP_vclr(&fftImag, 1, vDSP_Length(fftSize))

        // Forward FFT
        vDSP_DFT_Execute(fftSetup, windowedInput, fftImag, &fftReal, &fftImag)

        // Complex multiplication with kernel (frequency domain convolution)
        // (a + bi)(c + di) = (ac - bd) + (ad + bc)i
        for i in 0..<fftSize {
            let a = fftReal[i]
            let b = fftImag[i]
            let c = kernelReal[i]
            let d = kernelImag[i]
            productReal[i] = a * c - b * d
            productImag[i] = a * d + b * c
        }

        // Inverse FFT
        vDSP_DFT_Execute(ifftSetup, productReal, productImag, &ifftOutput, &ifftScratch)

        // Normalize IFFT
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(ifftOutput, 1, &scale, &ifftOutput, 1, vDSP_Length(fftSize))

        // Apply synthesis window
        vDSP_vmul(ifftOutput, 1, synthesisWindow, 1, &ifftOutput, 1, vDSP_Length(fftSize))

        // Overlap-add
        // First half: add previous overlap
        for i in 0..<hopSize {
            output[i] = ifftOutput[i] + overlap[i]
        }

        // Second half: store for next overlap
        for i in 0..<hopSize {
            overlap[i] = ifftOutput[i + hopSize]
        }
    }

    // MARK: - Reset

    /// Request reset - actual reset happens on audio thread to avoid priority inversion.
    func reset() {
        resetFlag.set()
    }

    /// Perform deferred reset on audio thread (no lock contention).
    @inline(__always)
    private func performResetIfNeeded() {
        guard resetFlag.testAndClear() else { return }
        vDSP_vclr(&inputBufferL, 1, vDSP_Length(fftSize))
        vDSP_vclr(&inputBufferR, 1, vDSP_Length(fftSize))
        vDSP_vclr(&outputBufferL, 1, vDSP_Length(fftSize))
        vDSP_vclr(&outputBufferR, 1, vDSP_Length(fftSize))
        vDSP_vclr(&overlapBufferL, 1, vDSP_Length(hopSize))
        vDSP_vclr(&overlapBufferR, 1, vDSP_Length(hopSize))
        writePosition = 0
    }
}
