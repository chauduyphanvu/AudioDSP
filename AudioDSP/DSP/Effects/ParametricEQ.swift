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
    // Core filters (biquad-based)
    private var biquadLeft: Biquad
    private var biquadRight: Biquad

    // SVF filters (alternative topology)
    private var svfLeft: StateVariableFilter
    private var svfRight: StateVariableFilter

    // Cascaded filters for different slopes
    private var cascadedLeft: CascadedFilter?
    private var cascadedRight: CascadedFilter?

    // Current settings
    private var params: EQBandParams
    private var topology: FilterTopology = .biquad
    private var slope: FilterSlope = .slope12dB
    private var msMode: MSMode = .stereo

    // Dynamic EQ
    private var dynamicsEnabled: Bool = false
    private var dynamicsThreshold: Float = -12
    private var dynamicsRatio: Float = 2.0
    private var dynamicsAttackCoeff: Float = 0.01
    private var dynamicsReleaseCoeff: Float = 0.001
    private var envelopeL: Float = 0
    private var envelopeR: Float = 0
    private var sidechainFilter: Biquad

    // Thread safety
    private var paramsLock = os_unfair_lock()
    private let enabledFlagPtr: UnsafeMutablePointer<Int32>
    private let sampleRate: Float

    var enabled: Bool {
        OSAtomicAdd32(0, enabledFlagPtr) != 0
    }

    // Public accessors
    var bandType: BandType {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        return params.bandType
    }
    var frequency: Float {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        return params.frequency
    }
    var gainDb: Float {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        return params.gainDb
    }
    var q: Float {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        return params.q
    }
    var solo: Bool {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        return params.solo
    }
    var currentSlope: FilterSlope {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        return slope
    }
    var currentMSMode: MSMode {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        return msMode
    }
    var currentTopology: FilterTopology {
        os_unfair_lock_lock(&paramsLock)
        defer { os_unfair_lock_unlock(&paramsLock) }
        return topology
    }

    init(sampleRate: Float, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        self.sampleRate = sampleRate
        self.params = EQBandParams(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q)

        self.enabledFlagPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        enabledFlagPtr.initialize(to: 1)

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

        // Sidechain filter for dynamic EQ (bandpass centered on band frequency)
        self.sidechainFilter = Biquad(params: BiquadParams(
            filterType: .peak(gainDb: 0),
            frequency: frequency,
            q: 1.0,
            gainDb: 0
        ), sampleRate: sampleRate)

        updateSVFParams()
    }

    deinit {
        enabledFlagPtr.deinitialize(count: 1)
        enabledFlagPtr.deallocate()
    }

    private func updateSVFParams() {
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
        guard OSAtomicAdd32(0, enabledFlagPtr) != 0 else { return (left, right) }

        os_unfair_lock_lock(&paramsLock)
        let currentTopology = topology
        let currentSlope = slope
        let currentMsMode = msMode
        let currentBandType = params.bandType
        let dynEnabled = dynamicsEnabled
        let dynThreshold = dynamicsThreshold
        let dynRatio = dynamicsRatio
        let attackCoeff = dynamicsAttackCoeff
        let releaseCoeff = dynamicsReleaseCoeff
        os_unfair_lock_unlock(&paramsLock)

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
        os_unfair_lock_lock(&paramsLock)
        params = EQBandParams(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q, solo: params.solo)
        os_unfair_lock_unlock(&paramsLock)

        let biquadParams = BiquadParams(
            filterType: bandType.toBiquadType(gainDb: gainDb),
            frequency: frequency,
            q: q,
            gainDb: gainDb
        )

        biquadLeft.updateParameters(biquadParams)
        biquadRight.updateParameters(biquadParams)
        updateSVFParams()

        // Update cascaded filters if needed
        if FilterSlope.appliesTo(bandType) {
            cascadedLeft?.updateParameters(frequency: frequency, q: q, isHighPass: bandType == .highPass)
            cascadedRight?.updateParameters(frequency: frequency, q: q, isHighPass: bandType == .highPass)
        }

        // Update sidechain filter for dynamic EQ
        sidechainFilter.updateParameters(BiquadParams(
            filterType: .peak(gainDb: 0),
            frequency: frequency,
            q: 1.0,
            gainDb: 0
        ))
    }

    func setSlope(_ newSlope: FilterSlope) {
        os_unfair_lock_lock(&paramsLock)
        slope = newSlope
        let currentParams = params
        os_unfair_lock_unlock(&paramsLock)

        // Create or update cascaded filters
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
        os_unfair_lock_lock(&paramsLock)
        topology = newTopology
        os_unfair_lock_unlock(&paramsLock)
    }

    func setMSMode(_ newMode: MSMode) {
        os_unfair_lock_lock(&paramsLock)
        msMode = newMode
        os_unfair_lock_unlock(&paramsLock)
    }

    func setDynamics(enabled: Bool, threshold: Float, ratio: Float, attackMs: Float, releaseMs: Float) {
        os_unfair_lock_lock(&paramsLock)
        dynamicsEnabled = enabled
        dynamicsThreshold = threshold
        dynamicsRatio = max(1, ratio)
        dynamicsAttackCoeff = 1.0 - exp(-1.0 / (sampleRate * attackMs / 1000))
        dynamicsReleaseCoeff = 1.0 - exp(-1.0 / (sampleRate * releaseMs / 1000))
        os_unfair_lock_unlock(&paramsLock)
    }

    func setSolo(_ solo: Bool) {
        os_unfair_lock_lock(&paramsLock)
        params = EQBandParams(
            bandType: params.bandType,
            frequency: params.frequency,
            gainDb: params.gainDb,
            q: params.q,
            solo: solo
        )
        os_unfair_lock_unlock(&paramsLock)
    }

    func setEnabled(_ enabled: Bool) {
        let newValue: Int32 = enabled ? 1 : 0
        while true {
            let oldValue = OSAtomicAdd32(0, enabledFlagPtr)
            if oldValue == newValue { break }
            if OSAtomicCompareAndSwap32(oldValue, newValue, enabledFlagPtr) { break }
        }
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

    // Saturation processor (replaces old soft clipper)
    private var saturation: Saturation

    // Linear phase processor
    private var linearPhaseEQ: LinearPhaseEQ?
    private var processingMode: EQProcessingMode = .minimumPhase
    private var modeLock = os_unfair_lock()

    // Atomic solo bitmask
    private let soloMaskPtr: UnsafeMutablePointer<UInt32>

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate

        // Initialize saturation processor
        self.saturation = Saturation()

        // Allocate atomic solo mask
        self.soloMaskPtr = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        soloMaskPtr.initialize(to: 0)

        // Default 5-band layout
        bands = [
            ExtendedEQBand(sampleRate: sampleRate, bandType: .lowShelf, frequency: 80, gainDb: 0, q: 0.707),
            ExtendedEQBand(sampleRate: sampleRate, bandType: .peak, frequency: 250, gainDb: 0, q: 1.0),
            ExtendedEQBand(sampleRate: sampleRate, bandType: .peak, frequency: 1000, gainDb: 0, q: 1.0),
            ExtendedEQBand(sampleRate: sampleRate, bandType: .peak, frequency: 4000, gainDb: 0, q: 1.0),
            ExtendedEQBand(sampleRate: sampleRate, bandType: .highShelf, frequency: 12000, gainDb: 0, q: 0.707),
        ]
    }

    deinit {
        soloMaskPtr.deinitialize(count: 1)
        soloMaskPtr.deallocate()
    }

    /// Get current solo mask atomically (thread-safe for audio thread)
    @inline(__always)
    private func getSoloMask() -> UInt32 {
        let signed = OSAtomicAdd32(0, UnsafeMutablePointer<Int32>(OpaquePointer(soloMaskPtr)))
        return UInt32(bitPattern: signed)
    }

    /// Set solo bit for a band atomically
    private func setSoloBit(_ index: Int, _ value: Bool) {
        let bit = UInt32(1 << index)
        if value {
            OSAtomicOr32(bit, UnsafeMutablePointer<UInt32>(soloMaskPtr))
        } else {
            OSAtomicAnd32(~bit, UnsafeMutablePointer<UInt32>(soloMaskPtr))
        }
    }

    // MARK: - Processing Mode

    /// Set EQ processing mode (minimum phase or linear phase)
    func setProcessingMode(_ mode: EQProcessingMode) {
        os_unfair_lock_lock(&modeLock)
        defer { os_unfair_lock_unlock(&modeLock) }

        processingMode = mode

        if mode == .linearPhase && linearPhaseEQ == nil {
            linearPhaseEQ = LinearPhaseEQ(sampleRate: sampleRate)
            syncLinearPhaseParams()
        }
    }

    func getProcessingMode() -> EQProcessingMode {
        os_unfair_lock_lock(&modeLock)
        defer { os_unfair_lock_unlock(&modeLock) }
        return processingMode
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
        // Check processing mode
        os_unfair_lock_lock(&modeLock)
        let mode = processingMode
        os_unfair_lock_unlock(&modeLock)

        var l = left
        var r = right

        if mode == .linearPhase, let lpEQ = linearPhaseEQ {
            // Linear phase processing
            let result = lpEQ.process(left: l, right: r)
            l = result.left
            r = result.right
        } else {
            // Minimum phase processing
            let soloMask = getSoloMask()

            if soloMask != 0 {
                // Process only soloed bands
                for index in 0..<bands.count {
                    if (soloMask & UInt32(1 << index)) != 0 {
                        let result = bands[index].process(left: l, right: r)
                        l = result.left
                        r = result.right
                    }
                }
            } else {
                // Normal processing - all bands in series
                for band in bands {
                    let result = band.process(left: l, right: r)
                    l = result.left
                    r = result.right
                }
            }
        }

        // Apply saturation (with oversampling)
        let saturated = saturation.process(left: l, right: r)

        return saturated
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
        os_unfair_lock_lock(&modeLock)
        let mode = processingMode
        os_unfair_lock_unlock(&modeLock)

        if mode == .linearPhase {
            return linearPhaseEQ?.latencySamples ?? 0
        }
        return 0
    }

    func setBand(_ index: Int, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        guard index >= 0, index < bands.count else { return }
        bands[index].update(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q)

        // Sync to linear phase if active
        if processingMode == .linearPhase {
            syncLinearPhaseParams()
        }
    }

    func setSolo(_ index: Int, solo: Bool) {
        guard index >= 0, index < bands.count else { return }
        bands[index].setSolo(solo)
        setSoloBit(index, solo)
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
            setSoloBit(index, false)
        }
    }

    func getBand(_ index: Int) -> ExtendedEQBand? {
        guard index >= 0, index < bands.count else { return nil }
        return bands[index]
    }

    func isBandSoloed(_ index: Int) -> Bool {
        guard index >= 0, index < bands.count else { return false }
        return (getSoloMask() & UInt32(1 << index)) != 0
    }

    var hasSoloedBand: Bool {
        getSoloMask() != 0
    }

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
            freq = min(max(value, 20), 20000)
            gain = band.gainDb
            q = band.q
        case 1:
            freq = band.frequency
            gain = min(max(value, -24), 24)
            q = band.q
        case 2:
            freq = band.frequency
            gain = band.gainDb
            q = min(max(value, 0.1), 10)
        default:
            return
        }

        band.update(bandType: band.bandType, frequency: freq, gainDb: gain, q: q)
    }

    /// Calculate frequency response magnitude at a given frequency
    func magnitudeAt(frequency: Float) -> Float {
        var magnitude: Float = 1.0

        // Check if any band is soloed
        let soloedBands = bands.filter { $0.solo }
        let bandsToProcess = soloedBands.isEmpty ? bands : soloedBands

        for band in bandsToProcess {
            let omega = 2.0 * Float.pi * frequency / sampleRate
            let cosOmega = cos(omega)
            let cos2Omega = cos(2.0 * omega)
            let sinOmega = sin(omega)
            let sin2Omega = sin(2.0 * omega)

            let coeffs = BiquadCoefficients.calculate(
                type: band.bandType.toBiquadType(gainDb: band.gainDb),
                sampleRate: sampleRate,
                frequency: band.frequency,
                q: band.q
            )

            // H(e^jw) = (b0 + b1*e^-jw + b2*e^-2jw) / (1 + a1*e^-jw + a2*e^-2jw)
            let numReal = coeffs.b0 + coeffs.b1 * cosOmega + coeffs.b2 * cos2Omega
            let numImag = -coeffs.b1 * sinOmega - coeffs.b2 * sin2Omega
            let denReal = 1.0 + coeffs.a1 * cosOmega + coeffs.a2 * cos2Omega
            let denImag = -coeffs.a1 * sinOmega - coeffs.a2 * sin2Omega

            let numMag = sqrt(numReal * numReal + numImag * numImag)
            let denMag = sqrt(denReal * denReal + denImag * denImag)

            magnitude *= numMag / max(denMag, 1e-10)
        }

        return magnitude
    }

    /// Calculate phase response at a given frequency (in radians)
    func phaseAt(frequency: Float) -> Float {
        var totalPhase: Float = 0.0

        // Check if any band is soloed
        let soloedBands = bands.filter { $0.solo }
        let bandsToProcess = soloedBands.isEmpty ? bands : soloedBands

        for band in bandsToProcess {
            let omega = 2.0 * Float.pi * frequency / sampleRate
            let cosOmega = cos(omega)
            let cos2Omega = cos(2.0 * omega)
            let sinOmega = sin(omega)
            let sin2Omega = sin(2.0 * omega)

            let coeffs = BiquadCoefficients.calculate(
                type: band.bandType.toBiquadType(gainDb: band.gainDb),
                sampleRate: sampleRate,
                frequency: band.frequency,
                q: band.q
            )

            // Calculate complex transfer function
            let numReal = coeffs.b0 + coeffs.b1 * cosOmega + coeffs.b2 * cos2Omega
            let numImag = -coeffs.b1 * sinOmega - coeffs.b2 * sin2Omega
            let denReal = 1.0 + coeffs.a1 * cosOmega + coeffs.a2 * cos2Omega
            let denImag = -coeffs.a1 * sinOmega - coeffs.a2 * sin2Omega

            // Phase = atan2(imag, real) for numerator - atan2(imag, real) for denominator
            let numPhase = atan2(numImag, numReal)
            let denPhase = atan2(denImag, denReal)

            totalPhase += numPhase - denPhase
        }

        return totalPhase
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
