import SwiftUI

// MARK: - Sound Science

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
