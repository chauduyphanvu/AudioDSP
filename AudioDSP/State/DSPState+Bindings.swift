import Combine
import Foundation

// MARK: - Combine Bindings

extension DSPState {
    /// Set up reactive bindings to sync UI state changes to DSP chain
    /// Uses 8ms debounce for responsive feedback while DSP-side smoothing handles zipper noise
    func setupBindings() {
        // EQ bands
        $eqBands
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncEQToChain() }
            .store(in: &cancellables)

        // EQ processing mode
        $eqProcessingMode
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncEQToChain() }
            .store(in: &cancellables)

        // EQ saturation
        Publishers.CombineLatest($eqSaturationMode, $eqSaturationDrive)
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncEQToChain() }
            .store(in: &cancellables)

        // Output gain
        $outputGain
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncOutputGainToChain() }
            .store(in: &cancellables)

        // Compressor
        Publishers.CombineLatest4($compressorThreshold, $compressorRatio, $compressorAttack, $compressorRelease)
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncCompressorToChain() }
            .store(in: &cancellables)

        $compressorMakeup
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncCompressorToChain() }
            .store(in: &cancellables)

        // Limiter
        Publishers.CombineLatest($limiterCeiling, $limiterRelease)
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncLimiterToChain() }
            .store(in: &cancellables)

        // Reverb
        Publishers.CombineLatest4($reverbRoomSize, $reverbDamping, $reverbWidth, $reverbMix)
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncReverbToChain() }
            .store(in: &cancellables)

        // Delay
        Publishers.CombineLatest3($delayTime, $delayFeedback, $delayMix)
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncDelayToChain() }
            .store(in: &cancellables)

        // Stereo widener
        $stereoWidth
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncStereoWidenerToChain() }
            .store(in: &cancellables)

        // Bass enhancer
        Publishers.CombineLatest3($bassAmount, $bassLowFreq, $bassHarmonics)
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncBassEnhancerToChain() }
            .store(in: &cancellables)

        // Vocal clarity
        Publishers.CombineLatest($vocalClarity, $vocalAir)
            .debounce(for: .milliseconds(8), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncVocalClarityToChain() }
            .store(in: &cancellables)
    }
}
