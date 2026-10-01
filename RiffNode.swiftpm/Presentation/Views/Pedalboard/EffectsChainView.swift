import SwiftUI

// MARK: - Effects Chain View (Glass Pedalboard)
// Liquid Glass UI Design - iOS 26+

struct EffectsChainView: View {
    @Bindable var engine: AudioEngineManager
    @State private var selectedEffect: EffectNode?

    var body: some View {
        VStack(spacing: 16) {
            // Header – plain row, no glass on the title; buttons are capsule glass
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "cable.connector.horizontal")
                        .foregroundStyle(.orange)
                    Text("Pedalboard")
                        .font(.title3.bold())
                }

                Spacer()

                // Add effect menu
                Menu {
                    ForEach(EffectCategory.allCases) { category in
                        Menu(category.rawValue) {
                            ForEach(EffectType.effectTypes(for: category)) { type in
                                Button {
                                    withAnimation(.spring(duration: 0.3)) {
                                        engine.addEffect(type)
                                    }
                                } label: {
                                    Label(type.rawValue, systemImage: type.icon)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Pedal")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)

                // Stage Mode button
                Button {
                    NotificationCenter.default.post(name: .enterPerformanceMode, object: nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.expand.vertical")
                        Text("Stage Mode")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Signal chain visualization
            GlassSignalChainView(
                engine: engine,
                selectedEffect: $selectedEffect
            )

            // Parameter controls for selected effect
            if let effect = selectedEffect {
                GlassPedalControlsView(effect: effect, engine: engine)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .padding()
        .animation(.spring(duration: 0.3), value: selectedEffect?.id)
    }
}

// MARK: - Glass Signal Chain View

struct GlassSignalChainView: View {
    @Bindable var engine: AudioEngineManager
    @Binding var selectedEffect: EffectNode?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            signalChainContent
        }
        .scrollBounceBehavior(.basedOnSize)
        // Dark pedalboard surface
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.13), Color(white: 0.09)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [Color(white: 0.28), Color(white: 0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        // Trailing fade — tells the user there's more content to scroll to
        .overlay(alignment: .trailing) {
            if engine.effectsChain.count > 4 {
                LinearGradient(
                    colors: [Color(white: 0.09).opacity(0), Color(white: 0.09)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 48)
                .clipShape(
                    .rect(
                        bottomTrailingRadius: 18,
                        topTrailingRadius: 18
                    )
                )
                .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }

    private var signalChainContent: some View {
        HStack(spacing: 0) {
            PedalboardJack(label: "IN", isInput: true)
            PedalboardCable()

            ForEach(Array(engine.effectsChain.enumerated()), id: \.element.id) { index, effect in
                pedalWithDragDrop(effect: effect, index: index)
                PedalboardCable()
            }

            PedalboardJack(label: "OUT", isInput: false)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 12)
    }

    private func pedalWithDragDrop(effect: EffectNode, index: Int) -> some View {
        let isCurrentlySelected = selectedEffect?.id == effect.id

        return GlassEffectPedal(
            effect: effect,
            isSelected: isCurrentlySelected,
            onTap: { handleTap(effect: effect) },
            onDoubleTap: { engine.toggleEffect(effect) },
            onDelete: { handleDelete(effect: effect, index: index) }
        )
        .draggable(effect.id.uuidString) {
            dragPreview(for: effect)
        }
        .dropDestination(for: String.self) { items, _ in
            return handleDrop(items: items, targetIndex: index)
        }
    }

    private func handleTap(effect: EffectNode) {
        withAnimation(.spring(duration: 0.25)) {
            if selectedEffect?.id == effect.id {
                selectedEffect = nil
            } else {
                selectedEffect = effect
            }
        }
    }

    private func handleDelete(effect: EffectNode, index: Int) {
        withAnimation(.spring(duration: 0.3)) {
            if selectedEffect?.id == effect.id {
                selectedEffect = nil
            }
            engine.removeEffect(at: index)
        }
    }

    private func dragPreview(for effect: EffectNode) -> some View {
        GlassEffectPedal(
            effect: effect,
            isSelected: false,
            onTap: {},
            onDoubleTap: {},
            onDelete: {}
        )
        .opacity(0.7)
        .scaleEffect(0.9)
    }

    private func handleDrop(items: [String], targetIndex: Int) -> Bool {
        guard let droppedId = items.first else { return false }
        guard let sourceIndex = engine.effectsChain.firstIndex(where: { $0.id.uuidString == droppedId }) else { return false }
        guard sourceIndex != targetIndex else { return false }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        withAnimation(.spring(duration: 0.3)) {
            engine.moveEffect(from: IndexSet(integer: sourceIndex), to: destination)
        }
        return true
    }
}

// MARK: - Pedalboard Jack (hardware-style)

struct PedalboardJack: View {
    let label: String
    let isInput: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Jack housing – dark metal cylinder
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 42, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(white: 0.28), lineWidth: 1)
                    )

                // Jack hole – dark circle with rim
                Circle()
                    .fill(Color(white: 0.04))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(Color(white: 0.3), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }

            // Label
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isInput ? Color.green : Color(white: 0.55))
        }
    }
}

// MARK: - Pedalboard Cable (hardware-style)

struct PedalboardCable: View {
    var body: some View {
        VStack(spacing: 0) {
            // Cable line – slightly curved look via a thin rounded rect
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.18), Color(white: 0.22)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 28, height: 3)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
    }
}

// MARK: - Glass Pedal Controls View

struct GlassPedalControlsView: View {
    @Bindable var effect: EffectNode
    let engine: AudioEngineManager
    @State private var showingInfo = false

    var body: some View {
        GlassCard(tint: effect.type.color, cornerRadius: 16) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: effect.type.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(effect.type.color)

                        Text(effect.type.rawValue)
                            .font(.headline)
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
                    GlassEffectEducationView(effectType: effect.type)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))

                    GlassDivider()
                }

                // Knobs based on effect type
                GlassEffectKnobsView(effect: effect, binding: binding)
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

// MARK: - Glass Effect Education View

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

// MARK: - Glass Education Section

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

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing

                self.size.width = max(self.size.width, x)
            }

            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Glass Effect Knobs View

struct GlassEffectKnobsView: View {
    let effect: EffectNode
    let binding: (String) -> Binding<Float>

    var body: some View {
        HStack(spacing: 24) {
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

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()
        EffectsChainView(engine: AudioEngineManager())
            .frame(height: 500)
            .padding()
    }
}
