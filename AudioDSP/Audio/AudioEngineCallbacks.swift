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

    let maxFrames = 4096
    let frameCount = min(Int(inNumberFrames), maxFrames)
    let data = engine.inputBuffer

    // Set up buffer list for interleaved stereo
    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: UInt32(frameCount * 2 * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(data)
        )
    )

    // Render input audio into buffer
    // IMPORTANT: Use frameCount (clamped) not inNumberFrames to match buffer size
    guard let inputUnit = engine.inputUnit else { return noErr }
    let status = AudioUnitRender(inputUnit, ioActionFlags, inTimeStamp, 1, UInt32(frameCount), &bufferList)
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
    let engine = Unmanaged<AudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()

    guard let ioData = ioData else { return noErr }
    let ablPointer = UnsafeMutableAudioBufferListPointer(ioData)
    guard ablPointer.count > 0,
          let outData = ablPointer[0].mData?.assumingMemoryBound(to: Float.self) else {
        return noErr
    }

    let frameCount = Int(inNumberFrames)

    // Write interleaved stereo output
    // DEBUG: Set to true to bypass DSP and test raw audio passthrough
    let bypassDSP = false

    for frame in 0..<frameCount {
        let (left, right) = engine.ringBuffer.pop()

        let outL: Float
        let outR: Float
        if bypassDSP {
            outL = left
            outR = right
        } else {
            let (procL, procR) = engine.dspChain.process(left: left, right: right)
            outL = procL
            outR = procR
        }

        outData[frame * 2] = outL
        outData[frame * 2 + 1] = outR
        engine.fftAnalyzer.push(left: outL, right: outR)
    }

    return noErr
}

