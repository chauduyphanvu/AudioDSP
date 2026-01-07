import Foundation

/// Schroeder reverb: 4 parallel comb filters + 2 series allpass filters
final class Reverb: Effect, @unchecked Sendable {
    // Comb filter delays in samples at 44100 Hz (scaled for sample rate)
    private static let combDelays: [Int] = [1116, 1188, 1277, 1356]
    private static let allpassDelays: [Int] = [556, 441]

    // Comb filters (parallel)
    private var combBuffersL: [[Float]]
    private var combBuffersR: [[Float]]
    private var combIndices: [Int]
    private var combFeedback: [Float]

    // Allpass filters (series)
    private var allpassBuffersL: [[Float]]
    private var allpassBuffersR: [[Float]]
    private var allpassIndices: [Int]

    private var roomSize: Float = 0.5 {
        didSet { updateFeedback() }
    }
    private var damping: Float = 0.5
    private var width: Float = 1.0

    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 0.3

    let name = "Reverb"

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate

        let scale = sampleRate / 44100.0

        let combSizes = Self.combDelays.map { max(1, Int(Float($0) * scale)) }
        let allpassSizes = Self.allpassDelays.map { max(1, Int(Float($0) * scale)) }

        combBuffersL = combSizes.map { [Float](repeating: 0, count: $0) }
        combBuffersR = combSizes.map { [Float](repeating: 0, count: $0) }
        combIndices = [Int](repeating: 0, count: 4)
        combFeedback = [Float](repeating: 0.84, count: 4)

        allpassBuffersL = allpassSizes.map { [Float](repeating: 0, count: $0) }
        allpassBuffersR = allpassSizes.map { [Float](repeating: 0, count: $0) }
        allpassIndices = [Int](repeating: 0, count: 2)
    }

    private func updateFeedback() {
        // Map roomSize (0-1) to feedback (0.7-0.98)
        let baseFeedback = 0.7 + roomSize * 0.28
        for i in 0..<combFeedback.count {
            combFeedback[i] = baseFeedback
        }
    }

    @inline(__always)
    private func processComb(inputL: Float, inputR: Float, index: Int) -> (Float, Float) {
        let idx = combIndices[index]

        let outL = combBuffersL[index][idx]
        let outR = combBuffersR[index][idx]

        let feedback = combFeedback[index]
        let damp = damping

        combBuffersL[index][idx] = inputL + outL * feedback * (1.0 - damp)
        combBuffersR[index][idx] = inputR + outR * feedback * (1.0 - damp)

        combIndices[index] = (idx + 1) % combBuffersL[index].count

        return (outL, outR)
    }

    @inline(__always)
    private func processAllpass(inputL: Float, inputR: Float, index: Int) -> (Float, Float) {
        let idx = allpassIndices[index]

        let bufferedL = allpassBuffersL[index][idx]
        let bufferedR = allpassBuffersR[index][idx]

        let g: Float = 0.5

        let outL = bufferedL - inputL
        let outR = bufferedR - inputR

        allpassBuffersL[index][idx] = inputL + bufferedL * g
        allpassBuffersR[index][idx] = inputR + bufferedR * g

        allpassIndices[index] = (idx + 1) % allpassBuffersL[index].count

        return (outL, outR)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        // Mix input to mono for reverb processing
        let input = (left + right) * 0.5

        // Process through parallel comb filters
        var sumL: Float = 0
        var sumR: Float = 0

        for i in 0..<4 {
            let (outL, outR) = processComb(inputL: input, inputR: input, index: i)
            sumL += outL
            sumR += outR
        }

        // Normalize
        sumL *= 0.25
        sumR *= 0.25

        // Process through series allpass filters
        var (outL, outR) = processAllpass(inputL: sumL, inputR: sumR, index: 0)
        (outL, outR) = processAllpass(inputL: outL, inputR: outR, index: 1)

        // Apply stereo width
        let mid = (outL + outR) * 0.5
        let side = (outL - outR) * 0.5 * width

        return (mid + side, mid - side)
    }

    func reset() {
        for i in 0..<combBuffersL.count {
            combBuffersL[i] = [Float](repeating: 0, count: combBuffersL[i].count)
            combBuffersR[i] = [Float](repeating: 0, count: combBuffersR[i].count)
        }
        for i in 0..<allpassBuffersL.count {
            allpassBuffersL[i] = [Float](repeating: 0, count: allpassBuffersL[i].count)
            allpassBuffersR[i] = [Float](repeating: 0, count: allpassBuffersR[i].count)
        }
        combIndices = [Int](repeating: 0, count: 4)
        allpassIndices = [Int](repeating: 0, count: 2)
    }

    var parameters: [ParameterDescriptor] {
        [
            ParameterDescriptor("Room Size", min: 0, max: 1, defaultValue: 0.5, unit: .percent),
            ParameterDescriptor("Damping", min: 0, max: 1, defaultValue: 0.5, unit: .percent),
            ParameterDescriptor("Width", min: 0, max: 1, defaultValue: 1.0, unit: .percent),
        ]
    }

    func getParameter(_ index: Int) -> Float {
        switch index {
        case 0: return roomSize
        case 1: return damping
        case 2: return width
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        switch index {
        case 0:
            roomSize = min(max(value, 0), 1)
        case 1:
            damping = min(max(value, 0), 1)
        case 2:
            width = min(max(value, 0), 1)
        default: break
        }
    }
}
