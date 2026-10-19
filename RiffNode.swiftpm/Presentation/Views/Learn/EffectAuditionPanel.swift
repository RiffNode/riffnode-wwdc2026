import SwiftUI

// MARK: - Effect Audition Panel

struct EffectAuditionPanel: View {
    let type: EffectType
    let tint: Color
    let engine: any LearnEngine

    private var isAuditioning: Bool { engine.auditionEffect == type }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if isAuditioning { engine.stopAudition() } else { engine.startAudition(type) }
                } label: {
                    Label(isAuditioning ? "Stop" : "Hear it", systemImage: isAuditioning ? "stop.fill" : "play.fill")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(isAuditioning ? .white : tint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isAuditioning ? tint : tint.opacity(0.15), in: Capsule())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(!engine.canPlayDemoRiff)
                .accessibilityHint("Plays a demo riff through the \(type.rawValue) alone")

                if isAuditioning {
                    // A/B switch
                    Picker("Compare", selection: Binding(
                        get: { engine.isAuditionBypassed },
                        set: { engine.setAuditionBypassed($0) }
                    )) {
                        Text("With \(type.abbreviation)").tag(false)
                        Text("Dry").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    NotchLevelIndicator(level: engine.inputLevel, tint: tint)
                }

                Spacer(minLength: 0)
            }

            Text(engine.canPlayDemoRiff ? type.listenFor : "Start the engine to hear this effect.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isAuditioning ? .primary : .secondary)

            // See it while you hear it: the pedal's input against its output, live.
            // Switching to Dry makes the two lines meet – the A/B, visible.
            if isAuditioning, let node = engine.effectsChain.first(where: { $0.type == type }) {
                SignalLabView(effect: node, engine: engine)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(tint.opacity(isAuditioning ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 12))
        .animation(.smooth(duration: 0.25), value: isAuditioning)
    }
}

/// Tiny live level bars so you can see the riff is playing.
private struct NotchLevelIndicator: View {
    let level: Float
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: max(4, CGFloat(AudioMeter.normalized(level)) * 18 * (1 - CGFloat(index) * 0.15)))
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}
