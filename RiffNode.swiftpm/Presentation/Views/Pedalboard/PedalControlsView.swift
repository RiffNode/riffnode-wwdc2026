import SwiftUI

// MARK: - Pedal Controls

struct GlassPedalControlsView: View {
    @Bindable var effect: EffectNode
    let engine: any PedalboardEngine
    /// Narrow column next to the Signal Lab: knobs wrap onto more rows.
    var isCompact = false
    @State private var showingInfo = false

    var body: some View {
        GlassCard(tint: effect.type.color.opacity(0.18), cornerRadius: 16) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: effect.type.icon)
                            .font(.system(.callout, weight: .medium))
                            .foregroundStyle(effect.type.color)

                        PedalModelMenu(effect: effect, engine: engine)
                    }

                    Spacer()

                    // Info button
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            showingInfo.toggle()
                        }
                    } label: {
                        Image(systemName: showingInfo ? "info.circle.fill" : "info.circle")
                            .foregroundStyle(showingInfo ? effect.type.color : .secondary)
                    }
                    .buttonStyle(.plain)

                    // Bypass toggle
                    Toggle("", isOn: Binding(
                        get: { effect.isEnabled },
                        set: { _ in engine.toggleEffect(effect) }
                    ))
                    .toggleStyle(.switch)
                    .tint(effect.type.color)
                }

                GlassDivider()

                // Educational content
                if showingInfo {
                    if let model = effect.model {
                        PedalModelAbout(model: model)
                    }
                    GlassEffectEducationView(effectType: effect.type)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))

                    GlassDivider()
                }

                // Knobs based on effect type
                GlassEffectKnobsView(effect: effect, binding: binding, spacing: isCompact ? 12 : 24)
            }
        }
        .animation(.spring(duration: 0.3), value: showingInfo)
    }

    private func binding(for key: String) -> Binding<Float> {
        Binding(
            get: { effect.parameters[key] ?? 0 },
            set: { engine.updateEffectParameter(effect, key: key, value: $0) }
        )
    }
}

struct GlassEffectEducationView: View {
    let effectType: EffectType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // What it does
            GlassEducationSection(
                title: "What It Does",
                icon: "questionmark.circle",
                content: effectType.effectDescription,
                color: effectType.color
            )

            // How to use
            GlassEducationSection(
                title: "How To Use",
                icon: "hand.point.up",
                content: effectType.howToUse,
                color: .green
            )

            // Signal chain position
            GlassEducationSection(
                title: "Signal Chain Position",
                icon: "arrow.right.circle",
                content: effectType.signalChainPosition,
                color: .cyan
            )

            // Genres
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "music.note.list")
                    .foregroundStyle(.purple)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Common Genres")
                        .font(.caption.bold())
                        .foregroundStyle(.purple)

                    FlowLayout(spacing: 6) {
                        ForEach(effectType.commonGenres, id: \.self) { genre in
                            Text(genre)
                                .font(.caption2)
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassEffect(.regular.tint(.purple.opacity(0.2)), in: Capsule())
                        }
                    }
                }
            }

            // Famous examples
            GlassEducationSection(
                title: "Famous Examples",
                icon: "star.fill",
                content: effectType.famousExamples,
                color: .yellow
            )
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GlassEducationSection: View {
    let title: String
    let icon: String
    let content: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(color)

                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GlassEffectKnobsView: View {
    let effect: EffectNode
    let binding: (String) -> Binding<Float>
    var spacing: CGFloat = 24

    var body: some View {
        HStack(spacing: spacing) {
            switch effect.type {
            // Dynamics
            case .compressor:
                GlassKnob(value: binding("threshold"), range: -40...0, tint: effect.type.color, label: "THRESH", format: "%.0fdB")
                GlassKnob(value: binding("ratio"), range: 1...20, tint: effect.type.color, label: "RATIO", format: "%.1f:1")
                GlassKnob(value: binding("attack"), range: 0.1...100, tint: effect.type.color, label: "ATTACK", format: "%.0fms")

            // Filter & Pitch
            case .equalizer:
                GlassKnob(value: binding("bass"), range: -12...12, tint: .red, label: "BASS", format: "%.1fdB")
                GlassKnob(value: binding("mid"), range: -12...12, tint: .yellow, label: "MID", format: "%.1fdB")
                GlassKnob(value: binding("treble"), range: -12...12, tint: .cyan, label: "TREBLE", format: "%.1fdB")

            // Gain / Dirt
            case .overdrive:
                GlassKnob(value: binding("drive"), range: 0...100, tint: effect.type.color, label: "DRIVE")
                GlassKnob(value: binding("tone"), range: 0...100, tint: effect.type.color, label: "TONE")
                GlassKnob(value: binding("level"), range: 0...100, tint: effect.type.color, label: "LEVEL")

            case .distortion:
                GlassKnob(value: binding("drive"), range: 0...100, tint: effect.type.color, label: "DRIVE")
                GlassKnob(value: binding("tone"), range: 0...100, tint: effect.type.color, label: "TONE")
                GlassKnob(value: binding("level"), range: 0...100, tint: effect.type.color, label: "LEVEL")

            case .fuzz:
                GlassKnob(value: binding("fuzz"), range: 0...100, tint: effect.type.color, label: "FUZZ")
                GlassKnob(value: binding("tone"), range: 0...100, tint: effect.type.color, label: "TONE")
                GlassKnob(value: binding("level"), range: 0...100, tint: effect.type.color, label: "LEVEL")

            // Modulation
            case .chorus:
                GlassKnob(value: binding("rate"), range: 0.1...10, tint: effect.type.color, label: "RATE", format: "%.1fHz")
                GlassKnob(value: binding("depth"), range: 0...100, tint: effect.type.color, label: "DEPTH")
                GlassKnob(value: binding("mix"), range: 0...100, tint: effect.type.color, label: "MIX")

            case .phaser:
                GlassKnob(value: binding("rate"), range: 0.1...5, tint: effect.type.color, label: "RATE", format: "%.1fHz")
                GlassKnob(value: binding("depth"), range: 0...100, tint: effect.type.color, label: "DEPTH")
                GlassKnob(value: binding("feedback"), range: 0...100, tint: effect.type.color, label: "FDBK")

            case .flanger:
                GlassKnob(value: binding("rate"), range: 0.1...2, tint: effect.type.color, label: "RATE", format: "%.2fHz")
                GlassKnob(value: binding("depth"), range: 0...100, tint: effect.type.color, label: "DEPTH")
                GlassKnob(value: binding("feedback"), range: 0...100, tint: effect.type.color, label: "FDBK")

            case .tremolo:
                GlassKnob(value: binding("rate"), range: 0.5...15, tint: effect.type.color, label: "RATE", format: "%.1fHz")
                GlassKnob(value: binding("depth"), range: 0...100, tint: effect.type.color, label: "DEPTH")

            // Time & Ambience
            case .delay:
                GlassKnob(value: binding("time"), range: 0...2, tint: effect.type.color, label: "TIME", format: "%.2fs")
                GlassKnob(value: binding("feedback"), range: 0...100, tint: effect.type.color, label: "FDBK")
                GlassKnob(value: binding("mix"), range: 0...100, tint: effect.type.color, label: "MIX")

            case .reverb:
                GlassKnob(value: binding("wetDryMix"), range: 0...100, tint: effect.type.color, label: "MIX")
                GlassKnob(value: binding("decay"), range: 0.1...5, tint: effect.type.color, label: "DECAY", format: "%.1fs")
            }
        }
    }
}
