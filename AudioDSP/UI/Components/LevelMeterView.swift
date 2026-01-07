import SwiftUI

/// Segmented peak level meter
struct LevelMeterView: View {
    var leftLevel: Float   // Linear 0-1
    var rightLevel: Float  // Linear 0-1
    var label: String = ""
    var height: CGFloat = 120
    var showPeakHold: Bool = true

    @State private var peakLeft: Float = 0
    @State private var peakRight: Float = 0
    @State private var peakHoldTimer: Timer?

    private let segmentCount = 20
    private let segmentSpacing: CGFloat = 1

    var body: some View {
        VStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(DSPTypography.caption)
                    .foregroundColor(DSPTheme.textSecondary)
            }

            HStack(spacing: 3) {
                // Left channel
                MeterChannel(
                    level: leftLevel,
                    peak: peakLeft,
                    height: height,
                    segmentCount: segmentCount
                )

                // Right channel
                MeterChannel(
                    level: rightLevel,
                    peak: peakRight,
                    height: height,
                    segmentCount: segmentCount
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(DSPTheme.borderColor, lineWidth: 0.5)
            )

            // dB scale labels
            HStack(spacing: 0) {
                Text("0")
                Spacer()
                Text("-12")
                Spacer()
                Text("-24")
                Spacer()
                Text("-48")
            }
            .font(DSPTypography.mono)
            .foregroundColor(DSPTheme.textTertiary)
            .frame(width: 50)
        }
        .onChange(of: leftLevel) { _, newValue in
            updatePeak(channel: .left, level: newValue)
        }
        .onChange(of: rightLevel) { _, newValue in
            updatePeak(channel: .right, level: newValue)
        }
    }

    private enum Channel { case left, right }

    private func updatePeak(channel: Channel, level: Float) {
        switch channel {
        case .left:
            if level > peakLeft {
                peakLeft = level
                schedulePeakDecay()
            }
        case .right:
            if level > peakRight {
                peakRight = level
                schedulePeakDecay()
            }
        }
    }

    private func schedulePeakDecay() {
        peakHoldTimer?.invalidate()
        peakHoldTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.5)) {
                peakLeft = leftLevel
                peakRight = rightLevel
            }
        }
    }
}

/// Single channel meter
struct MeterChannel: View {
    var level: Float
    var peak: Float
    var height: CGFloat
    var segmentCount: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Segments
                VStack(spacing: 1) {
                    ForEach(0..<segmentCount, id: \.self) { index in
                        let segmentDb = dbForSegment(index)
                        let levelDb = linearToDb(max(level, 1e-10))
                        let isLit = levelDb >= segmentDb

                        Rectangle()
                            .fill(segmentColor(index: index, isLit: isLit))
                            .frame(height: segmentHeight(geometry.size.height))
                    }
                }

                // Peak indicator
                let peakDb = linearToDb(max(peak, 1e-10))
                let peakSegment = segmentForDb(peakDb)
                if peakSegment >= 0, peakSegment < segmentCount {
                    Rectangle()
                        .fill(peakColor(segment: peakSegment))
                        .frame(height: 2)
                        .offset(y: -peakOffset(segment: peakSegment, totalHeight: geometry.size.height))
                }
            }
        }
        .frame(width: 8, height: height)
    }

    private func dbForSegment(_ index: Int) -> Float {
        // Top segment = 0dB, bottom = -60dB
        let reversedIndex = segmentCount - 1 - index
        return Float(reversedIndex) * (-60.0 / Float(segmentCount - 1))
    }

    private func segmentForDb(_ db: Float) -> Int {
        let normalized = (db + 60) / 60  // 0 to 1
        return segmentCount - 1 - Int(normalized * Float(segmentCount - 1))
    }

    private func segmentHeight(_ totalHeight: CGFloat) -> CGFloat {
        (totalHeight - CGFloat(segmentCount - 1)) / CGFloat(segmentCount)
    }

    private func peakOffset(segment: Int, totalHeight: CGFloat) -> CGFloat {
        let segHeight = segmentHeight(totalHeight)
        return CGFloat(segmentCount - 1 - segment) * (segHeight + 1) + segHeight / 2
    }

    private func segmentColor(index: Int, isLit: Bool) -> Color {
        if !isLit {
            return Color.gray.opacity(0.15)
        }

        // Red zone: top 2 segments (0 to -6dB)
        if index < 2 {
            return DSPTheme.meterRed
        }
        // Orange zone: next 2 segments (-6 to -12dB)
        if index < 4 {
            return DSPTheme.meterOrange
        }
        // Yellow zone: next 4 segments (-12 to -24dB)
        if index < 8 {
            return DSPTheme.meterYellow
        }
        // Green zone: rest
        return DSPTheme.meterGreen
    }

    private func peakColor(segment: Int) -> Color {
        if segment < 2 {
            return DSPTheme.meterRed
        } else if segment < 4 {
            return DSPTheme.meterOrange
        } else if segment < 8 {
            return DSPTheme.meterYellow
        }
        return DSPTheme.meterGreen
    }
}

/// Horizontal gain reduction meter
struct GainReductionMeter: View {
    var gainReductionDb: Float  // Negative values
    var width: CGFloat = 80

    private var normalizedLevel: CGFloat {
        // Map -24dB to 0dB -> 1 to 0
        let clamped = min(max(gainReductionDb, -24), 0)
        return CGFloat(-clamped / 24)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("GR")
                .font(DSPTypography.mono)
                .foregroundColor(DSPTheme.textTertiary)

            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.4))

                    // Reduction bar (grows from right to left)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DSPTheme.meterOrange)
                        .frame(width: normalizedLevel * geometry.size.width)
                }
            }
            .frame(width: width, height: 6)

            Text(String(format: "%.1f dB", gainReductionDb))
                .font(DSPTypography.mono)
                .foregroundColor(DSPTheme.textSecondary)
        }
    }
}

#Preview {
    HStack(spacing: 32) {
        LevelMeterView(
            leftLevel: 0.6,
            rightLevel: 0.5,
            label: "Input"
        )

        LevelMeterView(
            leftLevel: 0.8,
            rightLevel: 0.75,
            label: "Output"
        )

        GainReductionMeter(gainReductionDb: -6)
    }
    .padding(40)
    .background(DSPTheme.background)
}
