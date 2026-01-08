import os

// MARK: - Logger Extension for Audio Subsystem

extension Logger {
    /// Shared logger instance for audio-related diagnostics
    static let audio = Logger(subsystem: "com.audiodsp", category: "Audio")
}
