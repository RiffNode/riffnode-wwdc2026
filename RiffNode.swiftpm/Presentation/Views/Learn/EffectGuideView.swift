import SwiftUI

// MARK: - Learn
// Four chapters, each one picked from a big visual card: build a real pedalboard, browse
// the classic pedals, the effect families, and the science of sound. Every chapter is
// something to play with first and read second.

struct EffectGuideView: View {

    // MARK: - Dependencies

    private let guideService: EffectGuideServiceProtocol
    var engine: (any LearnEngine)?

    // MARK: - State

    @State private var selectedCategoryIndex: Int = 0
    @State private var expandedEffectId: UUID? = nil
    /// Remembers the chapter you were reading.
    @AppStorage("learn.chapter") private var selectedSection: LearnSection = .board
    @State private var addedEffectId: UUID? = nil

    enum LearnSection: String, CaseIterable, Identifiable {
        case board = "Build a Board"
        case library = "Pedal Library"
        case effects = "Effect Types"
        case science = "Sound Science"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .board: "Cable, tuner, power, order"
            case .library: "20 classic pedals to hear"
            case .effects: "What each family does"
            case .science: "Waves, harmonics, pitch"
            }
        }

        var icon: String {
            switch self {
            case .board: "rectangle.3.group"
            case .library: "square.grid.3x3.fill"
            case .effects: "slider.horizontal.3"
            case .science: "waveform"
            }
        }

        var tint: Color {
            switch self {
            case .board: .orange
            case .library: .green
            case .effects: .purple
            case .science: .cyan
            }
        }
    }

    // MARK: - Initialization

    init(guideService: any EffectGuideServiceProtocol, engine: (any LearnEngine)? = nil) {
        self.guideService = guideService
        self.engine = engine
    }

    // MARK: - Computed Properties

    private var categories: [any EffectCategoryProviding] {
        guideService.categories
    }

    private var selectedCategory: (any EffectCategoryProviding)? {
        guard selectedCategoryIndex < categories.count else { return nil }
        return categories[selectedCategoryIndex]
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Content based on selected section
            ScrollView {
                chapterCards
                    .padding(.horizontal)
                    .padding(.top)

                switch selectedSection {
                case .board:
                    BoardGuideView(chain: engine?.effectsChain ?? [])
                        .padding()

                case .library:
                    PedalLibraryView(engine: engine)
                        .padding()

                case .science:
                    GlassSoundScienceView()
                        .padding(.top)

                case .effects:
                    VStack(spacing: 16) {
                        // Category picker - native segmented style
                        if categories.count > 0 {
                            Picker("Category", selection: $selectedCategoryIndex) {
                                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                                    Text(category.name)
                                        .tag(index)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                        }

                        if let category = selectedCategory {
                            // Category description - minimal
                            Text(category.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 8)

                            // Effects list - cleaner design
                            LazyVStack(spacing: 12) {
                                // Pedals you can play in RiffNode come first; the rest are for reading
                                ForEach(Array(category.effects.sorted { (a: any EffectInfoProviding, b: any EffectInfoProviding) in
                                    (a as? EffectInfoModel)?.effectType != nil && (b as? EffectInfoModel)?.effectType == nil
                                }.enumerated()), id: \.offset) { index, effect in
                                    if let effectModel = effect as? EffectInfoModel {
                                        GlassEffectCardView(
                                            effect: effectModel,
                                            isExpanded: expandedEffectId == effectModel.id,
                                            justAdded: addedEffectId == effectModel.id,
                                            engine: engine
                                        ) {
                                            withAnimation(.spring(duration: 0.3)) {
                                                expandedEffectId = expandedEffectId == effectModel.id ? nil : effectModel.id
                                            }
                                        } onTryEffect: { type in
                                            if let eng = engine {
                                                eng.addEffect(type)
                                                addedEffectId = effectModel.id
                                                Task { @MainActor in
                                                    try? await Task.sleep(for: .milliseconds(1500))
                                                    addedEffectId = nil
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: selectedSection)
        .animation(.smooth(duration: 0.25), value: selectedCategoryIndex)
        // Leaving Learn hands the player's own pedalboard back
        .onDisappear { engine?.stopAudition() }
        .onChange(of: selectedSection) { _, _ in engine?.stopAudition() }
    }

    /// The four chapters as big cards; the chosen one is lit.
    private var chapterCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            ForEach(LearnSection.allCases) { section in
                let isOn = selectedSection == section
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.icon)
                            .font(.title2)
                            .foregroundStyle(isOn ? .white : section.tint)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 12).fill(isOn ? section.tint : section.tint.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.rawValue).font(.headline)
                            Text(section.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .glassEffect(isOn ? .regular.tint(section.tint.opacity(0.25)).interactive() : .regular.interactive(),
                                 in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isOn ? section.tint.opacity(0.7) : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Glass Sound Science Section

struct GlassSoundScienceView: View {
    @State private var selectedTopic: SoundTopic = .waveforms
    @State private var animationPhase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum SoundTopic: String, CaseIterable {
        case waveforms = "Waves"
        case frequency = "Pitch"
        case clipping = "Distortion"
        case time = "Time"

        var explanation: String {
            switch self {
            case .waveforms:
                return "Sound is vibration traveling through air as waves. Guitar strings vibrate, creating pressure waves your ears interpret as sound. The shape of these waves determines the tone quality."
            case .frequency:
                return "Frequency is how fast sound waves vibrate, measured in Hertz (Hz). Higher frequency = higher pitch. Guitar effects can shift, multiply, or modulate these frequencies."
            case .clipping:
                return "Distortion occurs when a signal is too loud for a circuit to handle cleanly. The tops of the waves get 'clipped' off, creating harmonics that give that crunchy, aggressive sound."
            case .time:
                return "Time-based effects manipulate when you hear the sound. Delay creates echoes, reverb simulates reflections in physical spaces, and chorus uses tiny delays for movement."
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Topic selector - native segmented picker
            Picker("Topic", selection: $selectedTopic) {
                ForEach(SoundTopic.allCases, id: \.self) { topic in
                    Text(topic.rawValue)
                        .tag(topic)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Content card
            GlassCard(cornerRadius: 16) {
                VStack(spacing: 16) {
                    // Visualization - more subtle colors
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(0.2))

                        SoundVisualization(topic: selectedTopic, phase: animationPhase)
                            .padding()
                    }
                    .frame(height: 100)

                    // Explanation
                    Text(selectedTopic.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }
}

// MARK: - Sound Visualization

struct SoundVisualization: View {
    let topic: GlassSoundScienceView.SoundTopic
    let phase: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let midY = size.height / 2
                let time = timeline.date.timeIntervalSinceReferenceDate

                switch topic {
                case .waveforms:
                    drawWaveform(context: context, size: size, midY: midY, time: time)
                case .frequency:
                    drawFrequency(context: context, size: size, midY: midY, time: time)
                case .clipping:
                    drawClipping(context: context, size: size, midY: midY, time: time)
                case .time:
                    drawTimeEffect(context: context, size: size, midY: midY, time: time)
                }
            }
        }
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))

        for x in stride(from: 0, through: size.width, by: 2) {
            let relativeX = x / size.width
            let y = midY + sin(relativeX * .pi * 4 + time * 2) * size.height * 0.35
            path.addLine(to: CGPoint(x: x, y: y))
        }

        context.stroke(path, with: .color(.cyan), lineWidth: 2)
    }

    private func drawFrequency(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double) {
        // Low frequency wave
        var lowPath = Path()
        lowPath.move(to: CGPoint(x: 0, y: midY - 20))
        for x in stride(from: 0, through: size.width, by: 2) {
            let y = midY - 20 + sin(x / size.width * .pi * 2 + time) * 15
            lowPath.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(lowPath, with: .color(.red.opacity(0.8)), lineWidth: 2)

        // High frequency wave
        var highPath = Path()
        highPath.move(to: CGPoint(x: 0, y: midY + 20))
        for x in stride(from: 0, through: size.width, by: 2) {
            let y = midY + 20 + sin(x / size.width * .pi * 8 + time * 2) * 15
            highPath.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(highPath, with: .color(.green.opacity(0.8)), lineWidth: 2)
    }

    private func drawClipping(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double) {
        // Clean wave
        var cleanPath = Path()
        cleanPath.move(to: CGPoint(x: 0, y: midY))
        for x in stride(from: 0, through: size.width / 2 - 10, by: 2) {
            let y = midY + sin(x / size.width * .pi * 6 + time * 2) * size.height * 0.35
            cleanPath.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(cleanPath, with: .color(.green.opacity(0.6)), lineWidth: 2)

        // Clipped wave
        var clippedPath = Path()
        let startX = size.width / 2 + 10
        clippedPath.move(to: CGPoint(x: startX, y: midY))
        for x in stride(from: startX, through: size.width, by: 2) {
            var y = midY + sin(x / size.width * .pi * 6 + time * 2) * size.height * 0.5
            let clipThreshold = size.height * 0.25
            y = min(max(y, midY - clipThreshold), midY + clipThreshold)
            clippedPath.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(clippedPath, with: .color(.orange), lineWidth: 2)
    }

    private func drawTimeEffect(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double) {
        // Original signal
        var originalPath = Path()
        originalPath.move(to: CGPoint(x: 0, y: midY))
        for x in stride(from: 0, through: size.width, by: 2) {
            let y = midY + sin(x / size.width * .pi * 4 + time * 2) * size.height * 0.3
            originalPath.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(originalPath, with: .color(.cyan), lineWidth: 2)

        // Delayed echo
        var delayedPath = Path()
        let offset: CGFloat = 40
        delayedPath.move(to: CGPoint(x: offset, y: midY))
        for x in stride(from: offset, through: size.width, by: 2) {
            let y = midY + sin((x - offset) / size.width * .pi * 4 + time * 2) * size.height * 0.2
            delayedPath.addLine(to: CGPoint(x: x, y: y))
        }
        context.stroke(delayedPath, with: .color(.cyan.opacity(0.4)), lineWidth: 2)
    }
}

// MARK: - Glass Effect Card View

struct GlassEffectCardView: View {
    let effect: EffectInfoModel
    let isExpanded: Bool
    var justAdded: Bool = false
    var engine: (any LearnEngine)? = nil
    let onTap: () -> Void
    var onTryEffect: ((EffectType) -> Void)? = nil

    var body: some View {
        GlassCard(cornerRadius: 12, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Header - clean, minimal design
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        // Color dot for the effect category
                        Circle()
                            .fill(effect.color.opacity(0.8))
                            .frame(width: 8, height: 8)

                        Text(effect.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        // "Try It" badge if effect is in the app
                        if let effectType = effect.effectType, onTryEffect != nil {
                            if justAdded {
                                Label("Added!", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Text(effectType.abbreviation)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(effect.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .glassEffect(.regular.tint(effect.color.opacity(0.15)), in: Capsule())
                            }
                        }

                        Text(isExpanded ? "Less" : "More")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }
                .buttonStyle(.plain)

                if isExpanded {
                    GlassEffectCardDetails(
                        effect: effect,
                        engine: engine,
                        onTryEffect: onTryEffect
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(duration: 0.3), value: isExpanded)
        .animation(.spring(duration: 0.3), value: justAdded)
    }
}

// MARK: - Glass Effect Card Details

struct GlassEffectCardDetails: View {
    let effect: EffectInfoModel
    var engine: (any LearnEngine)? = nil
    var onTryEffect: ((EffectType) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Divider - subtle
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 16) {
                // Hear it first – sound before reading
                if let effectType = effect.effectType, let engine {
                    EffectAuditionPanel(type: effectType, tint: effect.color, engine: engine)
                }

                // What It Does
                GlassEffectInfoSection(
                    title: "What It Does",
                    content: effect.function
                )

                // The Sound
                GlassEffectInfoSection(
                    title: "The Sound",
                    content: effect.sound
                )

                // How To Use
                GlassEffectTipsSection(
                    title: "How To Use",
                    content: effect.howToUse
                )

                // Signal Chain Position
                GlassEffectSignalChainSection(
                    position: effect.signalChainPosition
                )

                // Famous Artists
                GlassEffectArtistsSection(
                    artists: effect.famousUsers
                )

                // Try on Pedalboard - only for effects available in the app
                if let effectType = effect.effectType, let tryAction = onTryEffect {
                    Button {
                        tryAction(effectType)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Add to Pedalboard")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(effect.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(effect.color.opacity(0.15)), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

// MARK: - Glass Effect Info Section

struct GlassEffectInfoSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Glass Effect Tips Section

struct GlassEffectTipsSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Glass Effect Signal Chain Section

struct GlassEffectSignalChainSection: View {
    let position: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SIGNAL CHAIN")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            // Visual signal chain indicator
            HStack(spacing: 4) {
                Text("IN")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)

                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == getPositionIndex() ? Color.primary.opacity(0.6) : Color.primary.opacity(0.15))
                        .frame(width: 20, height: 8)
                }

                Text("OUT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)

                Spacer()
            }

            Text(position)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func getPositionIndex() -> Int {
        let lowercased = position.lowercased()
        if lowercased.contains("first") || lowercased.contains("beginning") || lowercased.contains("front") {
            return 0
        } else if lowercased.contains("early") || lowercased.contains("after compressor") {
            return 1
        } else if lowercased.contains("middle") {
            return 2
        } else if lowercased.contains("late") || lowercased.contains("before reverb") {
            return 3
        } else if lowercased.contains("end") || lowercased.contains("last") {
            return 4
        }
        return 2
    }
}

// MARK: - Glass Effect Artists Section

struct GlassEffectArtistsSection: View {
    let artists: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FAMOUS USERS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            let artistList = artists.components(separatedBy: ", ")
            FlowLayout(spacing: 6) {
                ForEach(artistList, id: \.self) { artist in
                    Text(artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: Capsule())
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()

        EffectGuideView(guideService: AppDependencies.live().effectGuide)
    }
}

// MARK: - Effect Audition Panel
// "Hear it" – plays the demo riff through this pedal alone, with an A/B switch,
// so the difference is heard in seconds instead of read about.

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
                        .font(.system(size: 13, weight: .semibold))
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
