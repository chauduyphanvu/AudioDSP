import AudioToolbox
import os

/// Manages CoreAudio device discovery and inspection
/// All methods are macOS-specific and require access to the system audio hardware
#if os(macOS)
enum AudioDeviceManager {
    // MARK: - Device Discovery

    /// Find the BlackHole virtual audio device for system audio capture
    /// Returns the device ID if found and has input channels, nil otherwise
    static func findBlackHoleDevice() -> AudioDeviceID? {
        guard let deviceIDs = getAllDeviceIDs() else { return nil }

        for deviceID in deviceIDs {
            if let name = getDeviceName(deviceID),
               name.lowercased().contains("blackhole"),
               hasInputChannels(deviceID) {
                return deviceID
            }
        }

        return nil
    }

    /// Find a suitable speaker/headphone output device
    /// Searches using priority patterns matching common macOS audio outputs
    static func findSpeakerDevice() -> AudioDeviceID? {
        guard let deviceIDs = getAllDeviceIDs() else { return nil }

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

    // MARK: - Device Properties

    /// Get the human-readable name of an audio device
    static func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
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

    /// Get the nominal sample rate of an audio device
    static func getNominalSampleRate(_ deviceID: AudioDeviceID) -> Double? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &sampleRate
        )

        guard status == noErr, sampleRate > 0, sampleRate <= 384000 else { return nil }
        return sampleRate
    }

    /// Check if device has input channels available
    static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        channelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput) > 0
    }

    /// Check if device has output channels available
    static func hasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        channelCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput) > 0
    }

    /// Get channel count for a device with the specified scope (input or output)
    static func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return 0 }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else { return 0 }

        return UnsafeMutableAudioBufferListPointer(bufferListPointer)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    // MARK: - Private Helpers

    /// Get all audio device IDs on the system
    private static func getAllDeviceIDs() -> [AudioDeviceID]? {
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

        return deviceIDs
    }
}
#endif
