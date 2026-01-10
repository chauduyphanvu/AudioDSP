import AVFoundation
import AudioToolbox
import Combine
import os

/// Audio engine using low-level CoreAudio for full device control (like Rust CLI)
@MainActor
final class AudioEngine: ObservableObject {
    // MARK: - Audio Thread Accessible Properties

    // These are accessed from audio thread callbacks - must be nonisolated
    // dspChain and fftAnalyzer need internal access for UI
    nonisolated(unsafe) var dspChain: DSPChain?
    nonisolated(unsafe) let fftAnalyzer: FFTAnalyzer

    // Ring buffer sized for low latency: 4096 samples = ~85ms at 48kHz
    // This provides enough headroom for callback timing differences while keeping latency low
    nonisolated(unsafe) let ringBuffer = StereoRingBuffer(capacity: 4096)

    // Audio units - accessed by callbacks via refCon
    nonisolated(unsafe) var inputUnit: AudioUnit?
    nonisolated(unsafe) private(set) var outputUnit: AudioUnit?

    // Pre-allocated buffer for input callback to avoid real-time allocation
    // Size for max expected buffer: 4096 frames * 2 channels
    nonisolated(unsafe) let inputBuffer: UnsafeMutablePointer<Float>
    private let inputBufferCapacity: Int = 4096 * 2

    // MARK: - Published UI State

    @Published var inputLevelLeft: Float = 0
    @Published var inputLevelRight: Float = 0
    @Published var outputLevelLeft: Float = 0
    @Published var outputLevelRight: Float = 0

    @Published var spectrumData: [Float] = []

    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "Ready"

    // MARK: - Configuration

    private(set) var sampleRate: Double = 48000
    let channels: Int = 2

    // MARK: - Private State

    private var levelUpdateTimer: Timer?

    // MARK: - Lifecycle

    init() {
        fftAnalyzer = FFTAnalyzer(fftSize: 2048)

        // Pre-allocate input buffer to avoid allocation on audio thread
        inputBuffer = UnsafeMutablePointer<Float>.allocate(capacity: inputBufferCapacity)
        inputBuffer.initialize(repeating: 0, count: inputBufferCapacity)
    }

