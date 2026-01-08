import Foundation
import os

/// EQ processing mode
enum EQProcessingMode: Int, Codable, CaseIterable, Sendable {
    case minimumPhase = 0
    case linearPhase = 1

    var displayName: String {
        switch self {
        case .minimumPhase: return "Minimum Phase"
        case .linearPhase: return "Linear Phase"
        }
    }

    var description: String {
        switch self {
        case .minimumPhase: return "Low latency, natural phase response"
        case .linearPhase: return "Zero phase distortion, ~43ms latency"
        }
    }
}

/// Extended EQ band with additional features
final class ExtendedEQBand: @unchecked Sendable {
    // Stereo filter pairs
    private var biquadLeft: Biquad
    private var biquadRight: Biquad
    private var svfLeft: StateVariableFilter
    private var svfRight: StateVariableFilter
    private var cascadedLeft: CascadedFilter?
    private var cascadedRight: CascadedFilter?

    // Thread-safe state using new utilities
    private let state: ThreadSafeValue<BandState>
    private let enabledFlag: AtomicBool
    private let sampleRate: Float

    // Dynamic EQ envelope state (audio thread only, no lock needed)
    private var envelopeL: Float = 0
    private var envelopeR: Float = 0
    private var sidechainFilter: Biquad

    /// Internal state bundle for atomic access
    private struct BandState {
        var params: EQBandParams
        var topology: FilterTopology = .biquad
        var slope: FilterSlope = .slope12dB
        var msMode: MSMode = .stereo
        var dynamicsEnabled: Bool = false
        var dynamicsThreshold: Float = -12
        var dynamicsRatio: Float = 2.0
        var dynamicsAttackCoeff: Float = 0.01
        var dynamicsReleaseCoeff: Float = 0.001
    }

    var enabled: Bool { enabledFlag.value }

    // Public accessors using ThreadSafeValue
    var bandType: BandType { state.read().params.bandType }
    var frequency: Float { state.read().params.frequency }
    var gainDb: Float { state.read().params.gainDb }
    var q: Float { state.read().params.q }
    var solo: Bool { state.read().params.solo }
    var currentSlope: FilterSlope { state.read().slope }
    var currentMSMode: MSMode { state.read().msMode }
    var currentTopology: FilterTopology { state.read().topology }

