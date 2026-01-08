import SwiftUI

/// Display mode for spectrum analyzer
enum SpectrumDisplayMode: String, CaseIterable {
    case curve = "Curve"
    case bars = "Bars"
}

/// Real-time spectrum analyzer visualization with peak hold and multiple display modes
struct SpectrumView: View {
    var magnitudes: [Float]  // dB values, typically -80 to 0
    var sampleRate: Float = 48000
    var fftSize: Int = 2048
    var height: CGFloat = 120
    var displayMode: SpectrumDisplayMode = .curve
    var showPeakHold: Bool = true
    var peakDecayRate: Float = 40  // dB per second (10 = slow, 100 = fast)

    @State private var peakHoldValues: [Float] = []
    @State private var peakDecayTimers: [Date] = []

    private let minDb: Float = -80
    private let maxDb: Float = 0
    private let minFreq: Float = 20
    private let maxFreq: Float = 20000
    private let peakHoldTime: TimeInterval = 1.5

    // Frequency bands for coloring
    private let bassRange: ClosedRange<Float> = 20...250
    private let midRange: ClosedRange<Float> = 250...4000
    private let highRange: ClosedRange<Float> = 4000...20000

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.5), Color.black.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Grid
                spectrumGrid(size: geometry.size)

                // Main spectrum visualization
                switch displayMode {
                case .curve:
                    curveVisualization(size: geometry.size)
                case .bars:
                    barVisualization(size: geometry.size)
                }

                // Peak hold indicators
                if showPeakHold && !peakHoldValues.isEmpty {
                    peakHoldLine(size: geometry.size)
                }

                // Frequency labels
                frequencyLabels(size: geometry.size)

                // dB labels
                dbLabels(size: geometry.size)

                // Frequency band indicators at top
                frequencyBandIndicators(size: geometry.size)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DSPTheme.borderColor, lineWidth: 0.5)
        )
        .onChange(of: magnitudes) { _, newMagnitudes in
            updatePeakHold(newMagnitudes)
        }
        .onAppear {
            if peakHoldValues.isEmpty && !magnitudes.isEmpty {
                peakHoldValues = magnitudes
                peakDecayTimers = Array(repeating: Date(), count: magnitudes.count)
            }
        }
    }

    // MARK: - Peak Hold Logic

    private func updatePeakHold(_ newMagnitudes: [Float]) {
        guard !newMagnitudes.isEmpty else { return }

        if peakHoldValues.count != newMagnitudes.count {
            peakHoldValues = newMagnitudes
            peakDecayTimers = Array(repeating: Date(), count: newMagnitudes.count)
            return
        }

        let now = Date()
        for i in 0..<newMagnitudes.count {
            if newMagnitudes[i] > peakHoldValues[i] {
                peakHoldValues[i] = newMagnitudes[i]
                peakDecayTimers[i] = now
            } else {
                let elapsed = now.timeIntervalSince(peakDecayTimers[i])
                if elapsed > peakHoldTime {
                    let decay = peakDecayRate * Float(elapsed - peakHoldTime)
                    peakHoldValues[i] = max(newMagnitudes[i], peakHoldValues[i] - decay)
                }
            }
        }
    }

    // MARK: - Curve Visualization

    private func curveVisualization(size: CGSize) -> some View {
        ZStack {
            // Gradient fill under curve
            spectrumPath(size: size, smooth: true)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: DSPTheme.meterGreen.opacity(0.4), location: 0),
                            .init(color: DSPTheme.meterYellow.opacity(0.3), location: 0.5),
                            .init(color: DSPTheme.meterRed.opacity(0.2), location: 0.85),
                            .init(color: DSPTheme.meterRed.opacity(0.4), location: 1.0),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

            // Outer glow
            spectrumStrokePath(size: size, smooth: true)
                .stroke(DSPTheme.spectrumLine.opacity(0.3), lineWidth: 4)
                .blur(radius: 3)

            // Main stroke
            spectrumStrokePath(size: size, smooth: true)
                .stroke(
                    LinearGradient(
                        colors: [DSPTheme.meterGreen, DSPTheme.meterYellow, DSPTheme.meterOrange, DSPTheme.meterRed],
                        startPoint: .bottom,
                        endPoint: .top
                    ),
                    lineWidth: 2
                )
        }
    }

    // MARK: - Bar Visualization

    private func barVisualization(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let barCount = 64
            let barWidth = size.width / CGFloat(barCount) - 1
            let barSpacing: CGFloat = 1

            for i in 0..<barCount {
                let normalizedPos = Float(i) / Float(barCount - 1)
                let freq = minFreq * powf(maxFreq / minFreq, normalizedPos)
                let binIndex = Int(freq * Float(fftSize) / sampleRate)

                guard binIndex >= 0 && binIndex < magnitudes.count else { continue }

                // Average a few bins for smoother bars
                var avgDb: Float = magnitudes[binIndex]
                var count = 1
                for offset in [-2, -1, 1, 2] {
                    let idx = binIndex + offset
                    if idx >= 0 && idx < magnitudes.count {
                        avgDb += magnitudes[idx]
                        count += 1
                    }
                }
                avgDb /= Float(count)

                let normalizedDb = (avgDb - minDb) / (maxDb - minDb)
                let barHeight = max(2, CGFloat(normalizedDb) * size.height)

                let x = CGFloat(i) * (barWidth + barSpacing)
                let y = size.height - barHeight

                // Color based on frequency range
                let barColor = colorForFrequency(freq)

                // Draw bar with gradient
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let gradient = Gradient(colors: [barColor.opacity(0.8), barColor])
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: y + barHeight), endPoint: CGPoint(x: 0, y: y))
                )

                // Peak indicator on top of bar
                if showPeakHold && binIndex < peakHoldValues.count {
                    let peakDb = (peakHoldValues[binIndex] - minDb) / (maxDb - minDb)
                    let peakY = size.height - max(2, CGFloat(peakDb) * size.height)
                    let peakRect = CGRect(x: x, y: peakY, width: barWidth, height: 2)
                    context.fill(Path(peakRect), with: .color(barColor))
                }
            }
        }
    }

    // MARK: - Peak Hold Line

    private func peakHoldLine(size: CGSize) -> some View {
        Path { path in
            guard !peakHoldValues.isEmpty else { return }

            var started = false
            for i in 0..<peakHoldValues.count {
                let freq = Float(i) * sampleRate / Float(fftSize)
                guard freq >= minFreq, freq <= maxFreq else { continue }

                let x = freqToX(freq, width: size.width)
                let y = dbToY(peakHoldValues[i], height: size.height)

                if !started {
                    path.move(to: CGPoint(x: x, y: y))
                    started = true
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(Color.white.opacity(0.6), lineWidth: 1)
    }

    // MARK: - Paths

    private func spectrumPath(size: CGSize, smooth: Bool) -> Path {
        Path { path in
            guard !magnitudes.isEmpty else { return }

            path.move(to: CGPoint(x: 0, y: size.height))

            var points: [CGPoint] = []

            for i in 0..<magnitudes.count {
                let freq = Float(i) * sampleRate / Float(fftSize)
                guard freq >= minFreq, freq <= maxFreq else { continue }

                let x = freqToX(freq, width: size.width)
                let y = dbToY(magnitudes[i], height: size.height)
                points.append(CGPoint(x: x, y: y))
            }

            if smooth && points.count > 2 {
                path.addLine(to: CGPoint(x: points[0].x, y: size.height))
                path.addLine(to: points[0])

                for i in 1..<points.count {
                    let p0 = points[max(0, i - 1)]
                    let p1 = points[i]

                    // Catmull-Rom to Bezier conversion for smooth curves
                    let cp1 = CGPoint(x: p0.x + (p1.x - p0.x) / 3, y: p0.y + (p1.y - p0.y) / 3)
                    let cp2 = CGPoint(x: p1.x - (p1.x - p0.x) / 3, y: p1.y - (p1.y - p0.y) / 3)

                    path.addCurve(to: p1, control1: cp1, control2: cp2)
                }
            } else {
                for point in points {
                    path.addLine(to: point)
                }
            }

            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }

    private func spectrumStrokePath(size: CGSize, smooth: Bool) -> Path {
        Path { path in
            guard !magnitudes.isEmpty else { return }

            var points: [CGPoint] = []

            for i in 0..<magnitudes.count {
                let freq = Float(i) * sampleRate / Float(fftSize)
                guard freq >= minFreq, freq <= maxFreq else { continue }

                let x = freqToX(freq, width: size.width)
                let y = dbToY(magnitudes[i], height: size.height)
                points.append(CGPoint(x: x, y: y))
            }

            guard !points.isEmpty else { return }

            if smooth && points.count > 2 {
                path.move(to: points[0])

                for i in 1..<points.count {
                    let p0 = points[max(0, i - 1)]
                    let p1 = points[i]

                    let cp1 = CGPoint(x: p0.x + (p1.x - p0.x) / 3, y: p0.y + (p1.y - p0.y) / 3)
                    let cp2 = CGPoint(x: p1.x - (p1.x - p0.x) / 3, y: p1.y - (p1.y - p0.y) / 3)

                    path.addCurve(to: p1, control1: cp1, control2: cp2)
                }
            } else {
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
        }
    }

    // MARK: - Grid

    private func spectrumGrid(size: CGSize) -> some View {
        Canvas { context, _ in
            // Horizontal dB lines
            let dbLevels: [Float] = [-6, -12, -24, -48]
            for db in dbLevels {
                let y = dbToY(db, height: size.height)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(DSPTheme.spectrumGrid.opacity(0.4)), lineWidth: 0.5)
            }

            // Vertical frequency lines
            let freqLines: [Float] = [50, 100, 200, 500, 1000, 2000, 5000, 10000]
            for freq in freqLines {
                let x = freqToX(freq, width: size.width)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(DSPTheme.spectrumGrid.opacity(0.3)), lineWidth: 0.5)
            }
        }
    }

    // MARK: - Labels

    private func frequencyLabels(size: CGSize) -> some View {
        ZStack {
            ForEach([30, 100, 300, 1000, 3000, 10000], id: \.self) { freq in
                let x = freqToX(Float(freq), width: size.width)
                Text(freq >= 1000 ? "\(freq/1000)k" : "\(freq)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(DSPTheme.textTertiary.opacity(0.7))
                    .position(x: x, y: size.height - 10)
            }
        }
    }

    private func dbLabels(size: CGSize) -> some View {
        ZStack {
            ForEach([-12, -24, -48], id: \.self) { db in
                let y = dbToY(Float(db), height: size.height)
                Text("\(db)")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(DSPTheme.textTertiary.opacity(0.6))
                    .position(x: 14, y: y)
            }
        }
    }

    private func frequencyBandIndicators(size: CGSize) -> some View {
        HStack(spacing: 0) {
            // Bass
            Rectangle()
                .fill(LinearGradient(
                    colors: [DSPTheme.meterGreen.opacity(0.3), DSPTheme.meterGreen.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: freqToX(250, width: size.width))

            // Mids
            Rectangle()
                .fill(LinearGradient(
                    colors: [DSPTheme.meterYellow.opacity(0.1), DSPTheme.meterYellow.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: freqToX(4000, width: size.width) - freqToX(250, width: size.width))

            // Highs
            Rectangle()
                .fill(LinearGradient(
                    colors: [DSPTheme.meterOrange.opacity(0.1), DSPTheme.meterOrange.opacity(0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
        }
        .frame(height: 3)
        .position(x: size.width / 2, y: 1.5)
    }

    // MARK: - Helpers

    private func colorForFrequency(_ freq: Float) -> Color {
        if bassRange.contains(freq) {
            return DSPTheme.meterGreen
        } else if midRange.contains(freq) {
            return DSPTheme.meterYellow
        } else {
            return DSPTheme.meterOrange
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
        let clamped = min(max(db, minDb), maxDb)
        let normalized = (clamped - minDb) / (maxDb - minDb)
        return height * (1 - CGFloat(normalized))
    }
}

#Preview {
    VStack(spacing: 20) {
        // Generate sample spectrum data
        let sampleData: [Float] = (0..<1024).map { i in
            let freq = Float(i) * 48000 / 2048
            var db: Float = -60
            if freq > 50, freq < 200 { db = -25 }
            if freq > 800, freq < 3000 { db = -35 }
            if freq > 5000, freq < 8000 { db = -45 }
            db += Float.random(in: -5...5)
            return db
        }

        Text("Curve Mode")
            .foregroundColor(.white)
        SpectrumView(magnitudes: sampleData, displayMode: .curve)

        Text("Bar Mode")
            .foregroundColor(.white)
        SpectrumView(magnitudes: sampleData, displayMode: .bars)
    }
    .padding()
    .background(DSPTheme.background)
}
