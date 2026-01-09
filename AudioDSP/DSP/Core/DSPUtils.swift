import Foundation

// MARK: - Clamping Extension

extension Comparable {
    /// Clamp value to a closed range. More readable than min(max(value, lower), upper).
    @inline(__always)
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