    init(sampleRate: Float, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        self.sampleRate = sampleRate

        let initialParams = EQBandParams(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q)
        self.state = ThreadSafeValue(BandState(params: initialParams))
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

    private func updateSVFParams() {
        let currentState = state.read()
        let params = currentState.params
        let svfMode: SVFMode
        switch params.bandType {
        case .lowShelf: svfMode = .lowShelf
        case .highShelf: svfMode = .highShelf
        case .peak: svfMode = .peak
        case .lowPass: svfMode = .lowpass
        case .highPass: svfMode = .highpass
        }
        svfLeft.setParameters(mode: svfMode, frequency: params.frequency, q: params.q, gainDb: params.gainDb)
        svfRight.setParameters(mode: svfMode, frequency: params.frequency, q: params.q, gainDb: params.gainDb)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        guard enabledFlag.value else { return (left, right) }

        // Read all state atomically
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
            if envDb > dynThreshold {
                let overThreshold = envDb - dynThreshold
                let gainReduction = overThreshold * (1 - 1 / dynRatio)
                let gainLinear = dbToLinear(-gainReduction)
                l *= gainLinear
                r *= gainLinear
            }
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

    func update(bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        state.modify { s in
            s.params = EQBandParams(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q, solo: s.params.solo)
        }

        let biquadParams = BiquadParams(
            filterType: bandType.toBiquadType(gainDb: gainDb),
            frequency: frequency,
            q: q,
            gainDb: gainDb
        )

        biquadLeft.updateParameters(biquadParams)
        biquadRight.updateParameters(biquadParams)
        updateSVFParams()

        if FilterSlope.appliesTo(bandType) {
            cascadedLeft?.updateParameters(frequency: frequency, q: q, isHighPass: bandType == .highPass)
            cascadedRight?.updateParameters(frequency: frequency, q: q, isHighPass: bandType == .highPass)
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
}

/// 5-band Parametric Equalizer with advanced features
final class ParametricEQ: Effect, @unchecked Sendable {
    private var bands: [ExtendedEQBand]
    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    let name = "Parametric EQ"

    private var saturation: Saturation
    private var linearPhaseEQ: LinearPhaseEQ?
    private let processingModeState: ThreadSafeValue<EQProcessingMode>
    private let soloMask: AtomicBitmask

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
        self.saturation = Saturation()
        self.processingModeState = ThreadSafeValue(.minimumPhase)
        self.soloMask = AtomicBitmask(0)

        bands = [
            ExtendedEQBand(sampleRate: sampleRate, bandType: .lowShelf, frequency: 80, gainDb: 0, q: 0.707),
            ExtendedEQBand(sampleRate: sampleRate, bandType: .peak, frequency: 250, gainDb: 0, q: 1.0),
            ExtendedEQBand(sampleRate: sampleRate, bandType: .peak, frequency: 1000, gainDb: 0, q: 1.0),
            ExtendedEQBand(sampleRate: sampleRate, bandType: .peak, frequency: 4000, gainDb: 0, q: 1.0),
            ExtendedEQBand(sampleRate: sampleRate, bandType: .highShelf, frequency: 12000, gainDb: 0, q: 0.707),
        ]
    }

    // MARK: - Processing Mode

    func setProcessingMode(_ mode: EQProcessingMode) {
        processingModeState.write(mode)
        if mode == .linearPhase && linearPhaseEQ == nil {
            linearPhaseEQ = LinearPhaseEQ(sampleRate: sampleRate)
            syncLinearPhaseParams()
        }
    }

    func getProcessingMode() -> EQProcessingMode {
        processingModeState.read()
    }

    /// Sync band parameters to linear phase processor
    private func syncLinearPhaseParams() {
        guard let lpEQ = linearPhaseEQ else { return }

        var params: [EQBandParams] = []
        for band in bands {
            params.append(EQBandParams(
                bandType: band.bandType,
                frequency: band.frequency,
                gainDb: band.gainDb,
                q: band.q,
                solo: band.solo
            ))
        }
        lpEQ.setBandParams(params)
    }

    // MARK: - Saturation

    /// Set saturation mode
    func setSaturationMode(_ mode: SaturationMode) {
        saturation.setMode(mode)
    }

    /// Set saturation drive (0-24 dB)
    func setSaturationDrive(_ drive: Float) {
        saturation.setDrive(drive)
    }

    func getSaturationMode() -> SaturationMode {
        saturation.getMode()
    }

    func getSaturationDrive() -> Float {
        saturation.getDrive()
    }

    // MARK: - Processing

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        let mode = processingModeState.read()
        var l = left
        var r = right

        if mode == .linearPhase, let lpEQ = linearPhaseEQ {
            let result = lpEQ.process(left: l, right: r)
            l = result.left
            r = result.right
        } else {
            let currentSoloMask = soloMask.value

            if currentSoloMask != 0 {
                for index in 0..<bands.count where soloMask.isBitSet(index) {
                    let result = bands[index].process(left: l, right: r)
                    l = result.left
                    r = result.right
                }
            } else {
                for band in bands {
                    let result = band.process(left: l, right: r)
                    l = result.left
                    r = result.right
                }
            }
        }

        return saturation.process(left: l, right: r)
    }

    func reset() {
        for band in bands {
            band.reset()
        }
        saturation.reset()
        linearPhaseEQ?.reset()
    }

    /// Get latency in samples (non-zero for linear phase mode)
    var latencySamples: Int {
        processingModeState.read() == .linearPhase ? (linearPhaseEQ?.latencySamples ?? 0) : 0
    }

    func setBand(_ index: Int, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        guard index >= 0, index < bands.count else { return }
        bands[index].update(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q)

        if processingModeState.read() == .linearPhase {
            syncLinearPhaseParams()
        }
    }

    func setSolo(_ index: Int, solo: Bool) {
        guard index >= 0, index < bands.count else { return }
        bands[index].setSolo(solo)
        soloMask.setBit(index, solo)
    }

    func setBandEnabled(_ index: Int, enabled: Bool) {
        guard index >= 0, index < bands.count else { return }
        bands[index].setEnabled(enabled)
    }

    func setBandSlope(_ index: Int, slope: FilterSlope) {
        guard index >= 0, index < bands.count else { return }
        bands[index].setSlope(slope)
    }

    func setBandTopology(_ index: Int, topology: FilterTopology) {
        guard index >= 0, index < bands.count else { return }
        bands[index].setTopology(topology)
    }

    func setBandMSMode(_ index: Int, mode: MSMode) {
        guard index >= 0, index < bands.count else { return }
        bands[index].setMSMode(mode)
    }

    func setBandDynamics(_ index: Int, enabled: Bool, threshold: Float, ratio: Float, attackMs: Float, releaseMs: Float) {
        guard index >= 0, index < bands.count else { return }
        bands[index].setDynamics(enabled: enabled, threshold: threshold, ratio: ratio, attackMs: attackMs, releaseMs: releaseMs)
    }

    func clearAllSolo() {
        for (index, band) in bands.enumerated() {
            band.setSolo(false)
            soloMask.setBit(index, false)
        }
    }

    func getBand(_ index: Int) -> ExtendedEQBand? {
        guard index >= 0, index < bands.count else { return nil }
        return bands[index]
    }

    func isBandSoloed(_ index: Int) -> Bool {
        guard index >= 0, index < bands.count else { return false }
        return soloMask.isBitSet(index)
    }

    var hasSoloedBand: Bool { soloMask.isNonZero }

    var bandCount: Int { bands.count }

    // MARK: - Parameter Interface

    var parameters: [ParameterDescriptor] {
        var params: [ParameterDescriptor] = []
        for i in 0..<bands.count {
            params.append(ParameterDescriptor("Band \(i + 1) Freq", min: 20, max: 20000, defaultValue: bands[i].frequency, unit: .hertz))
            params.append(ParameterDescriptor("Band \(i + 1) Gain", min: -24, max: 24, defaultValue: 0, unit: .decibels))
            params.append(ParameterDescriptor("Band \(i + 1) Q", min: 0.1, max: 10, defaultValue: 1.0, unit: .generic))
        }
        return params
    }

    func getParameter(_ index: Int) -> Float {
        let bandIndex = index / 3
        let paramType = index % 3

        guard let band = getBand(bandIndex) else { return 0 }

        switch paramType {
        case 0: return band.frequency
        case 1: return band.gainDb
        case 2: return band.q
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        let bandIndex = index / 3
        let paramType = index % 3

        guard let band = getBand(bandIndex) else { return }

        let freq: Float
        let gain: Float
        let q: Float

        switch paramType {
        case 0:
            freq = value.clamped(to: 20...20000)
            gain = band.gainDb
            q = band.q
        case 1:
            freq = band.frequency
            gain = value.clamped(to: -24...24)
            q = band.q
        case 2:
            freq = band.frequency
            gain = band.gainDb
            q = value.clamped(to: 0.1...10)
        default:
            return
        }

        band.update(bandType: band.bandType, frequency: freq, gainDb: gain, q: q)
    }

    /// Calculate frequency response magnitude at a given frequency
    func magnitudeAt(frequency: Float) -> Float {
        let soloedBands = bands.filter { $0.solo }
        let bandsToProcess = soloedBands.isEmpty ? bands : soloedBands

        let bandTuples = bandsToProcess.map { ($0.bandType, $0.frequency, $0.gainDb, $0.q) }
        return FrequencyResponse.combinedMagnitude(bands: bandTuples, atFrequency: frequency, sampleRate: sampleRate)
    }

    /// Calculate phase response at a given frequency (in radians)
    func phaseAt(frequency: Float) -> Float {
        let soloedBands = bands.filter { $0.solo }
        let bandsToProcess = soloedBands.isEmpty ? bands : soloedBands

        let bandTuples = bandsToProcess.map { ($0.bandType, $0.frequency, $0.gainDb, $0.q) }
        return FrequencyResponse.combinedPhase(bands: bandTuples, atFrequency: frequency, sampleRate: sampleRate)
    }

    /// Get array of band info for UI
    var bandInfo: [(frequency: Float, gainDb: Float, q: Float, bandType: BandType)] {
        bands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType) }
    }

    /// Get array of band info including solo state
    var bandInfoWithSolo: [(frequency: Float, gainDb: Float, q: Float, bandType: BandType, solo: Bool)] {
        bands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType, $0.solo) }
    }
}
