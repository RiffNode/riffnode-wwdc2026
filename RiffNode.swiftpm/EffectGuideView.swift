import SwiftUI

// MARK: - Effect Guide View
// Liquid Glass UI Design - iOS 26+

struct EffectGuideView: View {

    // MARK: - Dependencies

    private let guideService: EffectGuideServiceProtocol

    // MARK: - State

    @State private var selectedCategoryIndex: Int = 0
    @State private var expandedEffectId: UUID? = nil
    @State private var selectedSection: LearnSection = .effects

    enum LearnSection: String, CaseIterable {
        case science = "Sound Science"
        case effects = "Effect Types"
    }

    // MARK: - Initialization

    init(guideService: EffectGuideServiceProtocol = EffectGuideService.shared) {
        self.guideService = guideService
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
            // Header with section picker
            VStack(spacing: 16) {
                HStack {
                    Text("Learn")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.horizontal)

                // Section picker - native segmented style
                Picker("Section", selection: $selectedSection) {
                    ForEach(LearnSection.allCases, id: \.self) { section in
                        Text(section.rawValue)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            .padding(.top)

            // Content based on selected section
            ScrollView {
                switch selectedSection {
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
                                ForEach(Array(category.effects.enumerated()), id: \.offset) { index, effect in
                                    if let effectModel = effect as? EffectInfoModel {
                                        GlassEffectCardView(
                                            effect: effectModel,
                                            isExpanded: expandedEffectId == effectModel.id
                                        ) {
                                            withAnimation(.spring(duration: 0.3)) {
                                                expandedEffectId = expandedEffectId == effectModel.id ? nil : effectModel.id
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
    }
}

// MARK: - Glass Sound Science Section

struct GlassSoundScienceView: View {
    @State private var selectedTopic: SoundTopic = .waveforms
    @State private var animationPhase: Double = 0

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


// MARK: - Glass Effect Category Visualization

struct GlassEffectCategoryVisualization: View {
    let category: any EffectCategoryProviding

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.3))

            TimelineView(.animation(minimumInterval: 0.03)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let midY = size.height / 2

                    switch category.name.lowercased() {
                    case "dynamics":
                        drawDynamicsEffect(context: context, size: size, midY: midY, time: time, color: category.color)
                    case "gain / dirt":
                        drawDistortionEffect(context: context, size: size, midY: midY, time: time, color: category.color)
                    case "modulation":
                        drawModulationEffect(context: context, size: size, midY: midY, time: time, color: category.color)
                    case "time / ambience":
                        drawTimeEffect(context: context, size: size, midY: midY, time: time, color: category.color)
                    case "filter / pitch":
                        drawFilterEffect(context: context, size: size, midY: midY, time: time, color: category.color)
                    default:
                        drawGenericWaveform(context: context, size: size, midY: midY, time: time, color: category.color)
                    }
                }
            }
            .padding(8)

            // Labels
            HStack {
                VStack(alignment: .leading) {
                    Text("INPUT")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("OUTPUT")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(category.color)
                    Spacer()
                }
            }
            .padding(8)
        }
        .frame(height: 80)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func drawDynamicsEffect(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double, color: Color) {
        var inputPath = Path()
        var outputPath = Path()

        inputPath.move(to: CGPoint(x: 0, y: midY))
        outputPath.move(to: CGPoint(x: 0, y: midY))

        for x in stride(from: 0, through: size.width, by: 2) {
            let relativeX = x / size.width
            let inputAmplitude = (0.3 + sin(relativeX * .pi * 2) * 0.5) * size.height * 0.4
            let inputY = midY + sin(relativeX * .pi * 6 + time * 2) * inputAmplitude

            let compressedAmplitude = size.height * 0.25
            let outputY = midY + sin(relativeX * .pi * 6 + time * 2) * compressedAmplitude

            inputPath.addLine(to: CGPoint(x: x, y: inputY))
            outputPath.addLine(to: CGPoint(x: x, y: outputY))
        }

        context.stroke(inputPath, with: .color(.gray.opacity(0.5)), lineWidth: 1.5)
        context.stroke(outputPath, with: .color(color), lineWidth: 2)
    }

    private func drawDistortionEffect(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double, color: Color) {
        var cleanPath = Path()
        var clippedPath = Path()

        cleanPath.move(to: CGPoint(x: 0, y: midY))
        clippedPath.move(to: CGPoint(x: 0, y: midY))

        for x in stride(from: 0, through: size.width, by: 2) {
            let relativeX = x / size.width
            let wave = sin(relativeX * .pi * 4 + time * 2)

            let cleanY = midY + wave * size.height * 0.35
            cleanPath.addLine(to: CGPoint(x: x, y: cleanY))

            let clippedWave = max(-0.6, min(0.6, wave * 1.5))
            let clippedY = midY + clippedWave * size.height * 0.35
            clippedPath.addLine(to: CGPoint(x: x, y: clippedY))
        }

        context.stroke(cleanPath, with: .color(.gray.opacity(0.4)), lineWidth: 1.5)
        context.stroke(clippedPath, with: .color(color), lineWidth: 2)
    }

    private func drawModulationEffect(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double, color: Color) {
        let colors: [Color] = [color.opacity(0.3), color.opacity(0.5), color]

        for (i, c) in colors.enumerated() {
            var path = Path()
            let phaseOffset = Double(i) * 0.1
            let pitchOffset = Double(i) * 0.05

            path.move(to: CGPoint(x: 0, y: midY))

            for x in stride(from: 0, through: size.width, by: 2) {
                let relativeX = x / size.width
                let modulatedFreq = 4.0 + sin(time * 3 + phaseOffset) * pitchOffset
                let y = midY + sin(relativeX * .pi * modulatedFreq + time * 2 + phaseOffset) * size.height * 0.3
                path.addLine(to: CGPoint(x: x, y: y))
            }

            context.stroke(path, with: .color(c), lineWidth: i == 2 ? 2 : 1.5)
        }
    }

    private func drawTimeEffect(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double, color: Color) {
        let echoes = 4

        for i in (0..<echoes).reversed() {
            var path = Path()
            let delay = Double(i) * 0.15
            let fade = 1.0 - Double(i) * 0.25

            path.move(to: CGPoint(x: 0, y: midY))

            for x in stride(from: 0, through: size.width, by: 2) {
                let relativeX = x / size.width
                let y = midY + sin(relativeX * .pi * 4 + time * 2 - delay * 10) * size.height * 0.3 * fade
                path.addLine(to: CGPoint(x: x, y: y))
            }

            let strokeColor = i == 0 ? color : color.opacity(fade * 0.6)
            context.stroke(path, with: .color(strokeColor), lineWidth: i == 0 ? 2 : 1.5)
        }
    }

    private func drawFilterEffect(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double, color: Color) {
        var fullPath = Path()
        var filteredPath = Path()

        fullPath.move(to: CGPoint(x: 0, y: midY))
        filteredPath.move(to: CGPoint(x: 0, y: midY))

        for x in stride(from: 0, through: size.width, by: 2) {
            let relativeX = x / size.width

            let low = sin(relativeX * .pi * 2 + time * 2) * 0.5
            let mid = sin(relativeX * .pi * 6 + time * 2) * 0.3
            let high = sin(relativeX * .pi * 16 + time * 2) * 0.2
            let fullY = midY + (low + mid + high) * size.height * 0.3
            fullPath.addLine(to: CGPoint(x: x, y: fullY))

            let filteredY = midY + (low + mid * 0.5) * size.height * 0.3
            filteredPath.addLine(to: CGPoint(x: x, y: filteredY))
        }

        context.stroke(fullPath, with: .color(.gray.opacity(0.4)), lineWidth: 1.5)
        context.stroke(filteredPath, with: .color(color), lineWidth: 2)
    }

    private func drawGenericWaveform(context: GraphicsContext, size: CGSize, midY: CGFloat, time: Double, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))

        for x in stride(from: 0, through: size.width, by: 2) {
            let relativeX = x / size.width
            let y = midY + sin(relativeX * .pi * 4 + time * 2) * size.height * 0.3
            path.addLine(to: CGPoint(x: x, y: y))
        }

        context.stroke(path, with: .color(color), lineWidth: 2)
    }
}

// MARK: - Glass Effect Card View

struct GlassEffectCardView: View {
    let effect: EffectInfoModel
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        GlassCard(cornerRadius: 12, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Header - clean, minimal design
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        Text(effect.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(isExpanded ? "Less" : "More")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }
                .buttonStyle(.plain)

                if isExpanded {
                    GlassEffectCardDetails(effect: effect)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(duration: 0.3), value: isExpanded)
    }
}

// MARK: - Glass Effect Card Details

struct GlassEffectCardDetails: View {
    let effect: EffectInfoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Divider - subtle
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 16) {
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

// MARK: - Effects List View (Legacy)

struct EffectsListView: View {
    let effects: [any EffectInfoProviding]
    @Binding var expandedEffectId: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(effects.enumerated()), id: \.offset) { index, effect in
                    if let effectModel = effect as? EffectInfoModel {
                        GlassEffectCardView(
                            effect: effectModel,
                            isExpanded: expandedEffectId == effectModel.id
                        ) {
                            withAnimation(.spring(duration: 0.3)) {
                                expandedEffectId = expandedEffectId == effectModel.id ? nil : effectModel.id
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()

        EffectGuideView()
    }
}
