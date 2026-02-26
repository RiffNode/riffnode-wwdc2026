import SwiftUI

// MARK: - Guided Tour View
// Liquid Glass UI Design - iOS 26+
// An interactive 3-minute educational experience about guitar effects

struct GuidedTourView: View {
    @Bindable var engine: AudioEngineManager
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var showingEffect = false
    @State private var demoEffect: EffectType = .distortion
    @State private var savedEffectStates: [EffectType: Bool] = [:]
    @Namespace private var tourNamespace

    private let tourSteps: [TourStep] = [
        TourStep(
            title: "Welcome to RiffNode",
            subtitle: "Your Guitar Effects Playground",
            content: "Ever wondered how guitarists create those amazing sounds? From the crunchy distortion of rock to the spacey echoes of ambient music - it's all about effects pedals.",
            highlightEffect: nil,
            actionLabel: "Let's Explore"
        ),
        TourStep(
            title: "The Signal Chain",
            subtitle: "How Sound Flows",
            content: "Your guitar signal flows through a chain of effects, each one transforming the sound. The order matters - distortion before reverb sounds very different from reverb before distortion!",
            highlightEffect: nil,
            actionLabel: "Show Me"
        ),
        TourStep(
            title: "Distortion",
            subtitle: "The Sound of Rock",
            content: "Distortion clips your audio signal, creating that gritty, aggressive tone. From subtle warmth to full metal crunch - this effect defined rock music. Used by Metallica, AC/DC, and Nirvana.",
            highlightEffect: .distortion,
            actionLabel: "Hear It"
        ),
        TourStep(
            title: "Delay",
            subtitle: "Echoes in Time",
            content: "Delay repeats your notes like an echo. Short delays add thickness, longer delays create rhythmic patterns. Think U2's 'Where The Streets Have No Name' - that's delay magic!",
            highlightEffect: .delay,
            actionLabel: "Try Delay"
        ),
        TourStep(
            title: "Reverb",
            subtitle: "Creating Space",
            content: "Reverb simulates how sound bounces in physical spaces. A small room, a concert hall, or a massive cathedral - reverb puts your guitar anywhere. Essential for that 'polished' sound.",
            highlightEffect: .reverb,
            actionLabel: "Add Space"
        ),
        TourStep(
            title: "Chorus",
            subtitle: "Shimmer & Width",
            content: "Chorus makes one guitar sound like several playing together, slightly out of tune. It creates a lush, shimmering quality. The secret behind Nirvana's 'Come As You Are'.",
            highlightEffect: .chorus,
            actionLabel: "Hear Chorus"
        ),
        TourStep(
            title: "You're Ready!",
            subtitle: "Start Creating",
            content: "Now you understand the basics of guitar effects. Experiment with different combinations, adjust the knobs, and discover your own signature sound. There are no wrong answers - only new discoveries!",
            highlightEffect: nil,
            actionLabel: "Start Playing"
        )
    ]

