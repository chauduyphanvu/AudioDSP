import SwiftUI

/// EQ frequency response curve visualization with draggable bands, phase display, and spectrum overlay
struct EQCurveView: View {
    var bands: [(frequency: Float, gainDb: Float, q: Float, bandType: BandType)]
    var bandSoloStates: [Bool] = []
    var selectedBand: Int?
    var onBandSelected: ((Int) -> Void)?
    var onBandDragStarted: ((Int) -> Void)?  // Called when drag begins (for undo registration)
    var onBandDragged: ((Int, Float, Float) -> Void)?  // (bandIndex, newFreq, newGain)
    var height: CGFloat = 150
    var sampleRate: Float = 48000
    var spectrumData: [Float] = []
    var fftSize: Int = 2048
    var showPhaseResponse: Bool = false

    // Dragging state
    @State private var isDragging: Bool = false
    @State private var draggingBandIndex: Int?
    @State private var dragStartFreq: Float = 0
    @State private var dragStartGain: Float = 0
    @State private var currentDragFreq: Float = 0
    @State private var currentDragGain: Float = 0
    @GestureState private var dragOffset: CGSize = .zero

    // Cached coefficients for frequency response calculation
    // Prevents recalculating coefficients for every frequency point
    @State private var cachedCoefficients: [BiquadCoefficients] = []
    @State private var lastBandParams: [(Float, Float, Float, BandType)] = []

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

