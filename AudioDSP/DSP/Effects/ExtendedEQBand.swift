import Foundation
import os

/// Extended EQ band state bundle for atomic access across threads
struct ExtendedBandState: Sendable, Equatable {
    var params: EQBandParams
    var topology: FilterTopology = .biquad
    var slope: FilterSlope = .slope12dB
    var msMode: MSMode = .stereo
    var dynamicsEnabled: Bool = false
    var dynamicsThreshold: Float = -12
    var dynamicsRatio: Float = 2.0
    var dynamicsAttackCoeff: Float = 0.01
    var dynamicsReleaseCoeff: Float = 0.001
    var proportionalQEnabled: Bool = false
    var proportionalQStrength: Float = ProportionalQ.defaultStrength
}

/// Extended EQ band with stereo processing, multiple filter topologies,
/// variable slopes, M/S processing, and dynamic EQ capabilities.
final class ExtendedEQBand: @unchecked Sendable {
    // MARK: - Stereo Filter Pairs

    private var biquadLeft: Biquad
    private var biquadRight: Biquad
    private var svfLeft: StateVariableFilter
    private var svfRight: StateVariableFilter
    private var cascadedLeft: CascadedFilter?
    private var cascadedRight: CascadedFilter?

    // MARK: - Thread-Safe State

    private let state: ThreadSafeValue<ExtendedBandState>
    private let enabledFlag: AtomicBool
    private let sampleRate: Float

    // MARK: - Dynamic EQ State (audio thread only)

    private var envelopeL: Float = 0
    private var envelopeR: Float = 0
    private var sidechainFilter: Biquad

    // MARK: - Public Accessors

    var enabled: Bool { enabledFlag.value }
    var bandType: BandType { state.read().params.bandType }
    var frequency: Float { state.read().params.frequency }
    var gainDb: Float { state.read().params.gainDb }
    var q: Float { state.read().params.q }
    var solo: Bool { state.read().params.solo }
    var currentSlope: FilterSlope { state.read().slope }
    var currentMSMode: MSMode { state.read().msMode }
    var currentTopology: FilterTopology { state.read().topology }

    // MARK: - Initialization

    init(sampleRate: Float, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        self.sampleRate = sampleRate

        let initialParams = EQBandParams(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q)
        self.state = ThreadSafeValue(ExtendedBandState(params: initialParams))
        self.enabledFlag = AtomicBool(true)

        let biquadParams = BiquadParams(
            filterType: bandType.toBiquadType(gainDb: gainDb),
            frequency: frequency,
            q: q,
            gainDb: gainDb
        )

        self.biquadLeft = Biquad(params: biquadParams, sampleRate: sampleRate)
        self.biquadRight = Biquad(params: biquadParams, sampleRate: sampleRate)
        self.svfLeft = StateVariableFilter(sampleRate: sampleRate)
        self.svfRight = StateVariableFilter(sampleRate: sampleRate)

        self.sidechainFilter = Biquad(params: BiquadParams(
            filterType: .peak(gainDb: 0),
            frequency: frequency,
            q: 1.0,
            gainDb: 0
        ), sampleRate: sampleRate)

        updateSVFParams()
    }

    // MARK: - Processing

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        guard enabledFlag.value else { return (left, right) }

        let currentState = state.read()
        let currentTopology = currentState.topology
        let currentSlope = currentState.slope
        let currentMsMode = currentState.msMode
        let currentBandType = currentState.params.bandType
        let dynEnabled = currentState.dynamicsEnabled
        let dynThreshold = currentState.dynamicsThreshold
        let dynRatio = currentState.dynamicsRatio
        let attackCoeff = currentState.dynamicsAttackCoeff
        let releaseCoeff = currentState.dynamicsReleaseCoeff

        var l = left
        var r = right

        // Apply dynamic EQ if enabled
        if dynEnabled {
            (l, r) = applyDynamics(
                left: l,
                right: r,
                threshold: dynThreshold,
                ratio: dynRatio,
                attackCoeff: attackCoeff,
                releaseCoeff: releaseCoeff
            )
        }

