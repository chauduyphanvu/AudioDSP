import Accelerate
import Foundation

// MARK: - Linear Phase Kernel Generator

/// Generates linear-phase FIR kernels from EQ band parameters.
/// Produces symmetric impulse responses that eliminate phase distortion.
///
/// Thread Safety:
/// - Each instance should only be used from a single thread at a time
/// - Uses internal scratch buffers that would race if called concurrently
/// - Create separate instances if concurrent kernel generation is needed
final class LinearPhaseKernelGenerator: @unchecked Sendable {
    let fftSize: Int
    let sampleRate: Float

    // FFT setup for IFFT during kernel generation
    private let ifftSetup: vDSP_DFT_Setup

    // Scratch buffers (used only during generation, not during audio processing)
    private var scratchMagnitude: [Float]
    private var scratchFirKernel: [Float]
    private var scratchShifted: [Float]
    private var scratchReal: [Float]
    private var scratchImag: [Float]

    /// Initialize kernel generator.
    /// - Parameters:
    ///   - fftSize: FFT size for kernel (must match convolver)
    ///   - sampleRate: Audio sample rate in Hz
    init(fftSize: Int, sampleRate: Float) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate

        guard let ifftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .INVERSE
        ) else {
            fatalError("Failed to create IFFT setup for kernel generator")
        }
        self.ifftSetup = ifftSetup

        // Initialize scratch buffers
        scratchMagnitude = [Float](repeating: 0, count: fftSize / 2 + 1)
        scratchFirKernel = [Float](repeating: 0, count: fftSize)
        scratchShifted = [Float](repeating: 0, count: fftSize)
        scratchReal = [Float](repeating: 0, count: fftSize)
        scratchImag = [Float](repeating: 0, count: fftSize)
    }

    deinit {
        vDSP_DFT_DestroySetup(ifftSetup)
    }

    // MARK: - Kernel Generation

    /// Generate frequency-domain kernel from EQ band parameters.
    /// Computes the FFT of a linear-phase FIR filter directly into the provided buffers.
    /// - Parameters:
    ///   - params: Array of EQ band parameters
    ///   - realBuffer: Output buffer for real part of frequency-domain kernel
    ///   - imagBuffer: Output buffer for imaginary part of frequency-domain kernel
    ///   - fftSetup: Forward FFT setup to use for kernel computation
    func generateKernel(
        params: [EQBandParams],
        realBuffer: inout [Float],
        imagBuffer: inout [Float],
        fftSetup: vDSP_DFT_Setup
    ) {
        // Reset magnitude response to flat
        for i in 0..<scratchMagnitude.count {
            scratchMagnitude[i] = 1.0
        }

        // Accumulate magnitude response from all bands
        for band in params {
            accumulateBandMagnitude(band)
        }

        // Create zero-phase frequency-domain representation
        createZeroPhaseKernel()

        // Convert to time domain via IFFT
        convertToTimeDomain()

        // Apply Kaiser window to the centered impulse response
        KaiserWindow.apply(to: &scratchShifted, beta: 8.0)

        // Clear imaginary for FFT of real kernel
        vDSP_vclr(&scratchImag, 1, vDSP_Length(fftSize))

        // Compute FFT of kernel into output buffers
        vDSP_DFT_Execute(fftSetup, scratchShifted, scratchImag, &realBuffer, &imagBuffer)
    }

    // MARK: - Private Helpers

    /// Accumulate magnitude response from a single EQ band.
    private func accumulateBandMagnitude(_ band: EQBandParams) {
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

            let magnitude = computeBiquadMagnitude(coeffs: coeffs, frequency: freq)
            scratchMagnitude[bin] *= magnitude
        }
    }

    /// Compute biquad filter magnitude at a given frequency.
    private func computeBiquadMagnitude(coeffs: BiquadCoefficients, frequency: Float) -> Float {
        let omega = 2.0 * Float.pi * frequency / sampleRate
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

        return numMag / max(denMag, 1e-10)
    }

    /// Create frequency domain kernel with zero phase (magnitude only).
    private func createZeroPhaseKernel() {
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
    }

    /// Convert frequency domain kernel to time domain and center it.
    private func convertToTimeDomain() {
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
    }
}
