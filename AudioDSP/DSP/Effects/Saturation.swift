import Foundation

/// Thread-safe saturation processor with multiple analog-modeled modes.
/// Uses 2x oversampling to prevent harmonic aliasing from nonlinearities.
final class Saturation: @unchecked Sendable {
    /// Bundled parameter state for atomic access
    private struct Params: Sendable {
        var mode: SaturationMode = .clean
        var drive: Float = 0.0
        var mix: Float = 1.0
        var outputGain: Float = 0.0
    }

    private let params: ThreadSafeValue<Params>
    private let resetFlag: AtomicFlag

    // Soft clipping constants
    private let softClipThreshold: Float = 0.9
    private let softClipKnee: Float = 0.1

    // 2x oversampling state (audio thread only)
    private var oversamplePrevL: Float = 0
    private var oversamplePrevR: Float = 0
    private var downsamplePrevClipL: Float = 0
    private var downsamplePrevClipR: Float = 0

    // Tape mode HF rolloff state
    private var tapeLpStateL: Float = 0
    private var tapeLpStateR: Float = 0
    private let tapeLpCoeff: Float = 0.3

    init() {
        params = ThreadSafeValue(Params())
        resetFlag = AtomicFlag()
    }

    // MARK: - Parameter Access

    func setMode(_ newMode: SaturationMode) {
        params.modify { $0.mode = newMode }
    }

    func setDrive(_ newDrive: Float) {
        params.modify { $0.drive = newDrive.clamped(to: 0...24) }
    }

    func setMix(_ newMix: Float) {
        params.modify { $0.mix = newMix.clamped(to: 0...1) }
    }

    func setOutputGain(_ newGain: Float) {
        params.modify { $0.outputGain = newGain.clamped(to: -24...24) }
    }

    func getMode() -> SaturationMode { params.read().mode }
    func getDrive() -> Float { params.read().drive }

    // MARK: - Processing

    /// Process stereo samples with 2x oversampled saturation
    @inline(__always)
    func process(left: Float, right: Float) -> (Float, Float) {
        performResetIfNeeded()

        let p = params.read()
        let currentMode = p.mode
        let currentDrive = p.drive
        let currentMix = p.mix
        let currentOutputGain = p.outputGain

        // Fast path for clean mode with no drive
        if currentMode == .clean && currentDrive < 0.1 {
            // Just apply threshold-based clean limiting
            let maxSample = max(abs(left), abs(right))
            if maxSample <= softClipThreshold {
                oversamplePrevL = left
                oversamplePrevR = right
                downsamplePrevClipL = left
                downsamplePrevClipR = right
                return (left, right)
            }
        }

        // Store dry signal for mix
        let dryL = left
        let dryR = right

        // 2x upsample using linear interpolation
        let upL0 = (oversamplePrevL + left) * 0.5
        let upL1 = left
        let upR0 = (oversamplePrevR + right) * 0.5
        let upR1 = right

        // Apply saturation at 2x rate using extracted waveshaping functions
        var clipL0 = WaveshapingFunctions.saturate(
            upL0, mode: currentMode, driveAmount: currentDrive,
            threshold: softClipThreshold, knee: softClipKnee
        )
        var clipL1 = WaveshapingFunctions.saturate(
            upL1, mode: currentMode, driveAmount: currentDrive,
            threshold: softClipThreshold, knee: softClipKnee
        )
        var clipR0 = WaveshapingFunctions.saturate(
            upR0, mode: currentMode, driveAmount: currentDrive,
            threshold: softClipThreshold, knee: softClipKnee
        )
        var clipR1 = WaveshapingFunctions.saturate(
            upR1, mode: currentMode, driveAmount: currentDrive,
            threshold: softClipThreshold, knee: softClipKnee
        )

        // Tape mode: apply subtle HF rolloff (one-pole lowpass on oversampled signal)
        if currentMode == .tape {
            tapeLpStateL = tapeLpStateL + tapeLpCoeff * (clipL1 - tapeLpStateL)
            tapeLpStateR = tapeLpStateR + tapeLpCoeff * (clipR1 - tapeLpStateR)
            // Blend in some of the filtered signal
            clipL0 = clipL0 * 0.9 + tapeLpStateL * 0.1
            clipL1 = clipL1 * 0.9 + tapeLpStateL * 0.1
            clipR0 = clipR0 * 0.9 + tapeLpStateR * 0.1
            clipR1 = clipR1 * 0.9 + tapeLpStateR * 0.1
        }

        // Store for next interpolation
        oversamplePrevL = left
        oversamplePrevR = right

        // 3-tap downsample filter [0.25, 0.5, 0.25]
        var outL = 0.25 * downsamplePrevClipL + 0.5 * clipL0 + 0.25 * clipL1
        var outR = 0.25 * downsamplePrevClipR + 0.5 * clipR0 + 0.25 * clipR1

        // Store clipped samples for next iteration
        downsamplePrevClipL = clipL1
        downsamplePrevClipR = clipR1

        // Apply output gain compensation
        if currentOutputGain != 0 {
            let gainLinear = powf(10.0, currentOutputGain / 20.0)
            outL *= gainLinear
            outR *= gainLinear
        }

        // Apply wet/dry mix
        if currentMix < 1.0 {
            outL = dryL * (1.0 - currentMix) + outL * currentMix
            outR = dryR * (1.0 - currentMix) + outR * currentMix
        }

        return (outL, outR)
    }

    func reset() {
        resetFlag.set()
    }

    @inline(__always)
    private func performResetIfNeeded() {
        guard resetFlag.testAndClear() else { return }
        oversamplePrevL = 0
        oversamplePrevR = 0
        downsamplePrevClipL = 0
        downsamplePrevClipR = 0
        tapeLpStateL = 0
        tapeLpStateR = 0
    }
}
