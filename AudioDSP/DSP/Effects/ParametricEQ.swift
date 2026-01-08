import Foundation
import os

/// 5-band Parametric Equalizer with advanced features including
/// linear phase mode, saturation, and per-band dynamics.
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

    // MARK: - Initialization

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

    func setSaturationMode(_ mode: SaturationMode) {
        saturation.setMode(mode)
    }

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

    var latencySamples: Int {
        processingModeState.read() == .linearPhase ? (linearPhaseEQ?.latencySamples ?? 0) : 0
    }

    // MARK: - Band Management

    private func band(at index: Int) -> ExtendedEQBand? {
        bands.indices.contains(index) ? bands[index] : nil
    }

    func setBand(_ index: Int, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        guard let band = band(at: index) else { return }
        band.update(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q)

        if processingModeState.read() == .linearPhase {
            syncLinearPhaseParams()
        }
    }

    func setSolo(_ index: Int, solo: Bool) {
        guard let band = band(at: index) else { return }
        band.setSolo(solo)
        soloMask.setBit(index, solo)
    }

    func setBandEnabled(_ index: Int, enabled: Bool) {
        band(at: index)?.setEnabled(enabled)
    }

    func setBandSlope(_ index: Int, slope: FilterSlope) {
        band(at: index)?.setSlope(slope)
    }

    func setBandTopology(_ index: Int, topology: FilterTopology) {
        band(at: index)?.setTopology(topology)
    }

    func setBandMSMode(_ index: Int, mode: MSMode) {
        band(at: index)?.setMSMode(mode)
    }

    func setBandDynamics(_ index: Int, enabled: Bool, threshold: Float, ratio: Float, attackMs: Float, releaseMs: Float) {
        band(at: index)?.setDynamics(enabled: enabled, threshold: threshold, ratio: ratio, attackMs: attackMs, releaseMs: releaseMs)
    }

    func clearAllSolo() {
        for (index, band) in bands.enumerated() {
            band.setSolo(false)
            soloMask.setBit(index, false)
        }
    }

    func getBand(_ index: Int) -> ExtendedEQBand? {
        band(at: index)
    }

    func isBandSoloed(_ index: Int) -> Bool {
        bands.indices.contains(index) && soloMask.isBitSet(index)
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

    // MARK: - Frequency Response

    func magnitudeAt(frequency: Float) -> Float {
        let soloedBands = bands.filter { $0.solo }
        let bandsToProcess = soloedBands.isEmpty ? bands : soloedBands

        let bandTuples = bandsToProcess.map { ($0.bandType, $0.frequency, $0.gainDb, $0.q) }
        return FrequencyResponse.combinedMagnitude(bands: bandTuples, atFrequency: frequency, sampleRate: sampleRate)
    }

    func phaseAt(frequency: Float) -> Float {
        let soloedBands = bands.filter { $0.solo }
        let bandsToProcess = soloedBands.isEmpty ? bands : soloedBands

        let bandTuples = bandsToProcess.map { ($0.bandType, $0.frequency, $0.gainDb, $0.q) }
        return FrequencyResponse.combinedPhase(bands: bandTuples, atFrequency: frequency, sampleRate: sampleRate)
    }

    // MARK: - UI Helpers

    var bandInfo: [(frequency: Float, gainDb: Float, q: Float, bandType: BandType)] {
        bands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType) }
    }

    var bandInfoWithSolo: [(frequency: Float, gainDb: Float, q: Float, bandType: BandType, solo: Bool)] {
        bands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType, $0.solo) }
    }
}
