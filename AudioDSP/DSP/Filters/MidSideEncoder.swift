import Foundation

/// Mid/Side processing mode for stereo field manipulation
enum MSMode: Int, Codable, CaseIterable, Sendable {
    case stereo = 0  // Normal L/R processing
    case mid = 1     // Process mid channel only (mono content)
    case side = 2    // Process side channel only (stereo width)
    case both = 3    // Process both M/S channels independently

    var displayName: String {
        switch self {
        case .stereo: return "Stereo"
        case .mid: return "Mid"
        case .side: return "Side"
        case .both: return "M/S"
        }
    }

    var description: String {
        switch self {
        case .stereo: return "Normal left/right processing"
        case .mid: return "Process center/mono content"
        case .side: return "Process stereo width content"
        case .both: return "Process mid and side independently"
        }
    }
}

/// Utility for encoding/decoding stereo to Mid/Side and back
/// Mid = (L + R) / 2 (mono/center content)
/// Side = (L - R) / 2 (stereo difference/width)
enum MidSideEncoder {
    /// Encode stereo L/R to Mid/Side
    @inline(__always)
    static func encode(left: Float, right: Float) -> (mid: Float, side: Float) {
        let mid = (left + right) * 0.5
        let side = (left - right) * 0.5
        return (mid, side)
    }

    /// Decode Mid/Side back to stereo L/R
    @inline(__always)
    static func decode(mid: Float, side: Float) -> (left: Float, right: Float) {
        let left = mid + side
        let right = mid - side
        return (left, right)
    }

    /// Process stereo signal with separate mid and side processing functions
    @inline(__always)
    static func process(
        left: Float,
        right: Float,
        mode: MSMode,
        processL: (Float) -> Float,
        processR: (Float) -> Float
    ) -> (left: Float, right: Float) {
        switch mode {
        case .stereo:
            // Normal L/R processing
            return (processL(left), processR(right))

        case .mid:
            // Process only mid channel, side passes through
            let (mid, side) = encode(left: left, right: right)
            let processedMid = processL(mid)
            return decode(mid: processedMid, side: side)

        case .side:
            // Process only side channel, mid passes through
            let (mid, side) = encode(left: left, right: right)
            let processedSide = processR(side)
            return decode(mid: mid, side: processedSide)

        case .both:
            // Process both mid and side independently
            let (mid, side) = encode(left: left, right: right)
            let processedMid = processL(mid)
            let processedSide = processR(side)
            return decode(mid: processedMid, side: processedSide)
        }
    }
}

/// M/S Width control utility
enum MidSideWidth {
    /// Adjust stereo width using M/S processing
    /// width: 0 = mono, 1 = original, 2 = extra wide
    @inline(__always)
    static func adjustWidth(left: Float, right: Float, width: Float) -> (left: Float, right: Float) {
        let (mid, side) = MidSideEncoder.encode(left: left, right: right)

        // Adjust side level relative to mid
        let adjustedSide = side * width

        return MidSideEncoder.decode(mid: mid, side: adjustedSide)
    }

    /// Adjust mid and side levels independently
    /// midGain: linear gain for mid channel
    /// sideGain: linear gain for side channel
    @inline(__always)
    static func adjustBalance(
        left: Float,
        right: Float,
        midGain: Float,
        sideGain: Float
    ) -> (left: Float, right: Float) {
        let (mid, side) = MidSideEncoder.encode(left: left, right: right)
        let adjustedMid = mid * midGain
        let adjustedSide = side * sideGain
        return MidSideEncoder.decode(mid: adjustedMid, side: adjustedSide)
    }
}
