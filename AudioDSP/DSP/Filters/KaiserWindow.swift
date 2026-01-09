import Foundation

// MARK: - Kaiser Window

/// Kaiser window implementation for FIR filter design.
/// Provides excellent control over sidelobe levels via the beta parameter.
enum KaiserWindow {
    /// Apply Kaiser window to a buffer in-place.
    /// - Parameters:
    ///   - buffer: The buffer to window (modified in place)
    ///   - beta: Shape parameter controlling sidelobe attenuation (typical: 5-10)
    static func apply(to buffer: inout [Float], beta: Float) {
        let N = buffer.count
        let halfN = Float(N - 1) / 2.0
        let i0Beta = besselI0(beta)

        for n in 0..<N {
            let x = (Float(n) - halfN) / halfN
            let arg = beta * sqrt(max(0, 1 - x * x))
            let window = besselI0(arg) / i0Beta
            buffer[n] *= window
        }
    }

    /// Generate Kaiser window coefficients.
    /// - Parameters:
    ///   - length: Number of window samples
    ///   - beta: Shape parameter controlling sidelobe attenuation
    /// - Returns: Array of window coefficients
    static func generate(length: Int, beta: Float) -> [Float] {
        var window = [Float](repeating: 1.0, count: length)
        apply(to: &window, beta: beta)
        return window
    }

    /// Zeroth-order modified Bessel function of the first kind.
    /// Used in Kaiser window calculation.
    private static func besselI0(_ x: Float) -> Float {
        var sum: Float = 1.0
        var term: Float = 1.0
        let x2 = x * x / 4.0

        for k in 1...20 {
            term *= x2 / Float(k * k)
            sum += term
            if term < 1e-10 { break }
        }
        return sum
    }
}
