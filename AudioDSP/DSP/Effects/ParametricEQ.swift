import Foundation

/// 5-band Parametric Equalizer
final class ParametricEQ: Effect, @unchecked Sendable {
    private var bands: [EQBand]
    private let sampleRate: Float
    var isBypassed: Bool = false
    var wetDry: Float = 1.0

    let name = "Parametric EQ"

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate

        // Default 5-band layout: Low Shelf, 3x Peak, High Shelf
        bands = [
            EQBand(sampleRate: sampleRate, bandType: .lowShelf, frequency: 80, gainDb: 0, q: 0.707),
            EQBand(sampleRate: sampleRate, bandType: .peak, frequency: 250, gainDb: 0, q: 1.0),
            EQBand(sampleRate: sampleRate, bandType: .peak, frequency: 1000, gainDb: 0, q: 1.0),
            EQBand(sampleRate: sampleRate, bandType: .peak, frequency: 4000, gainDb: 0, q: 1.0),
            EQBand(sampleRate: sampleRate, bandType: .highShelf, frequency: 12000, gainDb: 0, q: 0.707),
        ]
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        var l = left
        var r = right

        for band in bands {
            let result = band.process(left: l, right: r)
            l = result.left
            r = result.right
        }

        return (l, r)
    }

    func reset() {
        for band in bands {
            band.reset()
        }
    }

    func setBand(_ index: Int, bandType: BandType, frequency: Float, gainDb: Float, q: Float) {
        guard index >= 0, index < bands.count else { return }
        bands[index].update(bandType: bandType, frequency: frequency, gainDb: gainDb, q: q)
    }

    func getBand(_ index: Int) -> EQBand? {
        guard index >= 0, index < bands.count else { return nil }
        return bands[index]
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

        for band in bands {
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

    /// Get array of band info for UI
    var bandInfo: [(frequency: Float, gainDb: Float, q: Float, bandType: BandType)] {
        bands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType) }
    }
}
