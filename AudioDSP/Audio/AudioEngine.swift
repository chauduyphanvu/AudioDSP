import AVFoundation
import AudioToolbox
import Combine
import os

/// Audio engine using low-level CoreAudio for full device control (like Rust CLI)
@MainActor
final class AudioEngine: ObservableObject {
    // These are accessed from audio thread callbacks - must be nonisolated
    // dspChain and fftAnalyzer need internal access for UI
    nonisolated(unsafe) let dspChain: DSPChain
    nonisolated(unsafe) let fftAnalyzer: FFTAnalyzer
    nonisolated(unsafe) fileprivate let ringBuffer = RingBuffer<Float>(capacity: 48000 * 2)
    nonisolated(unsafe) fileprivate var inputUnit: AudioUnit?
    nonisolated(unsafe) private var outputUnit: AudioUnit?

    // Published levels for UI metering
    @Published var inputLevelLeft: Float = 0
    @Published var inputLevelRight: Float = 0
    @Published var outputLevelLeft: Float = 0
    @Published var outputLevelRight: Float = 0

    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "Ready"

    let sampleRate: Double = 48000
    let channels: Int = 2

    private var levelUpdateTimer: Timer?

    init() {
        dspChain = DSPChain.createDefault(sampleRate: Float(sampleRate))
        fftAnalyzer = FFTAnalyzer(fftSize: 2048)
    }

    func start() async {
        do {
            try setupCoreAudio()
            isRunning = true
            statusMessage = "Processing audio"
            startLevelMetering()
            Logger.audio.info("Audio engine started successfully")
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            Logger.audio.error("Failed to start audio engine: \(error)")
        }
    }

    func stop() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil

        if let inputUnit = inputUnit {
            AudioOutputUnitStop(inputUnit)
            AudioComponentInstanceDispose(inputUnit)
        }
        if let outputUnit = outputUnit {
            AudioOutputUnitStop(outputUnit)
            AudioComponentInstanceDispose(outputUnit)
        }
        inputUnit = nil
        outputUnit = nil
        ringBuffer.clear()
        isRunning = false
        statusMessage = "Stopped"

