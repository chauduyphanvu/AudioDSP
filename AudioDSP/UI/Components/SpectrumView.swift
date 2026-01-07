import SwiftUI

/// Real-time spectrum analyzer visualization
struct SpectrumView: View {
    var magnitudes: [Float]  // dB values, typically -80 to 0
    var sampleRate: Float = 48000
    var fftSize: Int = 2048
    var height: CGFloat = 120

    private let minDb: Float = -80
    private let maxDb: Float = 0
    private let minFreq: Float = 20
    private let maxFreq: Float = 20000

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid
                spectrumGrid(size: geometry.size)

                // Spectrum curve
                spectrumPath(size: geometry.size)
                    .fill(DSPTheme.spectrumGradient)

                spectrumPath(size: geometry.size)
                    .stroke(DSPTheme.spectrumLine, lineWidth: 1.5)
                    .shadow(color: DSPTheme.spectrumLine.opacity(0.5), radius: 4)

                // Frequency labels
                frequencyLabels(size: geometry.size)
            }
        }
        .frame(height: height)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DSPTheme.borderColor, lineWidth: 0.5)
        )
    }

    private func spectrumPath(size: CGSize) -> Path {
        Path { path in
            guard !magnitudes.isEmpty else { return }

            let binCount = magnitudes.count

            // Start from bottom left
            path.move(to: CGPoint(x: 0, y: size.height))

            for i in 0..<binCount {
                let freq = Float(i) * sampleRate / Float(fftSize)

                // Skip frequencies outside range
                guard freq >= minFreq, freq <= maxFreq else { continue }

                let x = freqToX(freq, width: size.width)
                let y = dbToY(magnitudes[i], height: size.height)

                if i == 0 || freq == minFreq {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Close path at bottom
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }

    private func spectrumGrid(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            // Horizontal dB lines
            let dbLevels: [Float] = [0, -12, -24, -48, -72]
            for db in dbLevels {
                let y = dbToY(db, height: size.height)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(DSPTheme.spectrumGrid), lineWidth: 0.5)
            }

            // Vertical frequency lines (logarithmic)
            let freqLines: [Float] = [50, 100, 200, 500, 1000, 2000, 5000, 10000]
            for freq in freqLines {
                let x = freqToX(freq, width: size.width)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(DSPTheme.spectrumGrid), lineWidth: 0.5)
            }
        }
    }

    private func frequencyLabels(size: CGSize) -> some View {
        ZStack {
            // Frequency labels at bottom
            ForEach([100, 1000, 10000], id: \.self) { freq in
                let x = freqToX(Float(freq), width: size.width)
                Text(freq >= 1000 ? "\(freq/1000)k" : "\(freq)")
                    .font(DSPTypography.mono)
                    .foregroundColor(DSPTheme.textTertiary)
                    .position(x: x, y: size.height - 8)
            }

            // dB labels on left
            ForEach([0, -24, -48], id: \.self) { db in
                let y = dbToY(Float(db), height: size.height)
                Text("\(db)")
                    .font(DSPTypography.mono)
                    .foregroundColor(DSPTheme.textTertiary)
                    .position(x: 16, y: y)
            }
        }
    }

    private func freqToX(_ freq: Float, width: CGFloat) -> CGFloat {
        // Logarithmic scale
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
    // Generate sample spectrum data
    let sampleData: [Float] = (0..<1024).map { i in
        let freq = Float(i) * 48000 / 2048
        // Simulate a typical audio spectrum with some peaks
        var db: Float = -60
        if freq > 50, freq < 200 { db = -30 }  // Bass bump
        if freq > 1000, freq < 4000 { db = -40 }  // Presence
        db += Float.random(in: -5...5)  // Some variation
        return db
    }

    SpectrumView(magnitudes: sampleData)
        .padding()
        .background(DSPTheme.background)
}
