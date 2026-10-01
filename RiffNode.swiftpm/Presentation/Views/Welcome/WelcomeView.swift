import SwiftUI

// MARK: - Welcome View

struct WelcomeView: View {
    @Bindable var engine: AudioEngineManager
    let onStartTour: () -> Void
    let onSkipToMain: () -> Void

    @State private var viewModel: SetupViewModel?
    @State private var showContent = false
    @State private var setupComplete = false
    @State private var isSettingUp = false
    @State private var setupSteps: [SetupStepInfo] = []
    @Namespace private var welcomeNamespace

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 60)

            // Hero section with large glass logo - centered
            GlassEffectContainer(spacing: 24) {
                VStack(spacing: Spacing.xl) {
                    // Large glass app icon – circle shape matches the ambient glow
                    ZStack {
                        // Subtle ambient glow
                        Circle()
                            .fill(Color.riffPrimary.opacity(0.15))
                            .frame(width: 160, height: 160)
                            .blur(radius: 30)

                        // Logo on a circular glass disc
                        Image("RiffNodeLogo")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .foregroundStyle(Color.riffPrimary)
                            .padding(35)
                            .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.12)), in: Circle())
                    }
                    .scaleEffect(showContent ? 1 : 0.8)
                    .opacity(showContent ? 1 : 0)

                    // App name
                    VStack(spacing: Spacing.sm) {
                        Text("RiffNode")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Guitar Effects Playground")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(showContent ? 1 : 0)
                }
            }

            Spacer(minLength: 40)

            // Action buttons - simplified single-step setup
            VStack(spacing: Spacing.md) {
                if setupComplete {
                    // Setup complete – offer tour or skip
                    // "Take the Tour" is the primary CTA – tinted capsule glass
                    Button {
                        onStartTour()
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "sparkles")
                            Text("Take the Tour")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 32)
                        .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.18)), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // "Skip to Main" is a secondary action – plain capsule glass
                    Button {
                        onSkipToMain()
                    } label: {
                        Text("Skip to Main")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .glassEffect(.regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if isSettingUp {
                    // Loading state with progress steps – each row
                    // gets its own glass so they fuse inside the container
                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: Spacing.sm) {
                            ForEach(setupSteps) { step in
                                HStack(spacing: Spacing.sm) {
                                    Group {
                                        if step.isComplete {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        } else if step.isActive {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .frame(width: 20)

                                    Text(step.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(step.isActive ? .primary : (step.isComplete ? .secondary : .tertiary))

                                    Spacer()
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .glassEffect(
                                    step.isComplete
                                        ? .regular.tint(.green.opacity(0.15))
                                        : (step.isActive ? .regular.tint(Color.riffPrimary.opacity(0.2)) : .regular),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                            }
                        }
                        .frame(width: 300)
                    }
                } else {
                    // Initial setup button – primary CTA capsule
                    Button {
                        startSetup()
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "play.fill")
                            Text("Get Started")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 36)
                        .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.18)), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // Subtitle explaining what happens
                    Text("Requests microphone access and starts audio engine")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.bottom, Spacing.xxl)

            if let error = viewModel?.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .onAppear {
            viewModel = SetupViewModel(audioEngine: engine)
            withAnimation(.easeOut(duration: 0.5)) {
                showContent = true
            }
        }
    }

    private func startSetup() {
        Task {
            // Step 1: Request microphone permission FIRST (shows system dialog immediately)
            await engine.requestMicrophonePermission()

            // Check if permission was granted
            guard engine.hasPermission else {
                engine.errorMessage = "Microphone access is required to use RiffNode."
                return
            }

            // Permission granted - now show loading UI for remaining steps
            setupSteps = [
                SetupStepInfo(id: 0, title: "Configuring audio session", isActive: true, isComplete: false),
                SetupStepInfo(id: 1, title: "Initializing effects engine", isActive: false, isComplete: false),
                SetupStepInfo(id: 2, title: "Starting audio processing", isActive: false, isComplete: false)
            ]

            // Trigger loading UI
            isSettingUp = true

            do {
                // Step 1: Configure audio session
                try? await Task.sleep(for: .milliseconds(200))

                // Step 2: Initialize effects engine
                withAnimation(.easeInOut(duration: 0.2)) {
                    setupSteps[0].isActive = false
                    setupSteps[0].isComplete = true
                    setupSteps[1].isActive = true
                }
                try await engine.setupEngine()

                // Step 3: Start audio processing
                withAnimation(.easeInOut(duration: 0.2)) {
                    setupSteps[1].isActive = false
                    setupSteps[1].isComplete = true
                    setupSteps[2].isActive = true
                }
                try engine.start()

                // Complete
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeInOut(duration: 0.2)) {
                    setupSteps[2].isActive = false
                    setupSteps[2].isComplete = true
                }

                // Transition to complete state
                try? await Task.sleep(for: .milliseconds(400))
                isSettingUp = false
                withAnimation(.spring(duration: 0.4)) {
                    setupComplete = true
                }
            } catch {
                isSettingUp = false
                engine.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Setup Step Info

struct SetupStepInfo: Identifiable {
    let id: Int
    let title: String
    var isActive: Bool
    var isComplete: Bool
}
