import Foundation

// MARK: - Bypass Toggles

extension DSPState {
    func toggleEQBypass(showToast: Bool = true) {
        registerUndo()
        eqBypassed.toggle()
        syncToChain()
        if showToast {
            ToastManager.shared.show(effect: "EQ", enabled: !eqBypassed)
        }
    }

    func toggleCompressorBypass(showToast: Bool = true) {
        registerUndo()
        compressorBypassed.toggle()
        syncToChain()
        if showToast {
            ToastManager.shared.show(effect: "Compressor", enabled: !compressorBypassed)
        }
    }

    func toggleLimiterBypass(showToast: Bool = true) {
        registerUndo()
        limiterBypassed.toggle()
        syncToChain()
        if showToast {
            ToastManager.shared.show(effect: "Limiter", enabled: !limiterBypassed)
        }
    }

    func toggleReverbBypass(showToast: Bool = true) {
        registerUndo()
        reverbBypassed.toggle()
        syncToChain()
        if showToast {
            ToastManager.shared.show(effect: "Reverb", enabled: !reverbBypassed)
        }
    }

    func toggleDelayBypass(showToast: Bool = true) {
        registerUndo()
        delayBypassed.toggle()
        syncToChain()
        if showToast {
            ToastManager.shared.show(effect: "Delay", enabled: !delayBypassed)
        }
    }

    func toggleStereoWidenerBypass(showToast: Bool = true) {
        registerUndo()
        stereoWidenerBypassed.toggle()
        syncToChain()
        if showToast {
            ToastManager.shared.show(effect: "Stereo Widener", enabled: !stereoWidenerBypassed)
        }
    }

    func toggleBassEnhancerBypass(showToast: Bool = true) {
        registerUndo()
        bassEnhancerBypassed.toggle()
        syncToChain()
        if showToast {
            ToastManager.shared.show(effect: "Bass Enhancer", enabled: !bassEnhancerBypassed)
        }
    }

    func toggleVocalClarityBypass(showToast: Bool = true) {
        registerUndo()
        vocalClarityBypassed.toggle()
        syncToChain()
        if showToast {
            ToastManager.shared.show(effect: "Vocal Clarity", enabled: !vocalClarityBypassed)
        }
    }

    /// Toggle bypass for all effects at once
    func toggleBypassAll(showToast: Bool = true) {
        registerUndo()

        let allBypassed = eqBypassed && compressorBypassed && limiterBypassed &&
                          reverbBypassed && delayBypassed && stereoWidenerBypassed &&
                          bassEnhancerBypassed && vocalClarityBypassed

        let newState = !allBypassed
        eqBypassed = newState
        compressorBypassed = newState
        limiterBypassed = newState
        reverbBypassed = newState
        delayBypassed = newState
        stereoWidenerBypassed = newState
        bassEnhancerBypassed = newState
        vocalClarityBypassed = newState

        syncToChain()

        if showToast {
            ToastManager.shared.show(effect: "All Effects", enabled: !newState)
        }
    }
}

// MARK: - Reset All Parameters

extension DSPState {
    /// Reset all parameters to defaults
    func resetAllParameters() {
        registerUndo()

        // EQ
        eqBands = EQBandState.defaultBands
        eqBypassed = DSPDefaults.eqBypassed
        eqProcessingMode = DSPDefaults.eqProcessingMode
        eqSaturationMode = DSPDefaults.eqSaturationMode
        eqSaturationDrive = DSPDefaults.eqSaturationDrive

        // Compressor
        compressorThreshold = DSPDefaults.compressorThreshold
        compressorRatio = DSPDefaults.compressorRatio
        compressorAttack = DSPDefaults.compressorAttack
        compressorRelease = DSPDefaults.compressorRelease
        compressorMakeup = DSPDefaults.compressorMakeup
        compressorBypassed = DSPDefaults.compressorBypassed

        // Limiter
        limiterCeiling = DSPDefaults.limiterCeiling
        limiterRelease = DSPDefaults.limiterRelease
        limiterBypassed = DSPDefaults.limiterBypassed

        // Reverb
        reverbRoomSize = DSPDefaults.reverbRoomSize
        reverbDamping = DSPDefaults.reverbDamping
        reverbWidth = DSPDefaults.reverbWidth
        reverbMix = DSPDefaults.reverbMix
        reverbBypassed = DSPDefaults.reverbBypassed

        // Delay
        delayTime = DSPDefaults.delayTime
        delayFeedback = DSPDefaults.delayFeedback
        delayMix = DSPDefaults.delayMix
        delayBypassed = DSPDefaults.delayBypassed

        // Stereo Widener
        stereoWidth = DSPDefaults.stereoWidth
        stereoWidenerBypassed = DSPDefaults.stereoWidenerBypassed

        // Bass Enhancer
        bassAmount = DSPDefaults.bassAmount
        bassLowFreq = DSPDefaults.bassLowFreq
        bassHarmonics = DSPDefaults.bassHarmonics
        bassEnhancerBypassed = DSPDefaults.bassEnhancerBypassed

        // Vocal Clarity
        vocalClarity = DSPDefaults.vocalClarity
        vocalAir = DSPDefaults.vocalAir
        vocalClarityBypassed = DSPDefaults.vocalClarityBypassed

        // Output
        outputGain = DSPDefaults.outputGain
        outputGainBypassed = DSPDefaults.outputGainBypassed

        syncToChain()
        ToastManager.shared.show(action: "Parameters Reset", icon: "arrow.counterclockwise.circle.fill")
    }
}
