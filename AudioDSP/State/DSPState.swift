import Combine
import Foundation
import SwiftUI

/// EQ band state for UI binding
struct EQBandState: Equatable, Codable {
    var frequency: Float
    var gainDb: Float
    var q: Float
    var bandType: BandType
    var solo: Bool = false

    /// Bandwidth in octaves (derived from Q)
    var bandwidthOctaves: Float {
        QBandwidthConverter.qToOctaves(q)
    }

    /// Format Q with optional bandwidth display
    func formatQ(showBandwidth: Bool = false) -> String {
        if showBandwidth {
            return String(format: "%.2f (%.1f oct)", q, bandwidthOctaves)
        }
        return String(format: "%.2f", q)
    }
}

/// Main observable state for DSP parameters
@MainActor
final class DSPState: ObservableObject {
    // MARK: - Audio Engine

    var audioEngine: AudioEngine?

    // MARK: - EQ Parameters

    @Published var eqBands: [EQBandState] = [
        EQBandState(frequency: 80, gainDb: 0, q: 0.707, bandType: .lowShelf),
        EQBandState(frequency: 250, gainDb: 0, q: 1.0, bandType: .peak),
        EQBandState(frequency: 1000, gainDb: 0, q: 1.0, bandType: .peak),
        EQBandState(frequency: 4000, gainDb: 0, q: 1.0, bandType: .peak),
        EQBandState(frequency: 12000, gainDb: 0, q: 0.707, bandType: .highShelf),
    ]
    @Published var eqBypassed: Bool = false

    // MARK: - Compressor Parameters

    @Published var compressorThreshold: Float = -12
    @Published var compressorRatio: Float = 4
    @Published var compressorAttack: Float = 10
    @Published var compressorRelease: Float = 100
    @Published var compressorMakeup: Float = 0
    @Published var compressorBypassed: Bool = false
    @Published var compressorGainReduction: Float = 0

    // MARK: - Limiter Parameters

    @Published var limiterCeiling: Float = -0.3
    @Published var limiterRelease: Float = 50
    @Published var limiterBypassed: Bool = false
    @Published var limiterGainReduction: Float = 0

    // MARK: - Reverb Parameters

    @Published var reverbRoomSize: Float = 0.5
    @Published var reverbDamping: Float = 0.5
    @Published var reverbWidth: Float = 1.0
    @Published var reverbMix: Float = 0.3
    @Published var reverbBypassed: Bool = false

    // MARK: - Delay Parameters

    @Published var delayTime: Float = 250
    @Published var delayFeedback: Float = 0.3
    @Published var delayMix: Float = 0.3
    @Published var delayBypassed: Bool = false

    // MARK: - Stereo Widener Parameters

    @Published var stereoWidth: Float = 1.0
    @Published var stereoWidenerBypassed: Bool = false

    // MARK: - Bass Enhancer Parameters

    @Published var bassAmount: Float = 50
    @Published var bassLowFreq: Float = 100
    @Published var bassHarmonics: Float = 30
    @Published var bassEnhancerBypassed: Bool = false

    // MARK: - Vocal Clarity Parameters

    @Published var vocalClarity: Float = 50
    @Published var vocalAir: Float = 25
    @Published var vocalClarityBypassed: Bool = false

    // MARK: - Output Gain

    @Published var outputGain: Float = 0
    @Published var outputGainBypassed: Bool = false

    // MARK: - Metering

    @Published var inputLevelLeft: Float = 0
    @Published var inputLevelRight: Float = 0
    @Published var outputLevelLeft: Float = 0
    @Published var outputLevelRight: Float = 0
    @Published var spectrumData: [Float] = []

    // MARK: - A/B Comparison

    @Published var abSlot: ABSlot = .a
    private var slotA: StateSnapshot?
    private var slotB: StateSnapshot?

    // MARK: - Undo/Redo

