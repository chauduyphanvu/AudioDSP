import AudioToolbox

// MARK: - CoreAudio Callbacks

// These are global C-compatible functions required by CoreAudio.
// They access AudioEngine properties via the refCon pointer.
// All accessed properties must be nonisolated(unsafe) for real-time safety.

/// Input callback - captures audio from BlackHole virtual device
/// Called on the audio input thread (real-time priority)
func audioEngineInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<AudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()

    // Use pre-allocated buffer instead of allocating on audio thread
    // Clamp to buffer capacity to prevent overflow (pre-allocated for 4096 frames * 2 channels)
    let maxFrames = 4096
    let frameCount = min(Int(inNumberFrames), maxFrames)
    let data = engine.inputBuffer

    // Set up buffer list pointing to pre-allocated memory
    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: UInt32(frameCount) * 2 * UInt32(MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(data)
        )
    )

    // Render input audio into pre-allocated buffer
    guard let inputUnit = engine.inputUnit else { return noErr }
    let status = AudioUnitRender(inputUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, &bufferList)
    guard status == noErr else { return status }

    // Push interleaved stereo samples to ring buffer
    for frame in 0..<frameCount {
        let left = data[frame * 2]
        let right = data[frame * 2 + 1]
        engine.ringBuffer.push(left: left, right: right)
    }

    return noErr
}

/// Output callback - pulls processed audio to speakers/headphones
/// Called on the audio output thread (real-time priority)
func audioEngineOutputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    // Note: Denormal handling
    // - ARM64 (Apple Silicon): FTZ is enabled by default for performance
    // - x86_64 (Intel): Per-sample threshold checks in Biquad.swift handle denormals
    // - Additional protection: Filter state variables are flushed when below 1e-15

    let engine = Unmanaged<AudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()

    guard let ioData = ioData else { return noErr }
    let ablPointer = UnsafeMutableAudioBufferListPointer(ioData)
    guard ablPointer.count > 0,
          let outData = ablPointer[0].mData?.assumingMemoryBound(to: Float.self) else {
        return noErr
    }

    let frameCount = Int(inNumberFrames)

    for frame in 0..<frameCount {
        // Pull from ring buffer (with graceful underrun handling)
        let (left, right) = engine.ringBuffer.pop()

        // Process through DSP chain (lock-free)
        let (procL, procR) = engine.dspChain.process(left: left, right: right)

        // Write interleaved output
        outData[frame * 2] = procL
        outData[frame * 2 + 1] = procR

        // Feed analyzer
        engine.fftAnalyzer.push(left: procL, right: procR)
    }

    return noErr
}

