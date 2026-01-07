import SwiftUI

/// Time-based and enhancement effects panel
struct EffectsPanel: View {
    @ObservedObject var state: DSPState

    var body: some View {
        VStack(spacing: 16) {
            // Reverb
            EffectCard(
                name: "Reverb",
                isEnabled: !state.reverbBypassed,
                onToggle: { state.toggleReverbBypass() }
            ) {
                HStack(spacing: 20) {
                    Knob(
                        value: $state.reverbRoomSize,
                        range: 0...1,
                        label: "Room",
                        unit: .percent
                    )

                    Knob(
                        value: $state.reverbDamping,
                        range: 0...1,
                        label: "Damping",
                        unit: .percent
                    )

                    Knob(
                        value: $state.reverbWidth,
                        range: 0...1,
                        label: "Width",
                        unit: .percent
                    )

                    Knob(
                        value: $state.reverbMix,
                        range: 0...1,
                        label: "Mix",
                        unit: .percent
                    )
                }
            }

            // Delay
            EffectCard(
                name: "Delay",
                isEnabled: !state.delayBypassed,
                onToggle: { state.toggleDelayBypass() }
            ) {
                HStack(spacing: 20) {
                    Knob(
                        value: $state.delayTime,
                        range: 1...2000,
                        label: "Time",
                        unit: .milliseconds
                    )

                    Knob(
                        value: $state.delayFeedback,
                        range: 0...0.95,
                        label: "Feedback",
                        unit: .percent
                    )

                    Knob(
                        value: $state.delayMix,
                        range: 0...1,
                        label: "Mix",
                        unit: .percent
                    )
                }
            }

            // Stereo Widener
            EffectCard(
                name: "Stereo Widener",
                isEnabled: !state.stereoWidenerBypassed,
                onToggle: { state.toggleStereoWidenerBypass() }
            ) {
                Knob(
                    value: $state.stereoWidth,
                    range: 0...2,
                    label: "Width",
                    unit: .generic
                )
            }

            // Enhancement effects row
            HStack(spacing: 16) {
                // Bass Enhancer
                EffectCard(
                    name: "Bass Enhancer",
                    isEnabled: !state.bassEnhancerBypassed,
                    onToggle: { state.toggleBassEnhancerBypass() }
                ) {
                    VStack(spacing: 12) {
                        Knob(
                            value: $state.bassAmount,
                            range: 0...100,
                            label: "Amount",
                            unit: .percent,
                            size: 48
                        )

                        HStack(spacing: 12) {
                            CompactKnob(
                                value: $state.bassLowFreq,
                                range: 60...150,
                                label: "Freq",
                                unit: .hertz
                            )

                            CompactKnob(
                                value: $state.bassHarmonics,
                                range: 0...100,
                                label: "Harmonics",
                                unit: .percent
                            )
                        }
                    }
                }

                // Vocal Clarity
                EffectCard(
                    name: "Vocal Clarity",
                    isEnabled: !state.vocalClarityBypassed,
                    onToggle: { state.toggleVocalClarityBypass() }
                ) {
                    HStack(spacing: 16) {
                        Knob(
                            value: $state.vocalClarity,
                            range: 0...100,
                            label: "Clarity",
                            unit: .percent
                        )

                        Knob(
                            value: $state.vocalAir,
                            range: 0...100,
                            label: "Air",
                            unit: .percent
                        )
                    }
                }
            }
        }
        .padding(16)
        .panelStyle()
    }
}

/// Reusable effect card container
struct EffectCard<Content: View>: View {
    let name: String
    var isEnabled: Bool
    var onToggle: () -> Void
    @ViewBuilder var content: Content

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 12) {
            EffectHeader(
                name: name,
                isEnabled: isEnabled,
                onToggle: onToggle
            )

            content
                .opacity(isEnabled ? 1.0 : 0.4)
        }
        .padding(14)
        .background(DSPTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isHovered ? DSPTheme.borderColorLight.opacity(0.6) : DSPTheme.borderColor.opacity(0.5),
                    lineWidth: 0.5
                )
        )
        .shadow(color: isHovered ? DSPTheme.shadowColor.opacity(0.2) : Color.clear, radius: 8, y: 4)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    EffectsPanel(state: DSPState())
        .frame(width: 500)
        .padding()
        .background(DSPTheme.background)
}
