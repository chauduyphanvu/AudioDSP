import Foundation
import os

/// Linear Phase EQ using FFT convolution.
/// Eliminates phase distortion by using symmetric FIR kernels.
/// Latency: fftSize/2 samples (~43ms at 48kHz with 4096 FFT)
///
/// Architecture:
/// - Uses `OverlapAddConvolver` for real-time FFT processing
/// - Uses `LinearPhaseKernelGenerator` for FIR kernel computation
/// - Double-buffered kernel updates happen on a background thread
final class LinearPhaseEQ: @unchecked Sendable {
    private let sampleRate: Float
    private let convolver: OverlapAddConvolver
    private let kernelGenerator: LinearPhaseKernelGenerator

    // Band parameters and async update
    private var pendingBandParams: [EQBandParams]?
    private var currentBandParams: [EQBandParams] = []
    private var paramsLock = os_unfair_lock()
    private let updateQueue = DispatchQueue(label: "linearPhaseEQ.kernelUpdate", qos: .userInitiated)
    private var isUpdating: Bool = false

    /// Latency in samples
    var latencySamples: Int { convolver.latencySamples }

    /// Latency in milliseconds
    var latencyMs: Float {
        Float(latencySamples) / sampleRate * 1000
    }

    init(sampleRate: Float, fftSize: Int = 4096) {
        self.sampleRate = sampleRate
        self.convolver = OverlapAddConvolver(fftSize: fftSize)
        self.kernelGenerator = LinearPhaseKernelGenerator(fftSize: fftSize, sampleRate: sampleRate)
    }

    // MARK: - Parameter Updates

    /// Update band parameters for linear phase processing.
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

    /// Set all band parameters at once.
    func setBandParams(_ params: [EQBandParams]) {
        os_unfair_lock_lock(&paramsLock)
        pendingBandParams = params
        os_unfair_lock_unlock(&paramsLock)

        scheduleKernelUpdate()
    }

    /// Schedule async kernel update (coalesces rapid changes).
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

    /// Perform kernel update on background thread.
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

        // Generate kernel directly into convolver's inactive buffer
        convolver.updateKernel { [kernelGenerator] realBuffer, imagBuffer, fftSetup in
            kernelGenerator.generateKernel(
                params: params,
                realBuffer: &realBuffer,
                imagBuffer: &imagBuffer,
                fftSetup: fftSetup
            )
        }

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

    // MARK: - Processing (audio thread)

    /// Process a single stereo sample.
    /// Returns the output with latency of fftSize/2 samples.
    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        convolver.process(left: left, right: right)
    }

    /// Request reset - actual reset happens on audio thread to avoid priority inversion.
    func reset() {
        convolver.reset()
    }
}
