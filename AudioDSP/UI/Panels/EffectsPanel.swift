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
                        unit: .percent,
                        defaultValue: 0.5,
                        tooltip: "Room Size: Controls the perceived size of the virtual space. Small values create tight, intimate spaces like a closet or bathroom. Large values simulate concert halls and cathedrals. Also affects the decay time."
                    )

                    Knob(
                        value: $state.reverbDamping,
                        range: 0...1,
                        label: "Damping",
                        unit: .percent,
                        defaultValue: 0.5,
                        tooltip: "Damping: Controls how quickly high frequencies decay in the reverb tail. High damping creates warmer, more natural-sounding rooms (like a carpeted space). Low damping sounds brighter and more metallic (like a tiled bathroom)."
                    )

                    Knob(
                        value: $state.reverbWidth,
                        range: 0...1,
                        label: "Width",
                        unit: .percent,
                        defaultValue: 1.0,
                        tooltip: "Width: Controls the stereo spread of the reverb. At 100%, the reverb fills the entire stereo field. Lower values create a narrower, more focused reverb. Use lower values for a more intimate sound or to leave room for other elements."
                    )

                    Knob(
                        value: $state.reverbMix,
                        range: 0...1,
                        label: "Mix",
                        unit: .percent,
                        defaultValue: 0.3,
                        tooltip: "Mix: The balance between dry (original) and wet (reverb) signal. 0% is completely dry, 100% is all reverb. For subtle ambience use 10-20%. For noticeable reverb use 25-40%. Higher values create washy, ambient textures."
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
                        unit: .milliseconds,
                        defaultValue: 250,
                        tooltip: "Time: The delay between the original sound and its echo. Short delays (20-100ms) create doubling and slapback effects. Medium delays (100-400ms) produce rhythmic echoes. Long delays (500ms+) create distinct, separated repeats."
                    )

                    Knob(
                        value: $state.delayFeedback,
                        range: 0...0.95,
                        label: "Feedback",
                        unit: .percent,
                        defaultValue: 0.3,
                        tooltip: "Feedback: How much of the delayed signal feeds back into the delay. 0% gives a single echo. Higher values create multiple repeating echoes. Very high values (75%+) create long cascading trails. Be careful — high feedback can build up and get very loud."
                    )

                    Knob(
                        value: $state.delayMix,
                        range: 0...1,
                        label: "Mix",
                        unit: .percent,
                        defaultValue: 0.3,
                        tooltip: "Mix: The balance between dry (original) and wet (delayed) signal. Low values (10-25%) add subtle depth. Medium values (25-50%) make the delay clearly audible. Higher values create more dramatic echo effects."
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
                    unit: .generic,
                    defaultValue: 1.0,
                    tooltip: "Width: Controls the stereo spread. At 1.0, the stereo image is unchanged. Values below 1.0 narrow the image toward mono. Values above 1.0 widen the stereo field for a more expansive sound. Extreme values (1.5+) may cause phase issues on some systems."
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
                            size: 48,
                            defaultValue: 50,
                            tooltip: "Amount: How much bass enhancement to apply. Subtle enhancement (20-40%) adds warmth and depth. Moderate amounts (40-70%) make bass more prominent. High amounts can add significant low-end weight but watch for muddiness."
                        )

                        HStack(spacing: 12) {
                            CompactKnob(
                                value: $state.bassLowFreq,
                                range: 60...150,
                                label: "Freq",
                                unit: .hertz,
                                defaultValue: 100,
                                tooltip: "Frequency: The target frequency for bass enhancement. Lower values (60-80Hz) enhance deep sub-bass. Higher values (100-150Hz) enhance punch and body. Choose based on your audio content — music with heavy bass might need lower values."
                            )

                            CompactKnob(
                                value: $state.bassHarmonics,
                                range: 0...100,
                                label: "Harmonics",
                                unit: .percent,
                                defaultValue: 30,
                                tooltip: "Harmonics: Adds upper harmonics to the bass frequencies, making them audible on smaller speakers that can't reproduce deep bass. More harmonics = bass that 'cuts through' better but may sound less natural."
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
                            unit: .percent,
                            defaultValue: 50,
                            tooltip: "Clarity: Enhances the presence and intelligibility of vocals and speech by boosting the 2-4kHz range where consonants live. This makes voices cut through a mix more clearly. Too much can sound harsh or nasal."
                        )

                        Knob(
                            value: $state.vocalAir,
                            range: 0...100,
                            label: "Air",
                            unit: .percent,
                            defaultValue: 25,
                            tooltip: "Air: Adds a subtle high-frequency lift (10kHz+) to create a sense of openness and sparkle. This can make audio sound more 'produced' and professional. Use subtly — too much air can sound sibilant or harsh."
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
