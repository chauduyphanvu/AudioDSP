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
                                defaultValue: -12,
                                tooltip: "Threshold: The level at which compression begins. Signals above this level get reduced. Lower values = more compression applied. Start around -12dB and adjust based on your audio's dynamics."
                            )

                            Knob(
                                value: $state.compressorRatio,
                                range: 1...20,
                                label: "Ratio",
                                unit: .ratio,
                                defaultValue: 4,
                                tooltip: "Ratio: How much the signal is reduced once it exceeds the threshold. 4:1 means for every 4dB over threshold, only 1dB comes through. Higher ratios = more aggressive compression. 2-4:1 for gentle control, 8:1+ for heavy limiting."
                            )

                            Knob(
                                value: $state.compressorMakeup,
                                range: 0...24,
                                label: "Makeup",
                                unit: .decibels,
                                defaultValue: 0,
                                tooltip: "Makeup Gain: Boosts the output to compensate for volume lost during compression. If your compressed signal sounds quieter, increase this to match the original loudness while keeping the dynamic control."
                            )
                        }

                        HStack(spacing: 20) {
                            Knob(
                                value: $state.compressorAttack,
                                range: 0.1...100,
                                label: "Attack",
                                unit: .milliseconds,
                                size: 48,
                                defaultValue: 10,
                                tooltip: "Attack: How quickly compression kicks in after the signal exceeds the threshold. Fast attack (1-10ms) catches transients and tames peaks. Slow attack (20-100ms) lets transients through, preserving punch and snap."
                            )

                            Knob(
                                value: $state.compressorRelease,
                                range: 10...1000,
                                label: "Release",
                                unit: .milliseconds,
                                size: 48,
                                defaultValue: 100,
                                tooltip: "Release: How quickly compression stops after the signal drops below the threshold. Fast release (50-100ms) sounds more transparent but can cause pumping. Slow release (200-500ms) sounds smoother but can reduce dynamics."
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
                    .help("Gain Reduction: Shows how much the compressor is reducing the signal in real-time. More reduction (longer bar) means more compression is being applied. Watch this to ensure you're not over-compressing.")
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
                            defaultValue: -0.3,
                            tooltip: "Ceiling: The absolute maximum output level. No audio will exceed this. Set to -0.3dB or lower to prevent digital clipping. Use -1dB or lower if you'll be encoding to MP3/AAC later."
                        )

                        Knob(
                            value: $state.limiterRelease,
                            range: 10...500,
                            label: "Release",
                            unit: .milliseconds,
                            defaultValue: 50,
                            tooltip: "Release: How fast the limiter recovers after catching a peak. Faster release (10-50ms) is more transparent but may cause distortion on sustained loud passages. Slower release (100-300ms) is smoother but can pump on rhythmic material."
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
                    .help("Gain Reduction: Shows how much the limiter is catching peaks. Occasional flickers are normal. Constant heavy reduction means your input is too hot — reduce the output gain or compressor makeup gain.")
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