                // Phase response curve (optional)
                if showPhaseResponse {
                    phaseCurve(size: geometry.size)
                        .stroke(DSPTheme.textTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                // Frequency response curve
                responseCurve(size: geometry.size)
                    .stroke(DSPTheme.accent, lineWidth: 2)
                    .shadow(color: DSPTheme.accent.opacity(0.5), radius: 4)

                // Fill under curve
                responseCurveFill(size: geometry.size)
                    .fill(DSPTheme.accent.opacity(0.1))

                // Q/Bandwidth visual indicators for selected band
                if let selected = selectedBand, selected < bands.count {
                    bandwidthIndicator(index: selected, size: geometry.size)
                }

                // Band markers (draggable)
                ForEach(0..<bands.count, id: \.self) { index in
                    draggableBandMarker(index: index, size: geometry.size)
                }

                // Zero line
                Path { path in
                    let y = dbToY(0, height: geometry.size.height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
                .stroke(DSPTheme.textTertiary.opacity(0.5), lineWidth: 1)

                // Frequency/Gain readout while dragging
                if isDragging, let dragIndex = draggingBandIndex {
                    dragReadout(index: dragIndex, size: geometry.size)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value: value, size: geometry.size)
                    }
                    .onEnded { _ in
                        endDrag()
                    }
            )
        }
        .frame(height: height)
        .background(DSPTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DSPTheme.borderColor, lineWidth: 1)
        )
        .onAppear {
            updateCachedCoefficients()
        }
        .onChange(of: bands.map { "\($0.frequency)-\($0.gainDb)-\($0.q)-\($0.bandType.rawValue)" }) { _, _ in
            updateCachedCoefficients()
        }
    }

    // MARK: - Dragging Logic

    private func handleDrag(value: DragGesture.Value, size: CGSize) {
        let location = value.location

        if !isDragging {
            // Check if we're starting a drag on a band marker
            for (index, band) in bands.enumerated() {
                let markerX = freqToX(band.frequency, width: size.width)
                let magnitude = calculateMagnitude(at: band.frequency)
                let db = linearToDb(magnitude)
                let markerY = dbToY(db, height: size.height)

                let distance = sqrt(pow(location.x - markerX, 2) + pow(location.y - markerY, 2))
                if distance < 20 {  // Hit test radius
                    isDragging = true
                    draggingBandIndex = index
                    dragStartFreq = band.frequency
                    dragStartGain = band.gainDb
                    currentDragFreq = band.frequency
                    currentDragGain = band.gainDb
                    onBandSelected?(index)
                    // Register undo at drag start (not during drag) to avoid polluting undo stack
                    onBandDragStarted?(index)
                    return
                }
            }

            // If not on a marker, just select the nearest band
            let freq = xToFreq(location.x, width: size.width)
            var nearestIndex = 0
            var nearestDistance = Float.infinity
            for (index, band) in bands.enumerated() {
                let dist = abs(log(freq) - log(band.frequency))
                if dist < nearestDistance {
                    nearestDistance = dist
                    nearestIndex = index
                }
            }
            onBandSelected?(nearestIndex)
        } else if let dragIndex = draggingBandIndex {
            // Continue dragging - update frequency and gain
            let newFreq = xToFreq(location.x, width: size.width)
            let newGain = yToDb(location.y, height: size.height)

            currentDragFreq = min(max(newFreq, 20), 20000)
            currentDragGain = min(max(newGain, -24), 24)

            onBandDragged?(dragIndex, currentDragFreq, currentDragGain)
        }
    }

    private func endDrag() {
        isDragging = false
        draggingBandIndex = nil
    }

    // MARK: - Coordinate Conversions

    private func xToFreq(_ x: CGFloat, width: CGFloat) -> Float {
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let normalized = Float(x / width)
        let logFreq = logMin + normalized * (logMax - logMin)
        return powf(10, logFreq)
    }

    private func yToDb(_ y: CGFloat, height: CGFloat) -> Float {
        let normalized = 1 - Float(y / height)
        return minDb + normalized * (maxDb - minDb)
    }

    // MARK: - Draggable Band Marker

    private func draggableBandMarker(index: Int, size: CGSize) -> some View {
        let band = bands[index]
        let freq = isDragging && draggingBandIndex == index ? currentDragFreq : band.frequency
        let gain = isDragging && draggingBandIndex == index ? currentDragGain : band.gainDb

        let x = freqToX(freq, width: size.width)
        let magnitude = calculateMagnitudeForBand(at: freq, bandIndex: index)
        let db = linearToDb(magnitude)
        let y = dbToY(db, height: size.height)
        let isSelected = selectedBand == index
        let isSoloed = index < bandSoloStates.count ? bandSoloStates[index] : false
        let isDraggingThis = isDragging && draggingBandIndex == index

        return ZStack {
            // Glow effect when dragging
            if isDraggingThis {
                Circle()
                    .fill(DSPTheme.eqBandColors[index % DSPTheme.eqBandColors.count].opacity(0.3))
                    .frame(width: 24, height: 24)
            }

            // Main marker
            Circle()
                .fill(DSPTheme.eqBandColors[index % DSPTheme.eqBandColors.count])
                .frame(width: isSelected || isDraggingThis ? 14 : 10, height: isSelected || isDraggingThis ? 14 : 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 2 : 1)
                )
                .shadow(color: DSPTheme.eqBandColors[index % DSPTheme.eqBandColors.count].opacity(isSelected ? 0.6 : 0), radius: 6)

            // Solo indicator
            if isSoloed {
                Text("S")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .position(x: x, y: y)
    }

    // MARK: - Bandwidth Indicator

    private func bandwidthIndicator(index: Int, size: CGSize) -> some View {
        let band = bands[index]
        let centerFreq = band.frequency
        let q = band.q

        // Calculate bandwidth in octaves and frequency bounds
        let octaves = QBandwidthConverter.qToOctaves(q)
        let lowerFreq = centerFreq / powf(2, octaves / 2)
        let upperFreq = centerFreq * powf(2, octaves / 2)

        let leftX = freqToX(max(lowerFreq, minFreq), width: size.width)
        let rightX = freqToX(min(upperFreq, maxFreq), width: size.width)
        let centerX = freqToX(centerFreq, width: size.width)

        let magnitude = calculateMagnitude(at: centerFreq)
        let db = linearToDb(magnitude)
        let centerY = dbToY(db, height: size.height)

        let bandColor = DSPTheme.eqBandColors[index % DSPTheme.eqBandColors.count]

        return ZStack {
            // Bandwidth range indicator (horizontal line with end caps)
            Path { path in
                let y = centerY
                path.move(to: CGPoint(x: leftX, y: y))
                path.addLine(to: CGPoint(x: rightX, y: y))
            }
            .stroke(bandColor.opacity(0.4), lineWidth: 2)

            // Left cap
            Path { path in
                let y = centerY
                path.move(to: CGPoint(x: leftX, y: y - 6))
                path.addLine(to: CGPoint(x: leftX, y: y + 6))
            }
            .stroke(bandColor.opacity(0.4), lineWidth: 2)

            // Right cap
            Path { path in
                let y = centerY
                path.move(to: CGPoint(x: rightX, y: y - 6))
                path.addLine(to: CGPoint(x: rightX, y: y + 6))
            }
            .stroke(bandColor.opacity(0.4), lineWidth: 2)
        }
    }

    // MARK: - Drag Readout

    private func dragReadout(index: Int, size: CGSize) -> some View {
        let freq = currentDragFreq
        let gain = currentDragGain
        let x = freqToX(freq, width: size.width)
        let y = dbToY(gain, height: size.height)

        let freqString = freq >= 1000 ? String(format: "%.1f kHz", freq / 1000) : String(format: "%.0f Hz", freq)
        let gainString = String(format: "%+.1f dB", gain)

        // Position the readout above or below the marker depending on gain
        let readoutY = gain > 0 ? y - 30 : y + 30

        return VStack(spacing: 2) {
            Text(freqString)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            Text(gainString)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DSPTheme.cardBackground.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(DSPTheme.eqBandColors[index % DSPTheme.eqBandColors.count], lineWidth: 1)
        )
        .foregroundColor(DSPTheme.textPrimary)
        .position(x: min(max(x, 40), size.width - 40), y: min(max(readoutY, 20), size.height - 20))
    }

    // MARK: - Phase Response Curve

    private func phaseCurve(size: CGSize) -> Path {
        Path { path in
            let points = 200
            for i in 0..<points {
                let normalized = Float(i) / Float(points - 1)
                let freq = minFreq * powf(maxFreq / minFreq, normalized)
                let phase = calculatePhase(at: freq)

                let x = freqToX(freq, width: size.width)
                // Map phase (-π to π) to display range
                let normalizedPhase = (phase + Float.pi) / (2 * Float.pi)
                let y = size.height * (1 - CGFloat(normalizedPhase))

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func calculatePhase(at frequency: Float) -> Float {
        var totalPhase: Float = 0.0

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

            let numReal = coeffs.b0 + coeffs.b1 * cosOmega + coeffs.b2 * cos2Omega
            let numImag = -coeffs.b1 * sinOmega - coeffs.b2 * sin2Omega
            let denReal = 1.0 + coeffs.a1 * cosOmega + coeffs.a2 * cos2Omega
            let denImag = -coeffs.a1 * sinOmega - coeffs.a2 * sin2Omega

            let numPhase = atan2(numImag, numReal)
            let denPhase = atan2(denImag, denReal)

            totalPhase += numPhase - denPhase
        }

        // Wrap phase to -π to π
        while totalPhase > Float.pi { totalPhase -= 2 * Float.pi }
        while totalPhase < -Float.pi { totalPhase += 2 * Float.pi }

        return totalPhase
    }

    // MARK: - Existing Methods

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

    private func calculateMagnitude(at frequency: Float) -> Float {
        var magnitude: Float = 1.0

        // Use cached coefficients if available for better performance
        if cachedCoefficients.count == bands.count {
            for coeffs in cachedCoefficients {
                magnitude *= calculateBandMagnitudeWithCachedCoeffs(at: frequency, coeffs: coeffs)
            }
        } else {
            // Fallback to calculating coefficients on-the-fly
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
        }

        return magnitude
    }

    private func calculateMagnitudeForBand(at frequency: Float, bandIndex: Int) -> Float {
        var magnitude: Float = 1.0

        for (index, band) in bands.enumerated() {
            // Use current drag values for the dragging band
            let freq = (isDragging && draggingBandIndex == index) ? currentDragFreq : band.frequency
            let gain = (isDragging && draggingBandIndex == index) ? currentDragGain : band.gainDb

            let bandMagnitude = calculateBandMagnitude(
                at: frequency,
                bandFreq: freq,
                gainDb: gain,
                q: band.q,
                bandType: band.bandType
            )
            magnitude *= bandMagnitude
        }

        return magnitude
    }

    /// Update cached coefficients if band parameters have changed
    private func updateCachedCoefficients() {
        let currentParams = bands.map { ($0.frequency, $0.gainDb, $0.q, $0.bandType) }

        // Check if parameters have changed
        let needsUpdate = lastBandParams.count != currentParams.count ||
            zip(lastBandParams, currentParams).contains { old, new in
                old.0 != new.0 || old.1 != new.1 || old.2 != new.2 || old.3 != new.3
            }

        if needsUpdate {
            cachedCoefficients = bands.map { band in
                BiquadCoefficients.calculate(
                    type: band.bandType.toBiquadType(gainDb: band.gainDb),
                    sampleRate: sampleRate,
                    frequency: band.frequency,
                    q: band.q
                )
            }
            lastBandParams = currentParams
        }
    }

    /// Calculate magnitude using cached coefficients for efficiency
    private func calculateBandMagnitudeWithCachedCoeffs(at freq: Float, coeffs: BiquadCoefficients) -> Float {
        let omega = 2.0 * Float.pi * freq / sampleRate
        let cosOmega = cos(omega)
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

    private func calculateBandMagnitude(at freq: Float, bandFreq: Float, gainDb: Float, q: Float, bandType: BandType) -> Float {
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

    private func spectrumOverlay(size: CGSize) -> Path {
        Path { path in
            guard !spectrumData.isEmpty else { return }

            let binCount = spectrumData.count

            path.move(to: CGPoint(x: 0, y: size.height))

            var startedLine = false
            for i in 0..<binCount {
                let freq = Float(i) * sampleRate / Float(fftSize)

                guard freq >= minFreq, freq <= maxFreq else { continue }

                let x = freqToX(freq, width: size.width)
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
        selectedBand: 0,
        showPhaseResponse: true
    )
    .padding()
    .background(DSPTheme.background)
}
