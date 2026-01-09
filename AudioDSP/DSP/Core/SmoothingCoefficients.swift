import Foundation

// MARK: - Time Constants

/// Calculate exponential smoothing coefficient from time constant in milliseconds.
/// Used for envelope followers, parameter smoothers, and meter ballistics.
/// Formula: coeff = exp(-1 / (timeMs * 0.001 * sampleRate))
@inline(__always)
func timeToCoefficient(_ timeMs: Float, sampleRate: Float) -> Float {
    guard timeMs > 0 else { return 0 }
    return expf(-1.0 / (timeMs * 0.001 * sampleRate))
}

/// Calculate smoothing coefficient from time constant in seconds
@inline(__always)
func timeToCoefficient(seconds: Float, sampleRate: Float) -> Float {
    guard seconds > 0 else { return 0 }
    return expf(-1.0 / (seconds * sampleRate))
}

// MARK: - Denormal Handling

/// Flush value to zero if it's a denormal (below threshold).
/// Denormals can cause severe CPU penalties on some processors.
@inline(__always)
func flushDenormals(_ value: Float) -> Float {
    abs(value) < 1e-15 ? 0 : value
}

/// Flush value to zero with custom threshold
@inline(__always)
func flushDenormals(_ value: Float, threshold: Float) -> Float {
    abs(value) < threshold ? 0 : value
}
