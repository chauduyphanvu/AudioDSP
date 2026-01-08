import Accelerate
import Foundation
import os

/// Linear Phase EQ using FFT convolution
/// Eliminates phase distortion by using symmetric FIR kernels
/// Latency: fftSize/2 samples (~43ms at 48kHz with 4096 FFT)
final class LinearPhaseEQ: @unchecked Sendable {
    private let fftSize: Int
    private let hopSize: Int
    private let sampleRate: Float

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

    // Scratch buffers for kernel generation (used only on background thread)
    private var scratchMagnitude: [Float]
    private var scratchFirKernel: [Float]
    private var scratchShifted: [Float]
    private var scratchReal: [Float]
    private var scratchImag: [Float]

    // Processing buffers (pre-allocated, no allocation during process)
    private var windowedInput: [Float]
    private var fftReal: [Float]
    private var fftImag: [Float]
    private var productReal: [Float]
    private var productImag: [Float]
    private var ifftOutput: [Float]
    private var ifftScratch: [Float]

    // Window function (Hann for overlap-add)
    private let analysisWindow: [Float]
    private let synthesisWindow: [Float]

    // Band parameters and async update
    private var pendingBandParams: [EQBandParams]?
    private var currentBandParams: [EQBandParams] = []
    private var paramsLock = os_unfair_lock()
    private let updateQueue = DispatchQueue(label: "linearPhaseEQ.kernelUpdate", qos: .userInitiated)
    private var isUpdating: Bool = false

    // Reset flag for deferred reset on audio thread
    private let resetFlag = AtomicFlag()

    /// Latency in samples
    var latencySamples: Int { fftSize / 2 }

