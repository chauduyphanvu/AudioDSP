import Combine
import Foundation

/// Persistent session state model
struct SessionState: Codable {
    var eqBands: [EQBandState]
    var eqBypassed: Bool
    var eqProcessingMode: EQProcessingMode
    var eqSaturationMode: SaturationMode
    var eqSaturationDrive: Float
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
    var outputGainBypassed: Bool
}

/// Manages automatic session state persistence
@MainActor
final class SessionManager: ObservableObject {
    private let sessionURL: URL
    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AudioDSP")
        sessionURL = appDir.appendingPathComponent("session.json")

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    }

    func restoreSession(into state: DSPState) -> Bool {
        guard FileManager.default.fileExists(atPath: sessionURL.path),
              let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(SessionState.self, from: data) else {
            return false
        }

        apply(session, to: state)
        return true
    }

    func saveSession(from state: DSPState) {
        let session = capture(from: state)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(session)
            try data.write(to: sessionURL)
        } catch {
            print("Failed to save session: \(error)")
        }
    }

    func scheduleSave(from state: DSPState) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            saveSession(from: state)
        }
    }

    func bindAutoSave(to state: DSPState) {
        state.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self, weak state] _ in
                guard let self, let state else { return }
                self.saveSession(from: state)
            }
            .store(in: &cancellables)
    }

    private func capture(from state: DSPState) -> SessionState {
        SessionState(
            eqBands: state.eqBands,
            eqBypassed: state.eqBypassed,
            eqProcessingMode: state.eqProcessingMode,
            eqSaturationMode: state.eqSaturationMode,
            eqSaturationDrive: state.eqSaturationDrive,
            compressorThreshold: state.compressorThreshold,
            compressorRatio: state.compressorRatio,
            compressorAttack: state.compressorAttack,
            compressorRelease: state.compressorRelease,
            compressorMakeup: state.compressorMakeup,
            compressorBypassed: state.compressorBypassed,
            limiterCeiling: state.limiterCeiling,
            limiterRelease: state.limiterRelease,
            limiterBypassed: state.limiterBypassed,
            reverbRoomSize: state.reverbRoomSize,
            reverbDamping: state.reverbDamping,
            reverbWidth: state.reverbWidth,
            reverbMix: state.reverbMix,
            reverbBypassed: state.reverbBypassed,
            delayTime: state.delayTime,
            delayFeedback: state.delayFeedback,
            delayMix: state.delayMix,
            delayBypassed: state.delayBypassed,
            stereoWidth: state.stereoWidth,
            stereoWidenerBypassed: state.stereoWidenerBypassed,
            bassAmount: state.bassAmount,
            bassLowFreq: state.bassLowFreq,
            bassHarmonics: state.bassHarmonics,
            bassEnhancerBypassed: state.bassEnhancerBypassed,
            vocalClarity: state.vocalClarity,
            vocalAir: state.vocalAir,
            vocalClarityBypassed: state.vocalClarityBypassed,
            outputGain: state.outputGain,
            outputGainBypassed: state.outputGainBypassed
        )
    }

    private func apply(_ session: SessionState, to state: DSPState) {
        state.eqBands = session.eqBands
        state.eqBypassed = session.eqBypassed
        state.eqProcessingMode = session.eqProcessingMode
        state.eqSaturationMode = session.eqSaturationMode
        state.eqSaturationDrive = session.eqSaturationDrive
        state.compressorThreshold = session.compressorThreshold
        state.compressorRatio = session.compressorRatio
        state.compressorAttack = session.compressorAttack
        state.compressorRelease = session.compressorRelease
        state.compressorMakeup = session.compressorMakeup
        state.compressorBypassed = session.compressorBypassed
        state.limiterCeiling = session.limiterCeiling
        state.limiterRelease = session.limiterRelease
        state.limiterBypassed = session.limiterBypassed
        state.reverbRoomSize = session.reverbRoomSize
        state.reverbDamping = session.reverbDamping
        state.reverbWidth = session.reverbWidth
        state.reverbMix = session.reverbMix
        state.reverbBypassed = session.reverbBypassed
        state.delayTime = session.delayTime
        state.delayFeedback = session.delayFeedback
        state.delayMix = session.delayMix
        state.delayBypassed = session.delayBypassed
        state.stereoWidth = session.stereoWidth
        state.stereoWidenerBypassed = session.stereoWidenerBypassed
        state.bassAmount = session.bassAmount
        state.bassLowFreq = session.bassLowFreq
        state.bassHarmonics = session.bassHarmonics
        state.bassEnhancerBypassed = session.bassEnhancerBypassed
        state.vocalClarity = session.vocalClarity
        state.vocalAir = session.vocalAir
        state.vocalClarityBypassed = session.vocalClarityBypassed
        state.outputGain = session.outputGain
        state.outputGainBypassed = session.outputGainBypassed
    }
}
