import Foundation

// MARK: - Decibel Conversions

/// Convert decibels to linear amplitude
@inline(__always)
func dbToLinear(_ db: Float) -> Float {
    powf(10.0, db / 20.0)
}

/// Convert linear amplitude to decibels (clamps to avoid -infinity)
@inline(__always)
func linearToDb(_ linear: Float) -> Float {
    20.0 * log10f(max(linear, 1e-10))
}

// MARK: - Stereo Utilities

/// Compute peak value from stereo sample pair
@inline(__always)
func stereoPeak(_ left: Float, _ right: Float) -> Float {
    max(abs(left), abs(right))
}
