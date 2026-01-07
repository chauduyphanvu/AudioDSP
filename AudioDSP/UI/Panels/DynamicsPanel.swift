import SwiftUI

/// Combined Compressor and Limiter panel
struct DynamicsPanel: View {
    @ObservedObject var state: DSPState

    var body: some View {
        VStack(spacing: 16) {
            // Compressor section
            VStack(spacing: 12) {
                EffectHeader(
                    name: "Compressor",
                    isEnabled: !state.compressorBypassed,
                    onToggle: { state.toggleCompressorBypass() }
                )

                HStack(spacing: 24) {
                    // Parameters
                    VStack(spacing: 16) {
                        HStack(spacing: 20) {
                            Knob(
                                value: $state.compressorThreshold,
                                range: -60...0,
                                label: "Threshold",
                                unit: .decibels,
                                defaultValue: -12
                            )

                            Knob(
                                value: $state.compressorRatio,
                                range: 1...20,
                                label: "Ratio",
                                unit: .ratio,
                                defaultValue: 4
                            )

                            Knob(
                                value: $state.compressorMakeup,
                                range: 0...24,
                                label: "Makeup",
                                unit: .decibels,
                                defaultValue: 0
                            )
                        }

                        HStack(spacing: 20) {
                            Knob(
                                value: $state.compressorAttack,
                                range: 0.1...100,
                                label: "Attack",
                                unit: .milliseconds,
                                size: 48,
                                defaultValue: 10
                            )

                            Knob(
                                value: $state.compressorRelease,
                                range: 10...1000,
                                label: "Release",
                                unit: .milliseconds,
                                size: 48,
                                defaultValue: 100
                            )
                        }
                    }

                    // Gain reduction meter
                    VStack(spacing: 4) {
                        Text("GR")
                            .font(DSPTypography.caption)
                            .foregroundColor(DSPTheme.textSecondary)

                        GainReductionMeterVertical(
                            gainReductionDb: state.compressorGainReduction,
                            height: 100
                        )
                    }
                }
            }
            .padding(12)
            .cardStyle()

            // Limiter section
            VStack(spacing: 12) {
                EffectHeader(
                    name: "Limiter",
                    isEnabled: !state.limiterBypassed,
                    onToggle: { state.toggleLimiterBypass() }
                )

                HStack(spacing: 24) {
                    HStack(spacing: 20) {
                        Knob(
                            value: $state.limiterCeiling,
                            range: -12...0,
                            label: "Ceiling",
                            unit: .decibels,
                            defaultValue: -0.3
                        )

                        Knob(
                            value: $state.limiterRelease,
                            range: 10...500,
                            label: "Release",
                            unit: .milliseconds,
                            defaultValue: 50
                        )
                    }

                    // Gain reduction meter
                    VStack(spacing: 4) {
                        Text("GR")
                            .font(DSPTypography.caption)
                            .foregroundColor(DSPTheme.textSecondary)

                        GainReductionMeterVertical(
                            gainReductionDb: state.limiterGainReduction,
                            height: 60
                        )
                    }
                }
            }
            .padding(12)
            .cardStyle()
        }
        .padding(16)
        .panelStyle()
    }
}

/// Vertical gain reduction meter
struct GainReductionMeterVertical: View {
    var gainReductionDb: Float  // Negative values
    var height: CGFloat = 80

    private var normalizedLevel: CGFloat {
        // Map -24dB to 0dB -> 1 to 0
        let clamped = min(max(gainReductionDb, -24), 0)
        return CGFloat(-clamped / 24)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.4))

                    // Reduction bar (grows from top)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [DSPTheme.meterYellow, DSPTheme.meterOrange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: normalizedLevel * geometry.size.height)
                }
            }
            .frame(width: 12, height: height)

            Text(String(format: "%.1f", gainReductionDb))
                .font(DSPTypography.mono)
                .foregroundColor(DSPTheme.textSecondary)
        }
    }
}

#Preview {
    DynamicsPanel(state: DSPState())
        .frame(width: 400)
        .padding()
        .background(DSPTheme.background)
}