    deinit {
        // Stop audio units directly to prevent callback crashes during deallocation
        // Note: stop() should ideally be called before the engine is released,
        // but we perform direct cleanup here as a safety measure
        if let unit = inputUnit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
        }
        if let unit = outputUnit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
        }
        inputBuffer.deinitialize(count: inputBufferCapacity)
        inputBuffer.deallocate()
    }

    // MARK: - Public API

    func start() async {
        do {
            try setupCoreAudio()
            isRunning = true
            statusMessage = "Processing audio"
            startLevelMetering()
            postEngineStatusNotification(isRunning: true)
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
        postEngineStatusNotification(isRunning: false)

        Logger.audio.info("Audio engine stopped")
    }

    private func postEngineStatusNotification(isRunning: Bool) {
        NotificationCenter.default.post(
            name: .engineStatusChanged,
            object: nil,
            userInfo: ["isRunning": isRunning]
        )
    }

    // MARK: - CoreAudio Setup

    private func setupCoreAudio() throws {
        // Find devices using AudioDeviceManager
        guard let blackholeID = AudioDeviceManager.findBlackHoleDevice() else {
            throw AudioEngineError.deviceNotFound("BlackHole not found")
        }
        guard let speakerID = AudioDeviceManager.findSpeakerDevice() else {
            throw AudioEngineError.deviceNotFound("No speaker device found")
        }

        // Query output device sample rate (speaker is the master clock)
        if let deviceSampleRate = AudioDeviceManager.getNominalSampleRate(speakerID) {
            sampleRate = deviceSampleRate
            Logger.audio.info("Using device sample rate: \(deviceSampleRate) Hz")
        } else {
            Logger.audio.warning("Could not query sample rate, using default: \(self.sampleRate) Hz")
        }

        // Create DSP chain with detected sample rate
        dspChain = DSPChain.createDefault(sampleRate: Float(sampleRate))

        Logger.audio.info("Using BlackHole ID: \(blackholeID), Speaker ID: \(speakerID)")

        try setupInputUnit(deviceID: blackholeID)
        try setupOutputUnit(deviceID: speakerID)
        try configureStreamFormat()
        try installCallbacks()
        try initializeAndStartUnits()
    }

    private func setupInputUnit(deviceID: AudioDeviceID) throws {
        var inputDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let inputComponent = AudioComponentFindNext(nil, &inputDesc) else {
            throw AudioEngineError.componentNotFound("Could not find input component")
        }

        var tempInputUnit: AudioUnit?
        var status = AudioComponentInstanceNew(inputComponent, &tempInputUnit)
        guard status == noErr, let unit = tempInputUnit else {
            throw AudioEngineError.osStatus(status)
        }
        self.inputUnit = unit

        // Enable input, disable output on input unit
        var enableIO: UInt32 = 1
        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input, 1, &enableIO, UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else { throw AudioEngineError.osStatus(status) }

        enableIO = 0
        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output, 0, &enableIO, UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else { throw AudioEngineError.osStatus(status) }

        // Set input device to BlackHole
        var inputDeviceID = deviceID
        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &inputDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw AudioEngineError.osStatus(status) }
    }

    private func setupOutputUnit(deviceID: AudioDeviceID) throws {
        var outputDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let outputComponent = AudioComponentFindNext(nil, &outputDesc) else {
            throw AudioEngineError.componentNotFound("Could not find output component")
        }

        var tempOutputUnit: AudioUnit?
        var status = AudioComponentInstanceNew(outputComponent, &tempOutputUnit)
        guard status == noErr, let unit = tempOutputUnit else {
            throw AudioEngineError.osStatus(status)
        }
        self.outputUnit = unit

        // Set output device to speakers
        var outputDeviceID = deviceID
        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &outputDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw AudioEngineError.osStatus(status) }
    }

    private func configureStreamFormat() throws {
        guard let inputUnit = inputUnit, let outputUnit = outputUnit else {
            throw AudioEngineError.invalidState("Audio units not initialized")
        }

        // Use interleaved 32-bit float format
        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
            mBytesPerPacket: UInt32(channels * MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )

        var status = AudioUnitSetProperty(
            inputUnit, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output, 1, &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else { throw AudioEngineError.osStatus(status) }

        status = AudioUnitSetProperty(
            outputUnit, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input, 0, &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else { throw AudioEngineError.osStatus(status) }
    }

    private func installCallbacks() throws {
        guard let inputUnit = inputUnit, let outputUnit = outputUnit else {
            throw AudioEngineError.invalidState("Audio units not initialized")
        }

        // Set up input callback
        var inputCallbackStruct = AURenderCallbackStruct(
            inputProc: audioEngineInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        var status = AudioUnitSetProperty(
            inputUnit, kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global, 0, &inputCallbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else { throw AudioEngineError.osStatus(status) }

        // Set up output render callback
        var outputCallbackStruct = AURenderCallbackStruct(
            inputProc: audioEngineOutputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            outputUnit, kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input, 0, &outputCallbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else { throw AudioEngineError.osStatus(status) }
    }

    private func initializeAndStartUnits() throws {
        guard let inputUnit = inputUnit, let outputUnit = outputUnit else {
            throw AudioEngineError.invalidState("Audio units not initialized")
        }

        var status = AudioUnitInitialize(inputUnit)
        guard status == noErr else { throw AudioEngineError.osStatus(status) }

        status = AudioUnitInitialize(outputUnit)
        guard status == noErr else { throw AudioEngineError.osStatus(status) }

        status = AudioOutputUnitStart(inputUnit)
        guard status == noErr else { throw AudioEngineError.osStatus(status) }

        status = AudioOutputUnitStart(outputUnit)
        guard status == noErr else { throw AudioEngineError.osStatus(status) }
    }

    // MARK: - Level Metering

    private func startLevelMetering() {
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLevels()
            }
        }
    }

    private func updateLevels() {
        guard let dspChain else { return }

        let (inL, inR) = dspChain.inputLevels
        let (outL, outR) = dspChain.outputLevels

        // Smooth the levels with exponential moving average
        inputLevelLeft = inputLevelLeft * 0.8 + inL * 0.2
        inputLevelRight = inputLevelRight * 0.8 + inR * 0.2
        outputLevelLeft = outputLevelLeft * 0.8 + outL * 0.2
        outputLevelRight = outputLevelRight * 0.8 + outR * 0.2

        // Update spectrum data from FFT analyzer
        spectrumData = fftAnalyzer.analyze()
    }
}

// MARK: - Error Types

enum AudioEngineError: LocalizedError {
    case deviceNotFound(String)
    case componentNotFound(String)
    case osStatus(OSStatus)
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let message):
            return message
        case .componentNotFound(let message):
            return message
        case .osStatus(let status):
            return "CoreAudio error: \(status)"
        case .invalidState(let message):
            return message
        }
    }
}
