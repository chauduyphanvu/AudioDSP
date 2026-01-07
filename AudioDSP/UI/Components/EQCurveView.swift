import SwiftUI

/// EQ frequency response curve visualization with optional spectrum overlay
struct EQCurveView: View {
    var bands: [(frequency: Float, gainDb: Float, q: Float, bandType: BandType)]
    var selectedBand: Int?
    var onBandSelected: ((Int) -> Void)?
    var height: CGFloat = 150
    var sampleRate: Float = 48000  // Actual sample rate from audio engine
    var spectrumData: [Float] = []  // FFT magnitudes in dB for overlay
    var fftSize: Int = 2048

    private let minFreq: Float = 20
    private let maxFreq: Float = 20000
    private let minDb: Float = -24
    private let maxDb: Float = 24
    private let spectrumMinDb: Float = -80
    private let spectrumMaxDb: Float = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid
                eqGrid(size: geometry.size)

                // Spectrum analyzer overlay (behind EQ curve)
                if !spectrumData.isEmpty {
                    spectrumOverlay(size: geometry.size)
                        .fill(DSPTheme.spectrumGradient.opacity(0.25))

                    spectrumOverlay(size: geometry.size)
                        .stroke(DSPTheme.spectrumLine.opacity(0.3), lineWidth: 1)
                }

                // Frequency response curve
                responseCurve(size: geometry.size)
                    .stroke(DSPTheme.accent, lineWidth: 2)
                    .shadow(color: DSPTheme.accent.opacity(0.5), radius: 4)

                // Fill under curve
                responseCurveFill(size: geometry.size)
                    .fill(DSPTheme.accent.opacity(0.1))

                // Band markers
                ForEach(0..<bands.count, id: \.self) { index in
                    bandMarker(index: index, size: geometry.size)
                }

