import Foundation

/// 5-band Parametric Equalizer with soft clipping protection and solo mode
final class ParametricEQ: Effect, @unchecked Sendable {
    private var bands: [EQBand]
    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    let name = "Parametric EQ"

    // Soft clipper for gain staging protection
    // Threshold at ~0.9 linear amplitude (-0.92 dB)
    private let softClipThreshold: Float = 0.9
    private let softClipKnee: Float = 0.1

    // 2x oversampling state for anti-aliased soft clipping
    // Prevents harmonic aliasing from the tanh nonlinearity at high frequencies
    private var oversamplePrevL: Float = 0
    private var oversamplePrevR: Float = 0
    // Previous clipped samples for 3-tap downsampling filter [0.25, 0.5, 0.25]
    // Provides ~-18dB rejection at Nyquist vs ~-6dB with simple averaging
    private var downsamplePrevClipL: Float = 0
    private var downsamplePrevClipR: Float = 0

    // Atomic solo bitmask - each bit represents a band's solo state
    // Uses atomic operations for thread-safe access between UI and audio threads
    // With 5 bands, bits 0-4 are used
    private let soloMaskPtr: UnsafeMutablePointer<UInt32>

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate

        // Allocate atomic solo mask
        self.soloMaskPtr = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        soloMaskPtr.initialize(to: 0)

