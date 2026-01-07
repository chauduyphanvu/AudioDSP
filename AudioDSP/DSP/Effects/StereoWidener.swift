import Foundation

/// Stereo widener using Mid/Side processing
final class StereoWidener: Effect, @unchecked Sendable {
    private var width: Float = 1.0  // 0.0 = mono, 1.0 = normal, 2.0 = extra wide
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    let name = "Stereo Widener"

    init() {}

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Convert to Mid/Side
        let mid = (left + right) * 0.5
        let side = (left - right) * 0.5

        // Apply width
        let newSide = side * width

        // Convert back to L/R
        let newLeft = mid + newSide
        let newRight = mid - newSide

        return (newLeft, newRight)
    }

    func reset() {
        // No state to reset
    }

    var parameters: [ParameterDescriptor] {
        [
            ParameterDescriptor("Width", min: 0, max: 2, defaultValue: 1.0, unit: .generic),
        ]
    }

    func getParameter(_ index: Int) -> Float {
        switch index {
        case 0: return width
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        if index == 0 {
            width = min(max(value, 0), 2)
        }
    }
}