    var body: some View {
        ZStack {
            AdaptiveBackground()

            VStack(spacing: 0) {
                // Progress indicator - cleaner design
                GlassProgressBar(
                    progress: Double(currentStep) / Double(tourSteps.count - 1),
                    steps: tourSteps.count,
                    currentStep: currentStep
                )
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.lg)

                Spacer()

                // Main content
                let step = tourSteps[currentStep]

                VStack(spacing: Spacing.xl) {
                    // Effect visualization if applicable
                    if let effectType = step.highlightEffect {
                        GlassEffectDemoView(effectType: effectType, isActive: showingEffect)
                            .frame(height: 180)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Text content - clean and minimal without heavy glass border
                    VStack(spacing: Spacing.md) {
                        Text(step.title)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(step.subtitle)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(step.highlightEffect?.color ?? Color.riffPrimary)

                        Text(step.content)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.top, Spacing.sm)
                    }
                    .padding(Spacing.xl)
                    .frame(maxWidth: 500)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CornerRadius.xl))
                    .padding(.horizontal, Spacing.lg)
                }
                .id(currentStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Navigation
                GlassTourNavigation(
                    currentStep: currentStep,
                    actionLabel: tourSteps[currentStep].actionLabel,
                    onBack: handleBack,
                    onNext: handleAction,
                    namespace: tourNamespace
                )
                .padding(.bottom, Spacing.xl)

                // Skip option – capsule glass pill
                Button {
                    onComplete()
                } label: {
                    Text("Skip Tour")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, Spacing.lg)
            }
        }
        .onAppear {
            saveAndBypassAllEffects()
        }
        .onDisappear {
            restoreEffectStates()
        }
    }

    private func handleAction() {
        let step = tourSteps[currentStep]

        if currentStep < tourSteps.count - 1 {
            // Disable current effect before moving to next step
            if let currentEffect = step.highlightEffect {
                disableDemoEffect(currentEffect)
            }

            // Calculate next step index before updating currentStep
            let nextStepIndex = currentStep + 1
            let nextStep = tourSteps[nextStepIndex]

            withAnimation(.spring(duration: 0.4)) {
                showingEffect = false
                currentStep = nextStepIndex
            }

            // Enable the new step's effect after a short delay for smooth transition
            if let nextEffect = nextStep.highlightEffect {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    enableDemoEffect(nextEffect)
                    withAnimation(.spring(duration: 0.3)) {
                        showingEffect = true
                        demoEffect = nextEffect
                    }
                }
            }
        } else {
            restoreEffectStates()
            onComplete()
        }
    }

    private func handleBack() {
        let step = tourSteps[currentStep]

        // Disable current effect
        if let currentEffect = step.highlightEffect {
            disableDemoEffect(currentEffect)
        }

        // Calculate previous step
        let prevStepIndex = currentStep - 1
        let prevStep = tourSteps[prevStepIndex]

        withAnimation(.spring(duration: 0.4)) {
            showingEffect = false
            currentStep = prevStepIndex
        }

        // Enable the previous step's effect
        if let prevEffect = prevStep.highlightEffect {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                enableDemoEffect(prevEffect)
                withAnimation(.spring(duration: 0.3)) {
                    showingEffect = true
                    demoEffect = prevEffect
                }
            }
        }
    }

    private func saveAndBypassAllEffects() {
        savedEffectStates.removeAll()

        for effect in engine.effectsChain {
            savedEffectStates[effect.type] = effect.isEnabled

            if effect.isEnabled {
                engine.toggleEffect(effect)
            }
        }
    }

    private func restoreEffectStates() {
        for effect in engine.effectsChain {
            let shouldBeEnabled = savedEffectStates[effect.type] ?? false
            if effect.isEnabled != shouldBeEnabled {
                engine.toggleEffect(effect)
            }
        }
    }

    private func enableDemoEffect(_ type: EffectType) {
        if let effect = engine.effectsChain.first(where: { $0.type == type }) {
            if !effect.isEnabled {
                engine.toggleEffect(effect)
            }
        } else {
            engine.addEffect(type)
        }
    }

    private func disableDemoEffect(_ type: EffectType) {
        if let effect = engine.effectsChain.first(where: { $0.type == type }) {
            if effect.isEnabled {
                engine.toggleEffect(effect)
            }
        }
    }
}

// MARK: - Tour Step Model

struct TourStep {
    let title: String
    let subtitle: String
    let content: String
    let highlightEffect: EffectType?
    let actionLabel: String
}

// MARK: - Glass Progress Bar

struct GlassProgressBar: View {
    let progress: Double
    let steps: Int
    let currentStep: Int

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Step indicators – use .primary so dots adapt to colour scheme
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(0..<steps, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? Color.riffPrimary : Color.primary.opacity(0.2))
                            .frame(width: 10, height: 10)
                            .overlay {
                                if step == currentStep {
                                    Circle()
                                        .stroke(Color.riffPrimary, lineWidth: 2)
                                        .frame(width: 18, height: 18)
                                }
                            }