        // Default 5-band layout: Low Shelf, 3x Peak, High Shelf
        bands = [
            EQBand(sampleRate: sampleRate, bandType: .lowShelf, frequency: 80, gainDb: 0, q: 0.707),
            EQBand(sampleRate: sampleRate, bandType: .peak, frequency: 250, gainDb: 0, q: 1.0),
            EQBand(sampleRate: sampleRate, bandType: .peak, frequency: 1000, gainDb: 0, q: 1.0),
            EQBand(sampleRate: sampleRate, bandType: .peak, frequency: 4000, gainDb: 0, q: 1.0),
            EQBand(sampleRate: sampleRate, bandType: .highShelf, frequency: 12000, gainDb: 0, q: 0.707),
        ]
    }

    deinit {
        soloMaskPtr.deinitialize(count: 1)
        soloMaskPtr.deallocate()
    }

    /// Get current solo mask atomically (thread-safe for audio thread)
    /// OSAtomicAdd32(0, ...) returns the current value after adding 0, which is an atomic read
    @inline(__always)
    private func getSoloMask() -> UInt32 {
        let signed = OSAtomicAdd32(0, UnsafeMutablePointer<Int32>(OpaquePointer(soloMaskPtr)))
        return UInt32(bitPattern: signed)
    }

    /// Set solo bit for a band atomically
    private func setSoloBit(_ index: Int, _ value: Bool) {
        let bit = UInt32(1 << index)
        if value {
            OSAtomicOr32(bit, UnsafeMutablePointer<UInt32>(soloMaskPtr))
        } else {
            OSAtomicAnd32(~bit, UnsafeMutablePointer<UInt32>(soloMaskPtr))
        }
    }

    /// Core soft clipper function - tanh-based saturation for musical limiting
    @inline(__always)
    private func softClipCore(_ sample: Float) -> Float {
        let threshold = softClipThreshold
        let absSample = abs(sample)

        if absSample <= threshold {
            return sample
        }

        // Soft saturation above threshold using tanh
        let sign: Float = sample >= 0 ? 1 : -1
        let excess = absSample - threshold
        let knee = softClipKnee

        // Smooth transition using tanh compression
        let compressed = threshold + knee * tanh(excess / knee)
        return sign * min(compressed, 1.0)
    }

    /// 2x oversampled soft clipper to prevent harmonic aliasing
    /// Uses linear interpolation for upsampling and 3-tap filter for downsampling
    /// The 3-tap filter [0.25, 0.5, 0.25] provides ~-18dB rejection at Nyquist
    @inline(__always)
    private func softClipOversampled(left: Float, right: Float) -> (Float, Float) {
        // Check if soft clipping is needed (optimization: skip oversampling if below threshold)
        let maxSample = max(abs(left), abs(right))
        if maxSample <= softClipThreshold {
            oversamplePrevL = left
            oversamplePrevR = right
            downsamplePrevClipL = left
            downsamplePrevClipR = right
            return (left, right)
        }

        // 2x upsample using linear interpolation
        let upL0 = (oversamplePrevL + left) * 0.5  // Interpolated sample
        let upL1 = left                              // Original sample
        let upR0 = (oversamplePrevR + right) * 0.5
        let upR1 = right

        // Apply soft clipping at 2x rate
        let clipL0 = softClipCore(upL0)
        let clipL1 = softClipCore(upL1)
        let clipR0 = softClipCore(upR0)
        let clipR1 = softClipCore(upR1)

        // Store for next interpolation
        oversamplePrevL = left
        oversamplePrevR = right

        // 3-tap downsample filter [0.25, 0.5, 0.25] for better anti-aliasing
        // This provides ~-18dB rejection at Nyquist vs ~-6dB with simple averaging
        let outL = 0.25 * downsamplePrevClipL + 0.5 * clipL0 + 0.25 * clipL1
        let outR = 0.25 * downsamplePrevClipR + 0.5 * clipR0 + 0.25 * clipR1

        // Store clipped sample for next iteration's filter
        downsamplePrevClipL = clipL1
        downsamplePrevClipR = clipR1

        return (outL, outR)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        var l = left
        var r = right

        // Read solo mask atomically (thread-safe)
        let soloMask = getSoloMask()

        if soloMask != 0 {
            // Process only soloed bands using atomic bitmask
            for index in 0..<bands.count {
                if (soloMask & UInt32(1 << index)) != 0 {
                    let result = bands[index].process(left: l, right: r)
                    l = result.left
                    r = result.right
                }
            }
        } else {
            // Normal processing - all bands in series
            for band in bands {
                let result = band.process(left: l, right: r)
                l = result.left
                r = result.right
            }
        }

        // Apply 2x oversampled soft clipping to prevent aliasing from harmonic distortion
        let clipped = softClipOversampled(left: l, right: r)

        return clipped
    }

    func reset() {
        for band in bands {
            band.reset()
        }
        // Reset oversampling state
        oversamplePrevL = 0
        oversamplePrevR = 0
        downsamplePrevClipL = 0
        downsamplePrevClipR = 0
    }

    func setBand(_ index: Int, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        guard index >= 0, index < bands.count else { return }
        bands[index].update(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q)
    }

    func setSolo(_ index: Int, solo: Bool) {
        guard index >= 0, index < bands.count else { return }
        bands[index].setSolo(solo)
        setSoloBit(index, solo)
    }

    func setBandEnabled(_ index: Int, enabled: Bool) {
        guard index >= 0, index < bands.count else { return }
        bands[index].setEnabled(enabled)
    }

    func clearAllSolo() {
        for (index, band) in bands.enumerated() {
            band.setSolo(false)
            setSoloBit(index, false)
        }
    }

    func getBand(_ index: Int) -> EQBand? {
        guard index >= 0, index < bands.count else { return nil }
        return bands[index]
    }

    func isBandSoloed(_ index: Int) -> Bool {
        guard index >= 0, index < bands.count else { return false }
        return (getSoloMask() & UInt32(1 << index)) != 0
    }

    var hasSoloedBand: Bool {
        getSoloMask() != 0
    }

    var bandCount: Int { bands.count }

    // MARK: - Parameter Interface

    var parameters: [ParameterDescriptor] {
        var params: [ParameterDescriptor] = []
        for i in 0..<bands.count {
            params.append(ParameterDescriptor("Band \(i + 1) Freq", min: 20, max: 20000, defaultValue: bands[i].frequency, unit: .hertz))
            params.append(ParameterDescriptor("Band \(i + 1) Gain", min: -24, max: 24, defaultValue: 0, unit: .decibels))
            params.append(ParameterDescriptor("Band \(i + 1) Q", min: 0.1, max: 10, defaultValue: 1.0, unit: .generic))
        }
        return params
    }

    func getParameter(_ index: Int) -> Float {
        let bandIndex = index / 3
        let paramType = index % 3

        guard let band = getBand(bandIndex) else { return 0 }

        switch paramType {
        case 0: return band.frequency
        case 1: return band.gainDb
        case 2: return band.q
        default: return 0
        }
    }

    func setParameter(_ index: Int, value: Float) {
        let bandIndex = index / 3
        let paramType = index % 3

        guard let band = getBand(bandIndex) else { return }

        let freq: Float
        let gain: Float
        let q: Float

        switch paramType {
        case 0:
            freq = min(max(value, 20), 20000)
            gain = band.gainDb
            q = band.q
        case 1:
            freq = band.frequency
            gain = min(max(value, -24), 24)
            q = band.q
        case 2:
            freq = band.frequency
            gain = band.gainDb
            q = min(max(value, 0.1), 10)
        default:
            return
        }

        band.update(bandType: band.bandType, frequency: freq, gainDb: gain, q: q)
    }

    /// Calculate frequency response magnitude at a given frequency
    func magnitudeAt(frequency: Float) -> Float {
        var magnitude: Float = 1.0

        // Check if any band is soloed
        let soloedBands = bands.filter { $0.solo }
        let bandsToProcess = soloedBands.isEmpty ? bands : soloedBands

        for band in bandsToProcess {
            let omega = 2.0 * Float.pi * frequency / sampleRate
            let cosOmega = cos(omega)
            let cos2Omega = cos(2.0 * omega)
            let sinOmega = sin(omega)
            let sin2Omega = sin(2.0 * omega)

            let coeffs = BiquadCoefficients.calculate(
                type: band.bandType.toBiquadType(gainDb: band.gainDb),
                sampleRate: sampleRate,
                frequency: band.frequency,
                q: band.q
            )

            // H(e^jw) = (b0 + b1*e^-jw + b2*e^-2jw) / (1 + a1*e^-jw + a2*e^-2jw)
            let numReal = coeffs.b0 + coeffs.b1 * cosOmega + coeffs.b2 * cos2Omega
            let numImag = -coeffs.b1 * sinOmega - coeffs.b2 * sin2Omega
            let denReal = 1.0 + coeffs.a1 * cosOmega + coeffs.a2 * cos2Omega
            let denImag = -coeffs.a1 * sinOmega - coeffs.a2 * sin2Omega

            let numMag = sqrt(numReal * numReal + numImag * numImag)
            let denMag = sqrt(denReal * denReal + denImag * denImag)

            magnitude *= numMag / max(denMag, 1e-10)
        }

        return magnitude
    }

    /// Calculate phase response at a given frequency (in radians)
    func phaseAt(frequency: Float) -> Float {
        var totalPhase: Float = 0.0

        // Check if any band is soloed
        let soloedBands = bands.filter { $0.solo }
        let bandsToProcess = soloedBands.isEmpty ? bands : soloedBands

        for band in bandsToProcess {
            let omega = 2.0 * Float.pi * frequency / sampleRate
            let cosOmega = cos(omega)
            let cos2Omega = cos(2.0 * omega)
            let sinOmega = sin(omega)
            let sin2Omega = sin(2.0 * omega)

            let coeffs = BiquadCoefficients.calculate(
                type: band.bandType.toBiquadType(gainDb: band.gainDb),
                sampleRate: sampleRate,
                frequency: band.frequency,
                q: band.q
            )

            // Calculate complex transfer function
            let numReal = coeffs.b0 + coeffs.b1 * cosOmega + coeffs.b2 * cos2Omega
            let numImag = -coeffs.b1 * sinOmega - coeffs.b2 * sin2Omega
            let denReal = 1.0 + coeffs.a1 * cosOmega + coeffs.a2 * cos2Omega
            let denImag = -coeffs.a1 * sinOmega - coeffs.a2 * sin2Omega

            // Phase = atan2(imag, real) for numerator - atan2(imag, real) for denominator
            let numPhase = atan2(numImag, numReal)
            let denPhase = atan2(denImag, denReal)

            totalPhase += numPhase - denPhase
        }

        return totalPhase
    }

    /// Get array of band info for UI
    var bandInfo: [(frequency: Float, gainDb: Float, q: Float, bandType: BandType)] {
        bands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType) }
    }

    /// Get array of band info including solo state
    var bandInfoWithSolo: [(frequency: Float, gainDb: Float, q: Float, bandType: BandType, solo: Bool)] {
        bands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType, $0.solo) }
    }
}