        Logger.audio.info("Audio engine stopped")
    }

    private func setupCoreAudio() throws {
        // Find devices
        guard let blackholeID = findBlackHoleDevice() else {
            throw NSError(domain: "AudioEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "BlackHole not found"])
        }
        guard let speakerID = findSpeakerDevice() else {
            throw NSError(domain: "AudioEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "No speaker device found"])
        }

        Logger.audio.info("Using BlackHole ID: \(blackholeID), Speaker ID: \(speakerID)")

        // Set up input unit (HAL Output unit configured for input)
        var inputDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let inputComponent = AudioComponentFindNext(nil, &inputDesc) else {
            throw NSError(domain: "AudioEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not find input component"])
        }

        var tempInputUnit: AudioUnit?
        var status = AudioComponentInstanceNew(inputComponent, &tempInputUnit)
        guard status == noErr, let inputUnit = tempInputUnit else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        self.inputUnit = inputUnit

        // Enable input, disable output on input unit
        var enableIO: UInt32 = 1
        status = AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableIO, UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        enableIO = 0
        status = AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enableIO, UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        // Set input device to BlackHole
        var inputDeviceID = blackholeID
        status = AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &inputDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        // Set up output unit
        var outputDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let outputComponent = AudioComponentFindNext(nil, &outputDesc) else {
            throw NSError(domain: "AudioEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not find output component"])
        }

        var tempOutputUnit: AudioUnit?
        status = AudioComponentInstanceNew(outputComponent, &tempOutputUnit)
        guard status == noErr, let outputUnit = tempOutputUnit else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        self.outputUnit = outputUnit

        // Set output device to speakers
        var outputDeviceID = speakerID
        status = AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &outputDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        // Set stream format (stereo float)
        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )

        status = AudioUnitSetProperty(inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        status = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        // Set up input callback
        var inputCallbackStruct = AURenderCallbackStruct(
            inputProc: inputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &inputCallbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        // Set up output render callback
        var outputCallbackStruct = AURenderCallbackStruct(
            inputProc: outputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &outputCallbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        // Initialize and start
        status = AudioUnitInitialize(inputUnit)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        status = AudioUnitInitialize(outputUnit)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        status = AudioOutputUnitStart(inputUnit)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        status = AudioOutputUnitStart(outputUnit)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private func startLevelMetering() {
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLevels()
            }
        }
    }

    private func updateLevels() {
        let (inL, inR) = dspChain.inputLevels
        let (outL, outR) = dspChain.outputLevels

        // Smooth the levels
        inputLevelLeft = inputLevelLeft * 0.8 + inL * 0.2
        inputLevelRight = inputLevelRight * 0.8 + inR * 0.2
        outputLevelLeft = outputLevelLeft * 0.8 + outL * 0.2
        outputLevelRight = outputLevelRight * 0.8 + outR * 0.2
    }

    #if os(macOS)
    private func findBlackHoleDevice() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return nil }

        for deviceID in deviceIDs {
            if let name = getDeviceName(deviceID), name.lowercased().contains("blackhole") {
                // Check if it has input channels
                if hasInputChannels(deviceID) {
                    return deviceID
                }
            }
        }

        return nil
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr, let cfName = name?.takeRetainedValue() else { return nil }
        return cfName as String
    }

    private func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func findSpeakerDevice() -> AudioDeviceID? {
        // Search patterns in order of preference (same as Rust CLI)
        let patterns = [
            "External Headphones",
            "External Speakers",
            "USB",
            "Headphones",
            "MacBook Pro Speakers",
            "MacBook Air Speakers",
            "speaker",
            "built-in"
        ]

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return nil }

        // Try each pattern in order
        for pattern in patterns {
            for deviceID in deviceIDs {
                if let name = getDeviceName(deviceID),
                   name.lowercased().contains(pattern.lowercased()),
                   hasOutputChannels(deviceID) {
                    Logger.audio.info("Found speaker device: \(name) (ID: \(deviceID))")
                    return deviceID
                }
            }
        }

        return nil
    }

    private func hasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    #endif
}

// MARK: - CoreAudio Callbacks (must be global C functions)

private func inputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let engine = Unmanaged<AudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()

    // Allocate buffer for input data
    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: inNumberFrames * 2 * UInt32(MemoryLayout<Float>.size),
            mData: nil
        )
    )

    let dataSize = Int(inNumberFrames) * 2 * MemoryLayout<Float>.size
    let data = UnsafeMutablePointer<Float>.allocate(capacity: Int(inNumberFrames) * 2)
    defer { data.deallocate() }

    bufferList.mBuffers.mData = UnsafeMutableRawPointer(data)

    // Render input audio
    let status = AudioUnitRender(engine.inputUnit!, ioActionFlags, inTimeStamp, 1, inNumberFrames, &bufferList)
    guard status == noErr else { return status }

    // Push to ring buffer (interleaved stereo)
    for i in 0..<Int(inNumberFrames) * 2 {
        engine.ringBuffer.push(data[i])
    }

    return noErr
}

private func outputCallback(
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

    for frame in 0..<frameCount {
        // Pull from ring buffer (interleaved L, R)
        let left = engine.ringBuffer.pop() ?? 0.0
        let right = engine.ringBuffer.pop() ?? 0.0

        // Process through DSP chain
        let (procL, procR) = engine.dspChain.process(left: left, right: right)

        // Write interleaved output
        outData[frame * 2] = procL
        outData[frame * 2 + 1] = procR

        // Feed analyzer
        engine.fftAnalyzer.push(left: procL, right: procR)
    }

    return noErr
}

// MARK: - Logger Extension

extension Logger {
    static let audio = Logger(subsystem: "com.audiodsp", category: "Audio")
}