    init(sampleRate: Float, fftSize: Int = 4096) {
        self.sampleRate = sampleRate
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

        // Scratch buffers for background kernel generation
        scratchMagnitude = [Float](repeating: 0, count: fftSize / 2 + 1)
        scratchFirKernel = [Float](repeating: 0, count: fftSize)
        scratchShifted = [Float](repeating: 0, count: fftSize)
        scratchReal = [Float](repeating: 0, count: fftSize)
        scratchImag = [Float](repeating: 0, count: fftSize)

        // Processing buffers
        windowedInput = [Float](repeating: 0, count: fftSize)
        fftReal = [Float](repeating: 0, count: fftSize)
        fftImag = [Float](repeating: 0, count: fftSize)
        productReal = [Float](repeating: 0, count: fftSize)
        productImag = [Float](repeating: 0, count: fftSize)
        ifftOutput = [Float](repeating: 0, count: fftSize)
        ifftScratch = [Float](repeating: 0, count: fftSize)

        // Create windows
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

    // MARK: - Parameter Updates

    /// Update band parameters for linear phase processing
    func updateBand(_ index: Int, params: EQBandParams) {
        os_unfair_lock_lock(&paramsLock)
        var updated = currentBandParams
        while updated.count <= index {
            updated.append(EQBandParams())
        }
        updated[index] = params
        pendingBandParams = updated
        os_unfair_lock_unlock(&paramsLock)

        scheduleKernelUpdate()
    }

    /// Set all band parameters at once
    func setBandParams(_ params: [EQBandParams]) {
        os_unfair_lock_lock(&paramsLock)
        pendingBandParams = params
        os_unfair_lock_unlock(&paramsLock)

        scheduleKernelUpdate()
    }

    /// Schedule async kernel update (coalesces rapid changes)
    private func scheduleKernelUpdate() {
        os_unfair_lock_lock(&paramsLock)
        if isUpdating {
            os_unfair_lock_unlock(&paramsLock)
            return
        }
        isUpdating = true
        os_unfair_lock_unlock(&paramsLock)

        updateQueue.async { [weak self] in
            self?.performKernelUpdate()
        }
    }

    /// Perform kernel update on background thread
    private func performKernelUpdate() {
        // Get pending params
        os_unfair_lock_lock(&paramsLock)
        guard let params = pendingBandParams else {
            isUpdating = false
            os_unfair_lock_unlock(&paramsLock)
            return
        }
        pendingBandParams = nil
        currentBandParams = params
        os_unfair_lock_unlock(&paramsLock)

        // Generate kernel into inactive buffer (no locks needed for scratch buffers)
        generateLinearPhaseFIR(params: params)

        // Check for more pending updates
        os_unfair_lock_lock(&paramsLock)
        if pendingBandParams != nil {
            os_unfair_lock_unlock(&paramsLock)
            performKernelUpdate()
        } else {
            isUpdating = false
            os_unfair_lock_unlock(&paramsLock)
        }
    }

    // MARK: - FIR Generation (runs on background thread)

    /// Generate linear phase FIR kernel from band parameters
    private func generateLinearPhaseFIR(params: [EQBandParams]) {
        // Reset magnitude response to flat
        for i in 0..<scratchMagnitude.count {
            scratchMagnitude[i] = 1.0
        }

        for band in params {
            for bin in 0..<(fftSize / 2 + 1) {
                let freq = Float(bin) * sampleRate / Float(fftSize)
                if freq < 20 || freq > sampleRate / 2 * 0.99 { continue }

                // Calculate biquad magnitude at this frequency
                let biquadType = band.bandType.toBiquadType(gainDb: band.gainDb)
                let coeffs = BiquadCoefficients.calculate(
                    type: biquadType,
                    sampleRate: sampleRate,
                    frequency: band.frequency,
                    q: band.q
                )

                let omega = 2.0 * Float.pi * freq / sampleRate
                let cosOmega = cos(omega)
                let cos2Omega = cos(2.0 * omega)
                let sinOmega = sin(omega)
                let sin2Omega = sin(2.0 * omega)

                let numReal: Float = coeffs.b0 + coeffs.b1 * cosOmega + coeffs.b2 * cos2Omega
                let numImag: Float = -coeffs.b1 * sinOmega - coeffs.b2 * sin2Omega
                let denReal: Float = 1.0 + coeffs.a1 * cosOmega + coeffs.a2 * cos2Omega
                let denImag: Float = -coeffs.a1 * sinOmega - coeffs.a2 * sin2Omega

                let numMagSq: Float = numReal * numReal + numImag * numImag
                let denMagSq: Float = denReal * denReal + denImag * denImag
                let numMag = sqrt(numMagSq)
                let denMag = sqrt(denMagSq)

                scratchMagnitude[bin] *= numMag / max(denMag, 1e-10)
            }
        }

        // Create frequency domain kernel with zero phase
        // Positive frequencies
        for bin in 0..<(fftSize / 2 + 1) {
            scratchReal[bin] = scratchMagnitude[bin]
            scratchImag[bin] = 0
        }

        // Negative frequencies (conjugate symmetry for real output)
        for bin in 1..<(fftSize / 2) {
            scratchReal[fftSize - bin] = scratchMagnitude[bin]
            scratchImag[fftSize - bin] = 0
        }

        // Inverse FFT to get time-domain impulse response
        vDSP_DFT_Execute(ifftSetup, scratchReal, scratchImag, &scratchFirKernel, &scratchImag)

        // Normalize IFFT output
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(scratchFirKernel, 1, &scale, &scratchFirKernel, 1, vDSP_Length(fftSize))

        // Circular shift to center the impulse response
        let shiftAmount = fftSize / 2
        for i in 0..<fftSize {
            let srcIndex = (i + shiftAmount) % fftSize
            scratchShifted[i] = scratchFirKernel[srcIndex]
        }

        // Apply Kaiser window
        applyKaiserWindow(&scratchShifted, beta: 8.0)

        // Zero out imaginary for FFT of real kernel
        vDSP_vclr(&scratchImag, 1, vDSP_Length(fftSize))

        // Get target buffer (inactive one)
        os_unfair_lock_lock(&kernelSwapLock)
        let targetIsA = !activeKernelIsA
        os_unfair_lock_unlock(&kernelSwapLock)

        // Compute FFT of kernel into target buffer
        if targetIsA {
            vDSP_DFT_Execute(fftSetup, scratchShifted, scratchImag, &kernelBufferA_Real, &kernelBufferA_Imag)
        } else {
            vDSP_DFT_Execute(fftSetup, scratchShifted, scratchImag, &kernelBufferB_Real, &kernelBufferB_Imag)
        }

        // Swap active buffer
        os_unfair_lock_lock(&kernelSwapLock)
        activeKernelIsA = targetIsA
        os_unfair_lock_unlock(&kernelSwapLock)
    }

    /// Apply Kaiser window to the FIR kernel
    private func applyKaiserWindow(_ kernel: inout [Float], beta: Float) {
        let N = kernel.count
        let halfN = Float(N - 1) / 2.0
        let i0Beta = besselI0(beta)

        for n in 0..<N {
            let x = (Float(n) - halfN) / halfN
            let arg = beta * sqrt(max(0, 1 - x * x))
            let window = besselI0(arg) / i0Beta
            kernel[n] *= window
        }
    }

    /// Zeroth-order modified Bessel function of the first kind
    private func besselI0(_ x: Float) -> Float {
        var sum: Float = 1.0
        var term: Float = 1.0
        let x2 = x * x / 4.0

        for k in 1...20 {
            term *= x2 / Float(k * k)
            sum += term
            if term < 1e-10 { break }
        }
        return sum
    }

    // MARK: - Processing (audio thread, no locks on kernel read)

    /// Process a single stereo sample
    /// Returns the output with latency of fftSize/2 samples
    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Handle deferred reset on audio thread
        performResetIfNeeded()

        // Add input to buffer
        inputBufferL[writePosition] = left
        inputBufferR[writePosition] = right

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

    /// Process a block using overlap-add convolution
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

    /// Request reset - actual reset happens on audio thread to avoid priority inversion
    func reset() {
        resetFlag.set()
    }

    /// Perform deferred reset on audio thread (no lock contention)
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

    /// Get latency in milliseconds
    var latencyMs: Float {
        Float(latencySamples) / sampleRate * 1000
    }
}