    private let undoManager = UndoManager()
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
    }

    private func setupBindings() {
        // Sync state changes to DSP chain
        $eqBands
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncEQToChain() }
            .store(in: &cancellables)

        // Sync output gain changes to DSP chain
        $outputGain
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncOutputGainToChain() }
            .store(in: &cancellables)

        // Sync compressor changes
        Publishers.CombineLatest4($compressorThreshold, $compressorRatio, $compressorAttack, $compressorRelease)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncCompressorToChain() }
            .store(in: &cancellables)

        $compressorMakeup
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncCompressorToChain() }
            .store(in: &cancellables)

        // Sync limiter changes
        Publishers.CombineLatest($limiterCeiling, $limiterRelease)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncLimiterToChain() }
            .store(in: &cancellables)

        // Sync reverb changes
        Publishers.CombineLatest4($reverbRoomSize, $reverbDamping, $reverbWidth, $reverbMix)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncReverbToChain() }
            .store(in: &cancellables)

        // Sync delay changes
        Publishers.CombineLatest3($delayTime, $delayFeedback, $delayMix)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncDelayToChain() }
            .store(in: &cancellables)

        // Sync stereo widener changes
        $stereoWidth
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncStereoWidenerToChain() }
            .store(in: &cancellables)

        // Sync bass enhancer changes
        Publishers.CombineLatest3($bassAmount, $bassLowFreq, $bassHarmonics)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncBassEnhancerToChain() }
            .store(in: &cancellables)

        // Sync vocal clarity changes
        Publishers.CombineLatest($vocalClarity, $vocalAir)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncVocalClarityToChain() }
            .store(in: &cancellables)
    }

    // MARK: - DSP Sync

    func syncToChain() {
        guard let chain = audioEngine?.dspChain else { return }

        // Sync EQ
        syncEQToChain()

        // Sync Compressor
        if let compressor = chain.getEffect(at: 3) {
            compressor.isBypassed = compressorBypassed
            compressor.setParameter(0, value: compressorThreshold)
            compressor.setParameter(1, value: compressorRatio)
            compressor.setParameter(2, value: compressorAttack)
            compressor.setParameter(3, value: compressorRelease)
            compressor.setParameter(4, value: compressorMakeup)
        }

        // Sync Limiter
        if let limiter = chain.getEffect(at: 7) {
            limiter.isBypassed = limiterBypassed
            limiter.setParameter(0, value: limiterCeiling)
            limiter.setParameter(1, value: limiterRelease)
        }

        // Sync Reverb
        if let reverb = chain.getEffect(at: 4) {
            reverb.isBypassed = reverbBypassed
            reverb.wetDry = reverbMix
            reverb.setParameter(0, value: reverbRoomSize)
            reverb.setParameter(1, value: reverbDamping)
            reverb.setParameter(2, value: reverbWidth)
        }

        // Sync Delay
        if let delay = chain.getEffect(at: 5) {
            delay.isBypassed = delayBypassed
            delay.wetDry = delayMix
            delay.setParameter(0, value: delayTime)
            delay.setParameter(1, value: delayFeedback)
        }

        // Sync Stereo Widener
        if let widener = chain.getEffect(at: 6) {
            widener.isBypassed = stereoWidenerBypassed
            widener.setParameter(0, value: stereoWidth)
        }

        // Sync Bass Enhancer
        if let bass = chain.getEffect(at: 1) {
            bass.isBypassed = bassEnhancerBypassed
            bass.setParameter(0, value: bassAmount)
            bass.setParameter(1, value: bassLowFreq)
            bass.setParameter(2, value: bassHarmonics)
        }

        // Sync Vocal Clarity
        if let vocal = chain.getEffect(at: 2) {
            vocal.isBypassed = vocalClarityBypassed
            vocal.setParameter(0, value: vocalClarity)
            vocal.setParameter(1, value: vocalAir)
        }

        // Sync Output Gain
        if let gain = chain.getEffect(at: 8) {
            gain.isBypassed = outputGainBypassed
            gain.setParameter(0, value: outputGain)
        }
    }

    private func syncEQToChain() {
        guard let chain = audioEngine?.dspChain,
              let eq = chain.getEffect(at: 0) as? ParametricEQ else { return }

        eq.isBypassed = eqBypassed

        for (index, band) in eqBands.enumerated() {
            eq.setBand(index, bandType: band.bandType, frequency: band.frequency, gainDb: band.gainDb, q: band.q)
            eq.setSolo(index, solo: band.solo)
        }
    }

    private func syncOutputGainToChain() {
        guard let chain = audioEngine?.dspChain,
              let gain = chain.getEffect(at: 8) else { return }
        gain.isBypassed = outputGainBypassed
        gain.setParameter(0, value: outputGain)
    }

    private func syncCompressorToChain() {
        guard let chain = audioEngine?.dspChain,
              let compressor = chain.getEffect(at: 3) else { return }
        compressor.isBypassed = compressorBypassed
        compressor.setParameter(0, value: compressorThreshold)
        compressor.setParameter(1, value: compressorRatio)
        compressor.setParameter(2, value: compressorAttack)
        compressor.setParameter(3, value: compressorRelease)
        compressor.setParameter(4, value: compressorMakeup)
    }

    private func syncLimiterToChain() {
        guard let chain = audioEngine?.dspChain,
              let limiter = chain.getEffect(at: 7) else { return }
        limiter.isBypassed = limiterBypassed
        limiter.setParameter(0, value: limiterCeiling)
        limiter.setParameter(1, value: limiterRelease)
    }

    private func syncReverbToChain() {
        guard let chain = audioEngine?.dspChain,
              let reverb = chain.getEffect(at: 4) else { return }
        reverb.isBypassed = reverbBypassed
        reverb.wetDry = reverbMix
        reverb.setParameter(0, value: reverbRoomSize)
        reverb.setParameter(1, value: reverbDamping)
        reverb.setParameter(2, value: reverbWidth)
    }

    private func syncDelayToChain() {
        guard let chain = audioEngine?.dspChain,
              let delay = chain.getEffect(at: 5) else { return }
        delay.isBypassed = delayBypassed
        delay.wetDry = delayMix
        delay.setParameter(0, value: delayTime)
        delay.setParameter(1, value: delayFeedback)
    }

    private func syncStereoWidenerToChain() {
        guard let chain = audioEngine?.dspChain,
              let widener = chain.getEffect(at: 6) else { return }
        widener.isBypassed = stereoWidenerBypassed
        widener.setParameter(0, value: stereoWidth)
    }

    private func syncBassEnhancerToChain() {
        guard let chain = audioEngine?.dspChain,
              let bass = chain.getEffect(at: 1) else { return }
        bass.isBypassed = bassEnhancerBypassed
        bass.setParameter(0, value: bassAmount)
        bass.setParameter(1, value: bassLowFreq)
        bass.setParameter(2, value: bassHarmonics)
    }

    private func syncVocalClarityToChain() {
        guard let chain = audioEngine?.dspChain,
              let vocal = chain.getEffect(at: 2) else { return }
        vocal.isBypassed = vocalClarityBypassed
        vocal.setParameter(0, value: vocalClarity)
        vocal.setParameter(1, value: vocalAir)
    }

    /// Toggle solo for a specific EQ band
    func toggleEQBandSolo(at index: Int) {
        guard index >= 0, index < eqBands.count else { return }
        eqBands[index].solo.toggle()
        syncEQToChain()
    }

    /// Clear all EQ band solos
    func clearAllEQSolo() {
        for i in 0..<eqBands.count {
            eqBands[i].solo = false
        }
        syncEQToChain()
    }

    /// Check if any EQ band is soloed
    var hasEQSolo: Bool {
        eqBands.contains { $0.solo }
    }

    // MARK: - Bypass Toggles

    func toggleEQBypass() { registerUndo(); eqBypassed.toggle(); syncToChain() }
    func toggleCompressorBypass() { registerUndo(); compressorBypassed.toggle(); syncToChain() }
    func toggleLimiterBypass() { registerUndo(); limiterBypassed.toggle(); syncToChain() }
    func toggleReverbBypass() { registerUndo(); reverbBypassed.toggle(); syncToChain() }
    func toggleDelayBypass() { registerUndo(); delayBypassed.toggle(); syncToChain() }
    func toggleStereoWidenerBypass() { registerUndo(); stereoWidenerBypassed.toggle(); syncToChain() }
    func toggleBassEnhancerBypass() { registerUndo(); bassEnhancerBypassed.toggle(); syncToChain() }
    func toggleVocalClarityBypass() { registerUndo(); vocalClarityBypassed.toggle(); syncToChain() }

    // MARK: - Undo/Redo

    private func registerUndo() {
        let snapshot = createSnapshot()
        undoManager.registerUndo(withTarget: self) { target in
            target.restoreSnapshot(snapshot)
        }
        updateUndoState()
    }

    func undo() {
        undoManager.undo()
        updateUndoState()
        syncToChain()
    }

    func redo() {
        undoManager.redo()
        updateUndoState()
        syncToChain()
    }

    private func updateUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    // MARK: - A/B Comparison

    enum ABSlot {
        case a, b
    }

    func copyToCurrentSlot() {
        let snapshot = createSnapshot()
        switch abSlot {
        case .a: slotA = snapshot
        case .b: slotB = snapshot
        }
    }

    func switchABSlot() {
        // Save current to current slot
        copyToCurrentSlot()

        // Switch slot
        abSlot = abSlot == .a ? .b : .a

        // Restore from new slot
        if let snapshot = (abSlot == .a ? slotA : slotB) {
            restoreSnapshot(snapshot)
        }

        syncToChain()
    }

    // MARK: - Snapshots

    struct StateSnapshot {
        var eqBands: [EQBandState]
        var eqBypassed: Bool
        var compressorThreshold: Float
        var compressorRatio: Float
        var compressorAttack: Float
        var compressorRelease: Float
        var compressorMakeup: Float
        var compressorBypassed: Bool
        var limiterCeiling: Float
        var limiterRelease: Float
        var limiterBypassed: Bool
        var reverbRoomSize: Float
        var reverbDamping: Float
        var reverbWidth: Float
        var reverbMix: Float
        var reverbBypassed: Bool
        var delayTime: Float
        var delayFeedback: Float
        var delayMix: Float
        var delayBypassed: Bool
        var stereoWidth: Float
        var stereoWidenerBypassed: Bool
        var bassAmount: Float
        var bassLowFreq: Float
        var bassHarmonics: Float
        var bassEnhancerBypassed: Bool
        var vocalClarity: Float
        var vocalAir: Float
        var vocalClarityBypassed: Bool
        var outputGain: Float
    }

    func createSnapshot() -> StateSnapshot {
        StateSnapshot(
            eqBands: eqBands,
            eqBypassed: eqBypassed,
            compressorThreshold: compressorThreshold,
            compressorRatio: compressorRatio,
            compressorAttack: compressorAttack,
            compressorRelease: compressorRelease,
            compressorMakeup: compressorMakeup,
            compressorBypassed: compressorBypassed,
            limiterCeiling: limiterCeiling,
            limiterRelease: limiterRelease,
            limiterBypassed: limiterBypassed,
            reverbRoomSize: reverbRoomSize,
            reverbDamping: reverbDamping,
            reverbWidth: reverbWidth,
            reverbMix: reverbMix,
            reverbBypassed: reverbBypassed,
            delayTime: delayTime,
            delayFeedback: delayFeedback,
            delayMix: delayMix,
            delayBypassed: delayBypassed,
            stereoWidth: stereoWidth,
            stereoWidenerBypassed: stereoWidenerBypassed,
            bassAmount: bassAmount,
            bassLowFreq: bassLowFreq,
            bassHarmonics: bassHarmonics,
            bassEnhancerBypassed: bassEnhancerBypassed,
            vocalClarity: vocalClarity,
            vocalAir: vocalAir,
            vocalClarityBypassed: vocalClarityBypassed,
            outputGain: outputGain
        )
    }

    func restoreSnapshot(_ snapshot: StateSnapshot) {
        eqBands = snapshot.eqBands
        eqBypassed = snapshot.eqBypassed
        compressorThreshold = snapshot.compressorThreshold
        compressorRatio = snapshot.compressorRatio
        compressorAttack = snapshot.compressorAttack
        compressorRelease = snapshot.compressorRelease
        compressorMakeup = snapshot.compressorMakeup
        compressorBypassed = snapshot.compressorBypassed
        limiterCeiling = snapshot.limiterCeiling
        limiterRelease = snapshot.limiterRelease
        limiterBypassed = snapshot.limiterBypassed
        reverbRoomSize = snapshot.reverbRoomSize
        reverbDamping = snapshot.reverbDamping
        reverbWidth = snapshot.reverbWidth
        reverbMix = snapshot.reverbMix
        reverbBypassed = snapshot.reverbBypassed
        delayTime = snapshot.delayTime
        delayFeedback = snapshot.delayFeedback
        delayMix = snapshot.delayMix
        delayBypassed = snapshot.delayBypassed
        stereoWidth = snapshot.stereoWidth
        stereoWidenerBypassed = snapshot.stereoWidenerBypassed
        bassAmount = snapshot.bassAmount
        bassLowFreq = snapshot.bassLowFreq
        bassHarmonics = snapshot.bassHarmonics
        bassEnhancerBypassed = snapshot.bassEnhancerBypassed
        vocalClarity = snapshot.vocalClarity
        vocalAir = snapshot.vocalAir
        vocalClarityBypassed = snapshot.vocalClarityBypassed
        outputGain = snapshot.outputGain
    }
}