                        if step < steps - 1 {
                            Rectangle()
                                .fill(step < currentStep ? Color.riffPrimary : Color.primary.opacity(0.15))
                                .frame(height: 2)
                        }
                    }
                }
                .glassEffect(.regular, in: Capsule())
            }

            // Step counter
            Text("Step \(currentStep + 1) of \(steps)")
                .font(Typography.caption())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Glass Effect Demo View

struct GlassEffectDemoView: View {
    let effectType: EffectType
    let isActive: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Visual representation of the effect
            ZStack {
                // Background glow - more vibrant
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [effectType.color.opacity(isActive ? 0.4 : 0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)

                // Glass effect pedal - cleaner look
                VStack(spacing: 10) {
                    // LED indicator with better contrast
                    ZStack {
                        Circle()
                            .fill(isActive ? Color.green.opacity(0.3) : Color.clear)
                            .frame(width: 18, height: 18)
                            .blur(radius: 4)

                        Circle()
                            .fill(isActive ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 10, height: 10)
                    }

                    // Effect abbreviation - bold and clear
                    Text(effectType.abbreviation)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(isActive ? effectType.color : .primary)

                    // Effect name
                    Text(effectType.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 90, height: 110)
                .glassEffect(
                    isActive ? .regular.tint(effectType.color) : .regular,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .shadow(color: isActive ? effectType.color.opacity(0.4) : .black.opacity(0.1), radius: isActive ? 12 : 6)
            }

            // Waveform visualization - cleaner
            GlassWaveformDemo(isActive: isActive, color: effectType.color)
                .frame(height: 50)
                .padding(.horizontal, 30)
        }
    }
}

// MARK: - Glass Waveform Demo

struct GlassWaveformDemo: View {
    let isActive: Bool
    let color: Color

    var body: some View {
        ZStack {
            // Clean background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.05))

            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let midY = size.height / 2
                    var path = Path()

                    let date = timeline.date.timeIntervalSinceReferenceDate
                    let animatedPhase = isActive ? date * 3 : 0

                    path.move(to: CGPoint(x: 0, y: midY))

                    for x in stride(from: 0, through: size.width, by: 2) {
                        let relativeX = Double(x / size.width)
                        let amplitude = isActive ? Double(size.height) * 0.35 : Double(size.height) * 0.08

                        let wave1 = sin(relativeX * Double.pi * 4 + animatedPhase)
                        let wave2 = isActive ? sin(relativeX * Double.pi * 8 + animatedPhase * 1.5) * 0.3 : 0

                        let y = Double(midY) + (wave1 + wave2) * amplitude
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    // Draw filled area under wave
                    var fillPath = path
                    fillPath.addLine(to: CGPoint(x: size.width, y: midY))
                    fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                    fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                    fillPath.closeSubpath()

                    context.fill(
                        fillPath,
                        with: .linearGradient(
                            Gradient(colors: [color.opacity(isActive ? 0.3 : 0.1), color.opacity(0)]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )

                    // Stroke the wave line
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [color.opacity(0.9), color]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        lineWidth: isActive ? 2.5 : 1.5
                    )
                }
            }
            .padding(8)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Glass Tour Navigation

struct GlassTourNavigation: View {
    let currentStep: Int
    let actionLabel: String
    let onBack: () -> Void
    let onNext: () -> Void
    var namespace: Namespace.ID

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                if currentStep > 0 {
                    Button(action: onBack) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 28)
                        .glassEffect(.regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffectID("back_btn", in: namespace)
                }

                Button(action: onNext) {
                    HStack(spacing: Spacing.xs) {
                        Text(actionLabel)
                            .font(.headline.weight(.semibold))
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 32)
                    .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.18)), in: Capsule())
                }
                .buttonStyle(.plain)
                .glassEffectID("next_btn", in: namespace)
            }
        }
    }
}

// MARK: - Legacy Button Styles (for compatibility)

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(minWidth: 160)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [.cyan, .cyan.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    GuidedTourView(engine: AudioEngineManager(), onComplete: {})
}
