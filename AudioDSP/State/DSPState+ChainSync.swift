import Foundation

// MARK: - DSP Chain Synchronization

// Thread Safety Contract:
// DSPState is @MainActor and all UI state changes happen on the main thread.
// DSPChain is @unchecked Sendable and uses a config lock for getEffect() access.
// Effect parameter setters (setParameter, isBypassed, etc.) are thread-safe and
// use internal parameter smoothing to prevent audio artifacts.

/// Effect slot indices in the DSP chain
private enum EffectSlot: Int {
    case eq = 0
    case bassEnhancer = 1
    case vocalClarity = 2
    case compressor = 3
    case reverb = 4
    case delay = 5
    case stereoWidener = 6
    case limiter = 7
    case outputGain = 8
}

extension DSPState {
    /// Sync all parameters to the DSP chain
    func syncToChain() {
        guard let chain = audioEngine?.dspChain else { return }

        syncEQToChain()
        syncCompressorToChain(chain: chain)
        syncLimiterToChain(chain: chain)
        syncReverbToChain(chain: chain)
        syncDelayToChain(chain: chain)
        syncStereoWidenerToChain(chain: chain)
        syncBassEnhancerToChain(chain: chain)
        syncVocalClarityToChain(chain: chain)
        syncOutputGainToChain(chain: chain)
    }

    // MARK: - Individual Effect Sync Methods

    func syncEQToChain() {
        guard let chain = audioEngine?.dspChain,
              let eq = chain.getEffect(at: EffectSlot.eq.rawValue) as? ParametricEQ else { return }

        eq.isBypassed = eqBypassed
        eq.setProcessingMode(eqProcessingMode)
        eq.setSaturationMode(eqSaturationMode)
        eq.setSaturationDrive(eqSaturationDrive)

        for (index, band) in eqBands.enumerated() {
            eq.setBand(index, bandType: band.bandType, frequency: band.frequency, gainDb: band.gainDb, q: band.q)
            eq.setSolo(index, solo: band.solo)
            eq.setBandEnabled(index, enabled: band.enabled)
            eq.setBandSlope(index, slope: band.slope)
            eq.setBandTopology(index, topology: band.topology)
            eq.setBandMSMode(index, mode: band.msMode)
            eq.setBandDynamics(
                index,
                enabled: band.dynamicsEnabled,
                threshold: band.dynamicsThreshold,
                ratio: band.dynamicsRatio,
                attackMs: band.dynamicsAttack,
                releaseMs: band.dynamicsRelease
            )
        }
    }

    func syncOutputGainToChain() {
        guard let chain = audioEngine?.dspChain else { return }
        syncOutputGainToChain(chain: chain)
    }

    private func syncOutputGainToChain(chain: DSPChain) {
        guard let gain = chain.getEffect(at: EffectSlot.outputGain.rawValue) else { return }
        gain.isBypassed = outputGainBypassed
        gain.setParameter(0, value: outputGain)
    }

    func syncCompressorToChain() {
        guard let chain = audioEngine?.dspChain else { return }
        syncCompressorToChain(chain: chain)
    }

    private func syncCompressorToChain(chain: DSPChain) {
        guard let compressor = chain.getEffect(at: EffectSlot.compressor.rawValue) else { return }
        compressor.isBypassed = compressorBypassed
        compressor.setParameter(0, value: compressorThreshold)
        compressor.setParameter(1, value: compressorRatio)
        compressor.setParameter(2, value: compressorAttack)
        compressor.setParameter(3, value: compressorRelease)
        compressor.setParameter(4, value: compressorMakeup)
    }

    func syncLimiterToChain() {
        guard let chain = audioEngine?.dspChain else { return }
        syncLimiterToChain(chain: chain)
    }

    private func syncLimiterToChain(chain: DSPChain) {
        guard let limiter = chain.getEffect(at: EffectSlot.limiter.rawValue) else { return }
        limiter.isBypassed = limiterBypassed
        limiter.setParameter(0, value: limiterCeiling)
        limiter.setParameter(1, value: limiterRelease)
    }

    func syncReverbToChain() {
        guard let chain = audioEngine?.dspChain else { return }
        syncReverbToChain(chain: chain)
    }

    private func syncReverbToChain(chain: DSPChain) {
        guard let reverb = chain.getEffect(at: EffectSlot.reverb.rawValue) else { return }
        reverb.isBypassed = reverbBypassed
        reverb.wetDry = reverbMix
        reverb.setParameter(0, value: reverbRoomSize)
        reverb.setParameter(1, value: reverbDamping)
        reverb.setParameter(2, value: reverbWidth)
    }

    func syncDelayToChain() {
        guard let chain = audioEngine?.dspChain else { return }
        syncDelayToChain(chain: chain)
    }

    private func syncDelayToChain(chain: DSPChain) {
        guard let delay = chain.getEffect(at: EffectSlot.delay.rawValue) else { return }
        delay.isBypassed = delayBypassed
        delay.wetDry = delayMix
        delay.setParameter(0, value: delayTime)
        delay.setParameter(1, value: delayFeedback)
    }

    func syncStereoWidenerToChain() {
        guard let chain = audioEngine?.dspChain else { return }
        syncStereoWidenerToChain(chain: chain)
    }

    private func syncStereoWidenerToChain(chain: DSPChain) {
        guard let widener = chain.getEffect(at: EffectSlot.stereoWidener.rawValue) else { return }
        widener.isBypassed = stereoWidenerBypassed
        widener.setParameter(0, value: stereoWidth)
    }

    func syncBassEnhancerToChain() {
        guard let chain = audioEngine?.dspChain else { return }
        syncBassEnhancerToChain(chain: chain)
    }

    private func syncBassEnhancerToChain(chain: DSPChain) {
        guard let bass = chain.getEffect(at: EffectSlot.bassEnhancer.rawValue) else { return }
        bass.isBypassed = bassEnhancerBypassed
        bass.setParameter(0, value: bassAmount)
        bass.setParameter(1, value: bassLowFreq)
        bass.setParameter(2, value: bassHarmonics)
    }

    func syncVocalClarityToChain() {
        guard let chain = audioEngine?.dspChain else { return }
        syncVocalClarityToChain(chain: chain)
    }

    private func syncVocalClarityToChain(chain: DSPChain) {
        guard let vocal = chain.getEffect(at: EffectSlot.vocalClarity.rawValue) else { return }
        vocal.isBypassed = vocalClarityBypassed
        vocal.setParameter(0, value: vocalClarity)
        vocal.setParameter(1, value: vocalAir)
    }
}

// MARK: - EQ Band Operations

extension DSPState {
    /// Toggle solo for a specific EQ band
    func toggleEQBandSolo(at index: Int) {
        guard index >= 0, index < eqBands.count else { return }
        eqBands[index].solo.toggle()
        syncEQToChain()
    }

    /// Clear all EQ band solos
    func clearAllEQSolo() {
        for i in eqBands.indices {
            eqBands[i].solo = false
        }
        syncEQToChain()
    }

    /// Check if any EQ band is soloed
    var hasEQSolo: Bool {
        eqBands.contains { $0.solo }
    }
}