        // M/S processing wrapper
        let result = MidSideEncoder.process(
            left: l,
            right: r,
            mode: currentMsMode,
            processL: { sample in
                self.processFilterSample(sample, isLeft: true, topology: currentTopology, slope: currentSlope, bandType: currentBandType)
            },
            processR: { sample in
                self.processFilterSample(sample, isLeft: false, topology: currentTopology, slope: currentSlope, bandType: currentBandType)
            }
        )

        return result
    }

    @inline(__always)
    private func applyDynamics(
        left: Float,
        right: Float,
        threshold: Float,
        ratio: Float,
        attackCoeff: Float,
        releaseCoeff: Float
    ) -> (Float, Float) {
        let sidechainMono = (left + right) * 0.5
        let sidechainFiltered = sidechainFilter.process(sidechainMono)
        let sidechainLevel = abs(sidechainFiltered)

        // Envelope follower
        if sidechainLevel > envelopeL {
            envelopeL = envelopeL + attackCoeff * (sidechainLevel - envelopeL)
        } else {
            envelopeL = envelopeL + releaseCoeff * (sidechainLevel - envelopeL)
        }
        envelopeR = envelopeL  // Linked stereo

        // Calculate gain reduction
        let envDb = linearToDb(envelopeL + 1e-10)
        if envDb > threshold {
            let overThreshold = envDb - threshold
            let gainReduction = overThreshold * (1 - 1 / ratio)
            let gainLinear = dbToLinear(-gainReduction)
            return (left * gainLinear, right * gainLinear)
        }

        return (left, right)
    }

    @inline(__always)
    private func processFilterSample(_ sample: Float, isLeft: Bool, topology: FilterTopology, slope: FilterSlope, bandType: BandType) -> Float {
        // For LP/HP with non-standard slopes, use cascaded filter
        if FilterSlope.appliesTo(bandType) && slope != .slope12dB {
            if isLeft {
                return cascadedLeft?.process(sample) ?? sample
            } else {
                return cascadedRight?.process(sample) ?? sample
            }
        }

        // Standard processing with selected topology
        switch topology {
        case .biquad:
            return isLeft ? biquadLeft.process(sample) : biquadRight.process(sample)
        case .svf:
            return isLeft ? svfLeft.process(sample) : svfRight.process(sample)
        }
    }

    // MARK: - Parameter Updates

    /// Update band parameters from UI thread.
    ///
    /// Thread Safety Note: This method updates state atomically, then updates the underlying
    /// filters separately. There is a brief window (a few samples) where the cached state
    /// in process() may be slightly inconsistent with actual filter coefficients. This is
    /// acceptable for audio DSP where brief transients during parameter changes are tolerable.
    /// The underlying Biquad/SVF filters handle their own parameter smoothing to prevent clicks.
    func update(bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        let proportionalQSettings: (enabled: Bool, strength: Float) = state.modifyAndReturn { s in
            s.params = EQBandParams(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q, solo: s.params.solo)
            return (s.proportionalQEnabled, s.proportionalQStrength)
        }

        // Apply proportional Q for analog-style behavior
        let effectiveQ = proportionalQSettings.enabled
            ? ProportionalQ.calculate(baseQ: q, gainDb: gainDb, strength: proportionalQSettings.strength, bandType: bandType)
            : q

        let biquadParams = BiquadParams(
            filterType: bandType.toBiquadType(gainDb: gainDb),
            frequency: frequency,
            q: effectiveQ,
            gainDb: gainDb
        )

        biquadLeft.updateParameters(biquadParams)
        biquadRight.updateParameters(biquadParams)
        updateSVFParams(effectiveQ: effectiveQ)

        if FilterSlope.appliesTo(bandType) {
            cascadedLeft?.updateParameters(frequency: frequency, q: effectiveQ, isHighPass: bandType == .highPass)
            cascadedRight?.updateParameters(frequency: frequency, q: effectiveQ, isHighPass: bandType == .highPass)
        }

        sidechainFilter.updateParameters(BiquadParams(
            filterType: .peak(gainDb: 0),
            frequency: frequency,
            q: 1.0,
            gainDb: 0
        ))
    }

    func setSlope(_ newSlope: FilterSlope) {
        let currentParams: EQBandParams = state.modifyAndReturn { s in
            s.slope = newSlope
            return s.params
        }

        if FilterSlope.appliesTo(currentParams.bandType) {
            cascadedLeft = CascadedFilter(slope: newSlope, sampleRate: sampleRate)
            cascadedRight = CascadedFilter(slope: newSlope, sampleRate: sampleRate)
            cascadedLeft?.updateParameters(
                frequency: currentParams.frequency,
                q: currentParams.q,
                isHighPass: currentParams.bandType == .highPass
            )
            cascadedRight?.updateParameters(
                frequency: currentParams.frequency,
                q: currentParams.q,
                isHighPass: currentParams.bandType == .highPass
            )
        }
    }

    func setTopology(_ newTopology: FilterTopology) {
        state.modify { $0.topology = newTopology }
    }

    func setMSMode(_ newMode: MSMode) {
        state.modify { $0.msMode = newMode }
    }

    func setDynamics(enabled: Bool, threshold: Float, ratio: Float, attackMs: Float, releaseMs: Float) {
        state.modify { s in
            s.dynamicsEnabled = enabled
            s.dynamicsThreshold = threshold
            s.dynamicsRatio = max(1, ratio)
            s.dynamicsAttackCoeff = 1.0 - exp(-1.0 / (sampleRate * attackMs / 1000))
            s.dynamicsReleaseCoeff = 1.0 - exp(-1.0 / (sampleRate * releaseMs / 1000))
        }
    }

    func setSolo(_ solo: Bool) {
        state.modify { s in
            s.params = EQBandParams(
                bandType: s.params.bandType,
                frequency: s.params.frequency,
                gainDb: s.params.gainDb,
                q: s.params.q,
                solo: solo
            )
        }
    }

    func setEnabled(_ enabled: Bool) {
        enabledFlag.value = enabled
        if enabled {
            reset()
        }
    }

    // MARK: - Reset

    func reset() {
        biquadLeft.reset()
        biquadRight.reset()
        svfLeft.reset()
        svfRight.reset()
        cascadedLeft?.reset()
        cascadedRight?.reset()
        sidechainFilter.reset()
        envelopeL = 0
        envelopeR = 0
    }

    /// Configure proportional Q for analog-style EQ behavior.
    ///
    /// - Parameters:
    ///   - enabled: Whether to enable proportional Q
    ///   - strength: How much gain affects Q (0.08 = subtle, 0.15 = aggressive)
    func setProportionalQ(enabled: Bool, strength: Float = ProportionalQ.defaultStrength) {
        let currentParams: EQBandParams = state.modifyAndReturn { s in
            s.proportionalQEnabled = enabled
            s.proportionalQStrength = max(0, min(0.3, strength))
            return s.params
        }

        // Re-apply current parameters with new proportional Q setting
        update(
            bandType: currentParams.bandType,
            frequency: currentParams.frequency,
            gainDb: currentParams.gainDb,
            q: currentParams.q
        )
    }

    var proportionalQEnabled: Bool { state.read().proportionalQEnabled }
    var proportionalQStrength: Float { state.read().proportionalQStrength }

    // MARK: - Private Helpers

    private func updateSVFParams(effectiveQ: Float? = nil) {
        let currentState = state.read()
        let params = currentState.params

        // Use provided effectiveQ or calculate if proportional Q is enabled
        let qToUse: Float
        if let effective = effectiveQ {
            qToUse = effective
        } else if currentState.proportionalQEnabled {
            qToUse = ProportionalQ.calculate(
                baseQ: params.q,
                gainDb: params.gainDb,
                strength: currentState.proportionalQStrength,
                bandType: params.bandType
            )
        } else {
            qToUse = params.q
        }

        let svfMode: SVFMode
        switch params.bandType {
        case .lowShelf: svfMode = .lowShelf
        case .highShelf: svfMode = .highShelf
        case .peak: svfMode = .peak
        case .lowPass: svfMode = .lowpass
        case .highPass: svfMode = .highpass
        }
        svfLeft.setParameters(mode: svfMode, frequency: params.frequency, q: qToUse, gainDb: params.gainDb)
        svfRight.setParameters(mode: svfMode, frequency: params.frequency, q: qToUse, gainDb: params.gainDb)
    }
}