                // Zero line
                Path { path in
                    let y = dbToY(0, height: geometry.size.height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                .stroke(DSPTheme.textTertiary.opacity(0.5), lineWidth: 1)
            }
        }
        .frame(height: height)
        .background(DSPTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DSPTheme.borderColor, lineWidth: 1)
        )
    }

    private func eqGrid(size: CGSize) -> some View {
        Canvas { context, _ in
            // Horizontal dB lines
            for db in stride(from: -24, through: 24, by: 6) {
                let y = dbToY(Float(db), height: size.height)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))

                let opacity: Double = db == 0 ? 0.4 : 0.15
                context.stroke(path, with: .color(DSPTheme.textTertiary.opacity(opacity)), lineWidth: 0.5)
            }

            // Vertical frequency lines
            let freqLines: [Float] = [50, 100, 200, 500, 1000, 2000, 5000, 10000]
            for freq in freqLines {
                let x = freqToX(freq, width: size.width)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(DSPTheme.textTertiary.opacity(0.15)), lineWidth: 0.5)
            }
        }
    }

    private func responseCurve(size: CGSize) -> Path {
        Path { path in
            let points = 200
            for i in 0..<points {
                let normalized = Float(i) / Float(points - 1)
                let freq = minFreq * powf(maxFreq / minFreq, normalized)
                let magnitude = calculateMagnitude(at: freq)
                let db = linearToDb(magnitude)

                let x = freqToX(freq, width: size.width)
                let y = dbToY(db, height: size.height)

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func responseCurveFill(size: CGSize) -> Path {
        var path = responseCurve(size: size)
        let zeroY = dbToY(0, height: size.height)
        path.addLine(to: CGPoint(x: size.width, y: zeroY))
        path.addLine(to: CGPoint(x: 0, y: zeroY))
        path.closeSubpath()
        return path
    }

    private func bandMarker(index: Int, size: CGSize) -> some View {
        let band = bands[index]
        let x = freqToX(band.frequency, width: size.width)
        let magnitude = calculateMagnitude(at: band.frequency)
        let db = linearToDb(magnitude)
        let y = dbToY(db, height: size.height)
        let isSelected = selectedBand == index

        return Circle()
            .fill(DSPTheme.eqBandColors[index % DSPTheme.eqBandColors.count])
            .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: DSPTheme.eqBandColors[index % DSPTheme.eqBandColors.count].opacity(isSelected ? 0.6 : 0), radius: 6)
            .position(x: x, y: y)
            .onTapGesture {
                onBandSelected?(index)
            }
    }

    private func calculateMagnitude(at frequency: Float) -> Float {
        var magnitude: Float = 1.0

        for band in bands {
            let bandMagnitude = calculateBandMagnitude(
                at: frequency,
                bandFreq: band.frequency,
                gainDb: band.gainDb,
                q: band.q,
                bandType: band.bandType
            )
            magnitude *= bandMagnitude
        }

        return magnitude
    }

    private func calculateBandMagnitude(at freq: Float, bandFreq: Float, gainDb: Float, q: Float, bandType: BandType) -> Float {
        // Magnitude response calculation using actual sample rate
        let omega = 2.0 * Float.pi * freq / sampleRate
        let cosOmega = cos(omega)

        let coeffs = BiquadCoefficients.calculate(
            type: bandType.toBiquadType(gainDb: gainDb),
            sampleRate: sampleRate,
            frequency: bandFreq,
            q: q
        )

        let cos2Omega = cos(2.0 * omega)
        let sinOmega = sin(omega)
        let sin2Omega = sin(2.0 * omega)

        let numReal = coeffs.b0 + coeffs.b1 * cosOmega + coeffs.b2 * cos2Omega
        let numImag = -coeffs.b1 * sinOmega - coeffs.b2 * sin2Omega
        let denReal = 1.0 + coeffs.a1 * cosOmega + coeffs.a2 * cos2Omega
        let denImag = -coeffs.a1 * sinOmega - coeffs.a2 * sin2Omega

        let numMag = sqrt(numReal * numReal + numImag * numImag)
        let denMag = sqrt(denReal * denReal + denImag * denImag)

        return numMag / max(denMag, 1e-10)
    }

    /// Draw spectrum analyzer overlay behind EQ curve
    private func spectrumOverlay(size: CGSize) -> Path {
        Path { path in
            guard !spectrumData.isEmpty else { return }

            let binCount = spectrumData.count

            // Start from bottom left
            path.move(to: CGPoint(x: 0, y: size.height))

            var startedLine = false
            for i in 0..<binCount {
                let freq = Float(i) * sampleRate / Float(fftSize)

                // Skip frequencies outside range
                guard freq >= minFreq, freq <= maxFreq else { continue }

                let x = freqToX(freq, width: size.width)
                // Map spectrum dB (-80 to 0) to EQ display range (-24 to +24)
                let spectrumDb = spectrumData[i]
                let mappedDb = (spectrumDb - spectrumMinDb) / (spectrumMaxDb - spectrumMinDb) * (maxDb - minDb) + minDb
                let y = dbToY(mappedDb, height: size.height)

                if !startedLine {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x, y: y))
                    startedLine = true
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Close path at bottom
            if startedLine {
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            }
        }
    }

    private func freqToX(_ freq: Float, width: CGFloat) -> CGFloat {
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logFreq = log10(max(freq, minFreq))
        let normalized = (logFreq - logMin) / (logMax - logMin)
        return CGFloat(normalized) * width
    }

    private func dbToY(_ db: Float, height: CGFloat) -> CGFloat {
        let normalized = (db - minDb) / (maxDb - minDb)
        return height * (1 - CGFloat(normalized))
    }
}

#Preview {
    EQCurveView(
        bands: [
            (80, 6, 0.707, .lowShelf),
            (250, -3, 1.0, .peak),
            (1000, 0, 1.0, .peak),
            (4000, 4, 1.0, .peak),
            (12000, 2, 0.707, .highShelf),
        ],
        selectedBand: 0
    )
    .padding()
    .background(DSPTheme.background)
}
