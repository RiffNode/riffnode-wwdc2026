import SwiftUI

// MARK: - Main Content View
// Liquid Glass UI Design - iOS 26+ Design Language

struct ContentView: View {

    // MARK: - Dependencies (Dependency Injection)

    @State private var engine = AudioEngineManager()
    @State private var presetService = PresetService()

    // MARK: - State

    enum AppState {
        case welcome
        case guidedTour
        case main
    }

    @State private var appState: AppState = .welcome

    // MARK: - Body

    var body: some View {
        ZStack {
            AdaptiveBackground()

            switch appState {
            case .welcome:
                WelcomeView(
                    engine: engine,
                    onStartTour: {
                        withAnimation(.spring(duration: 0.5)) {
                            appState = .guidedTour
                        }
                    },
                    onSkipToMain: {
                        withAnimation(.spring(duration: 0.5)) {
                            appState = .main
                        }
                    }
                )

            case .guidedTour:
                GuidedTourView(engine: engine) {
                    withAnimation(.spring(duration: 0.5)) {
                        appState = .main
                    }
                }

            case .main:
                MainInterfaceView(
                    engine: engine,
                    presetService: presetService
                )
            }
        }
        // iOS 26 Liquid Glass: Force light mode to match Apple's design language
        .preferredColorScheme(.light)
        #if os(macOS)
        .frame(minWidth: 1000, minHeight: 700)
        #endif
    }
}

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


// MARK: - Main Interface View

struct MainInterfaceView: View {
    @Bindable var engine: AudioEngineManager
    let presetService: PresetProviding

    @State private var showingSettings = false
    @State private var showingPresets = false
    @State private var selectedTab: MainTab = .pedalboard

    // AI Features
    @State private var fftAnalyzer = FFTAnalyzer()
    @State private var chordDetector = ChordDetector()
    @State private var gestureController = VisionGestureController()
    @State private var semanticProcessor = SemanticCommandProcessor()
    @State private var analysisTask: Task<Void, Never>?

    // AI Chatbot
    @State private var chatbotController = AIChatbotController()
    @State private var showingChatbot = false

    // Performance Mode
    @State private var showingPerformanceMode = false
    @State private var performanceController = PerformanceModeController()

    // Chord AI Bridge
    @State private var chordSuggestionTask: Task<Void, Never>?
    @State private var chordAISuggestion: String?
    @State private var chordAIPrompt: String?
    @State private var lastSuggestedChord = ""

    // Gesture Control (main view)
    @State private var gestureControlEnabled = false

    enum MainTab: String, CaseIterable {
        case pedalboard = "Pedalboard"
        case parametricEQ = "Parametric EQ"
        case aiTools = "AI Tools"
        case learnEffects = "Learn"

        var icon: String {
            switch self {
            case .pedalboard: return "slider.horizontal.below.square.filled.and.square"
            case .parametricEQ: return "slider.horizontal.3"
            case .aiTools: return "brain.head.profile"
            case .learnEffects: return "text.book.closed"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Floating glass top bar
            GlassTopBarView(
                engine: engine,
                chordDetector: chordDetector,
                showingSettings: $showingSettings,
                showingPresets: $showingPresets
            )
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            HStack(spacing: Spacing.md) {
                // Left panel – all glass cards sit inside one container
                // so neighbouring cards fuse into a single liquid shape
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: Spacing.md) {
                        AudioVisualizationPanel(engine: engine)

                        // Spectrum + chord badge fuse with the cards above / below
                        MiniSpectrumIndicator(analyzer: fftAnalyzer)

                        CompactChordBadge(detector: chordDetector)

                        BackingTrackView(engine: engine)

                        GestureControlPill(
                            controller: gestureController,
                            isEnabled: $gestureControlEnabled
                        )
                    }
                }
                .padding(Spacing.md)
                .frame(width: 380)

                // Right panel with tab switching
                VStack(spacing: 0) {
                    // Tab bar – single glass element, no container needed
                    GlassTabBar(selection: $selectedTab, tint: Color.riffPrimary) { tab in
                        tab.icon
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)

                    // Content based on selected tab
                    Group {
                        switch selectedTab {
                        case .pedalboard:
                            EffectsChainView(engine: engine)
                        case .parametricEQ:
                            ScrollView {
                                ParametricEQView(engine: engine)
                                    .padding()
                            }
                        case .aiTools:
                            AIToolsView(
                                fftAnalyzer: fftAnalyzer,
                                chordDetector: chordDetector,
                                engine: engine
                            )
                        case .learnEffects:
                            EffectGuideView(engine: engine)
                        }
                    }
                    .animation(.smooth(duration: 0.25), value: selectedTab)
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, Spacing.md)
            }
            .padding(.top, Spacing.sm)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(engine: engine)
        }
        .sheet(isPresented: $showingPresets) {
            PresetPickerView(engine: engine, presetService: presetService)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 400, minHeight: 500)
                #endif
        }
        // AI Chatbot Overlay + Chord Suggestion Chip
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: Spacing.sm) {
                if let suggestion = chordAISuggestion, let prompt = chordAIPrompt {
                    ChordSuggestionChip(
                        suggestion: suggestion,
                        onApply: {
                            chatbotController.inputText = prompt
                            showingChatbot = true
                            withAnimation(.spring(duration: 0.3)) { chordAISuggestion = nil }
                            lastSuggestedChord = chordDetector.detectedChord
                        },
                        onDismiss: {
                            withAnimation(.spring(duration: 0.3)) { chordAISuggestion = nil }
                            lastSuggestedChord = chordDetector.detectedChord
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                AIChatbotOverlayView(
                    controller: chatbotController,
                    processor: semanticProcessor,
                    engine: engine,
                    isExpanded: $showingChatbot
                )
            }
            .padding(Spacing.lg)
        }
        // Performance Mode - fullscreen pedalboard with gesture control
        .fullScreenCover(isPresented: $showingPerformanceMode) {
            PerformanceModeView(
                engine: engine,
                gestureController: gestureController,
                controller: performanceController,
                presets: presetService.presets,
                onExit: { showingPerformanceMode = false }
            )
        }
        .onChange(of: chordDetector.detectedChord) { _, newChord in
            scheduleChordSuggestion(newChord)
        }
        .onChange(of: gestureControlEnabled) { _, enabled in
            Task {
                if enabled {
                    try? await gestureController.start()
                    gestureControlEnabled = gestureController.isRunning
                } else {
                    gestureController.stop()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .enterPerformanceMode)) { _ in
            showingPerformanceMode = true
        }
        .onAppear {
            setupGestureActions()
            setupAudioAnalysis()
        }
    }

    private func setupGestureActions() {
        gestureController.onGestureDetected = { gesture in
            handleGesture(gesture)
        }
        gestureController.onMouthOpenValueChanged = { [engine] value in
            engine.setExpressionValue(value, for: .equalizer)
        }
    }

    private func setupAudioAnalysis() {
        analysisTask?.cancel()
        engine.onAudioSamplesAvailable = { [fftAnalyzer, chordDetector] samples in
            if samples.count >= 2048 {
                fftAnalyzer.analyze(samples: samples)
                chordDetector.analyze(samples: samples)
            }
        }
    }

    private func handleGesture(_ gesture: VisionGestureController.Gesture) {
        let presets = presetService.presets
        switch gesture {
        case .headNodDown:
            guard !presets.isEmpty else { return }
            let next = (performanceController.currentPresetIndex + 1) % presets.count
            performanceController.currentPresetIndex = next
            engine.applyPreset(presets[next])

        case .headNodUp:
            guard !presets.isEmpty else { return }
            let prev = (performanceController.currentPresetIndex - 1 + presets.count) % presets.count
            performanceController.currentPresetIndex = prev
            engine.applyPreset(presets[prev])

        case .headTiltLeft:
            engine.effectsChain.filter { $0.isEnabled }.forEach { engine.toggleEffect($0) }

        case .headTiltRight:
            engine.effectsChain.filter { !$0.isEnabled }.forEach { engine.toggleEffect($0) }

        case .mouthOpen:
            if let gainEffect = engine.effectsChain.first(where: {
                [.overdrive, .distortion, .fuzz].contains($0.type)
            }) { engine.toggleEffect(gainEffect) }

        case .eyebrowRaise:
            if let comp = engine.effectsChain.first(where: { $0.type == .compressor }) {
                engine.toggleEffect(comp)
            }
        }
    }

    // MARK: - Chord AI Bridge

    private func scheduleChordSuggestion(_ newChord: String) {
        guard newChord != "—", newChord != lastSuggestedChord else {
            chordSuggestionTask?.cancel()
            if newChord == "—" { withAnimation { chordAISuggestion = nil } }
            return
        }
        chordSuggestionTask?.cancel()
        chordSuggestionTask = Task {
            // Debounce: wait 2s for chord to stabilise
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard chordDetector.confidence > 0.55 else { return }
            guard chordDetector.detectedChord == newChord else { return }
            withAnimation(.spring(duration: 0.4)) {
                chordAISuggestion = chordToDisplayText(newChord)
                chordAIPrompt    = chordToAIPrompt(newChord)
            }
        }
    }

    private func chordToDisplayText(_ chord: String) -> String {
        if chord.contains("Major") { return "Detected \(chord) — clean tone?" }
        if chord.contains("7")     { return "Detected \(chord) — bluesy drive?" }
        if chord.contains("5")     { return "Detected \(chord) — rock crunch?" }
        if chord.contains("m")     { return "Detected \(chord) — warm blues?" }
        return "Detected \(chord) — AI tone?"
    }

    private func chordToAIPrompt(_ chord: String) -> String {
        if chord.contains("Major") { return "bright clean tone for playing \(chord)" }
        if chord.contains("7")     { return "bluesy overdrive for \(chord)" }
        if chord.contains("5")     { return "heavy rock crunch for \(chord) power chord" }
        if chord.contains("m")     { return "warm blues tone for \(chord)" }
        return "suggest a matching tone for playing \(chord)"
    }
}

// MARK: - AI Tools View

struct AIToolsView: View {
    let fftAnalyzer: FFTAnalyzer
    let chordDetector: ChordDetector
    @Bindable var engine: AudioEngineManager

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 20) {
                VStack(spacing: Spacing.lg) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.title2)
                                    .foregroundStyle(.cyan)

                                Text("Audio Analysis")
                                    .font(.title2.bold())
                            }

                            Text("Real-time frequency and pitch analysis powered by Accelerate framework")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .glassEffect(.regular.tint(.cyan.opacity(0.1)), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, Spacing.lg)

                    // Spectrum Analyzer (FFT)
                    GlassCard(cornerRadius: CornerRadius.lg) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Real-Time Spectrum Analysis", systemImage: "waveform.path.ecg")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Fast Fourier Transform (FFT) decomposes your audio into frequency components")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            FFTSpectrumView(analyzer: fftAnalyzer)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)

                    // Chord Detection
                    GlassCard(cornerRadius: CornerRadius.lg) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("AI Chord Detection", systemImage: "pianokeys")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Pitch detection using autocorrelation algorithm identifies notes and chords")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ChordDetectorView(detector: chordDetector)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)

                    // Educational note
                    TechExplanationCard()
                        .padding(.horizontal, Spacing.lg)
                }
                .padding(.vertical, Spacing.md)
            }
        }
    }
}

// MARK: - Tech Explanation Card

struct TechExplanationCard: View {
    var body: some View {
        GlassCard(tint: Color.riffPrimary.opacity(0.3), cornerRadius: CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("The Science Behind", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.riffPrimary)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    TechBullet(
                        framework: "Foundation Models",
                        description: "On-device LLM for natural language to DSP parameter conversion"
                    )

                    TechBullet(
                        framework: "Accelerate (vDSP)",
                        description: "Apple's high-performance math library for FFT calculations"
                    )

                    TechBullet(
                        framework: "Vision Framework",
                        description: "Real-time face landmark detection for gesture recognition"
                    )

                    TechBullet(
                        framework: "Autocorrelation",
                        description: "Signal processing algorithm to detect fundamental pitch frequency"
                    )

                    TechBullet(
                        framework: "Swift Charts",
                        description: "Native data visualization for spectrum display"
                    )
                }
            }
        }
    }
}

struct TechBullet: View {
    let framework: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.riffPrimary)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(framework)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.15)), in: RoundedRectangle(cornerRadius: 6))

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Glass Top Bar View

struct GlassTopBarView: View {
    @Bindable var engine: AudioEngineManager
    let chordDetector: ChordDetector?
    @Binding var showingSettings: Bool
    @Binding var showingPresets: Bool

    init(engine: AudioEngineManager, chordDetector: ChordDetector? = nil, showingSettings: Binding<Bool>, showingPresets: Binding<Bool>) {
        self.engine = engine
        self.chordDetector = chordDetector
        self._showingSettings = showingSettings
        self._showingPresets = showingPresets
    }

    var body: some View {
        // One container wraps everything so all toolbar pills / buttons
        // fuse into a single liquid glass bar.
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 16) {
                // Logo with custom RiffNode icon
                HStack(spacing: 12) {
                    Image("RiffNodeLogo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .foregroundStyle(Color.riffPrimary)

                    Text("RiffNode")
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Audio Input Device indicator
                GlassAudioInputBadge(
                    deviceName: engine.currentInputDeviceName,
                    deviceType: engine.currentInputDeviceType,
                    onRefresh: {
                        engine.refreshInputDevices()
                    }
                )

                // Presets button
                Button {
                    showingPresets = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill")
                        Text("Presets")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)

                // Engine status
                GlassStatusIndicator(
                    status: engine.isRunning ? .active : .inactive,
                    label: engine.isRunning ? "Running" : "Stopped"
                )

                // Play/Stop + Settings – already inside the outer container
                // so they fuse with the status indicator next to them
                GlassIconButton(
                    icon: engine.isRunning ? "stop.fill" : "play.fill",
                    tint: engine.isRunning ? .red : .green
                ) {
                    if engine.isRunning {
                        engine.stop()
                    } else {
                        try? engine.start()
                    }
                }

                GlassIconButton(icon: "gear", tint: .primary) {
                    showingSettings = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            // The outer glass shape covers the whole bar
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Glass Audio Input Badge

struct GlassAudioInputBadge: View {
    let deviceName: String
    let deviceType: AudioInputDeviceType
    let onRefresh: () -> Void

    var body: some View {
        Button(action: onRefresh) {
            HStack(spacing: 8) {
                // Device type icon
                ZStack {
                    Circle()
                        .fill(deviceType.color.opacity(0.2))
                        .frame(width: 28, height: 28)

                    Image(systemName: deviceType.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(deviceType.color)
                }

                // Device info
                VStack(alignment: .leading, spacing: 1) {
                    Text(deviceType.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(formatDeviceName(deviceName))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                // Signal indicator
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundStyle(deviceType == .none ? Color.secondary : Color.green)
                    .symbolEffect(.pulse, options: .repeating, value: deviceType != .none)
            }
        }
        .buttonStyle(.plain)
        .glassPill()
        .help("Click to refresh audio input devices")
    }

    private func formatDeviceName(_ name: String) -> String {
        var displayName = name
            .replacingOccurrences(of: "MacBook Pro Microphone", with: "MacBook Pro Mic")
            .replacingOccurrences(of: "Built-in Microphone", with: "Built-in Mic")
            .replacingOccurrences(of: "USB Audio Device", with: "USB Audio")

        if displayName.count > 22 {
            displayName = String(displayName.prefix(20)) + "..."
        }
        return displayName
    }
}

// MARK: - Preset Picker View

struct PresetPickerView: View {
    @Bindable var engine: AudioEngineManager
    let presetService: PresetProviding
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: EffectPreset.PresetCategory?
    @State private var selectedPreset: EffectPreset?

    private var filteredPresets: [EffectPreset] {
        if let category = selectedCategory {
            return presetService.presets(for: category)
        }
        return presetService.presets
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: 0) {
                    GlassPresetCategoryBar(selectedCategory: $selectedCategory)

                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(filteredPresets) { preset in
                                GlassPresetCard(
                                    preset: preset,
                                    isSelected: selectedPreset?.id == preset.id
                                ) {
                                    selectedPreset = preset
                                    engine.applyPreset(preset)
                                    dismiss()
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Effect Presets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 500)
        #endif
    }
}

// MARK: - Glass Preset Category Bar

struct GlassPresetCategoryBar: View {
    @Binding var selectedCategory: EffectPreset.PresetCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 8) {
                    Button("All") {
                        withAnimation { selectedCategory = nil }
                    }
                    .buttonStyle(GlassPillStyle(isSelected: selectedCategory == nil, tint: .accentColor))

                    ForEach(EffectPreset.PresetCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) {
                            withAnimation { selectedCategory = category }
                        }
                        .buttonStyle(GlassPillStyle(isSelected: selectedCategory == category, tint: category.color))
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Glass Preset Card

struct GlassPresetCard: View {
    let preset: EffectPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(preset.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(preset.category.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(preset.category.color)
                        .glassEffect(.regular.tint(preset.category.color.opacity(0.2)), in: Capsule())
                }

                Text(preset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Effect chain preview
                HStack(spacing: 4) {
                    ForEach(Array(preset.effects.enumerated()), id: \.offset) { _, effect in
                        Text(effect.type.abbreviation)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(effect.type.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .glassEffect(.regular.tint(effect.type.color.opacity(0.25)), in: Capsule())
                    }
                }
            }
            .glassCard(
                tint: isSelected ? preset.category.color : nil,
                cornerRadius: 16,
                padding: 16
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings View
// Apple-style settings with proper section grouping and professional appearance

struct SettingsView: View {
    @Bindable var engine: AudioEngineManager
    @Environment(\.dismiss) private var dismiss

    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Audio Engine Section
                        SettingsSection(title: "Audio Engine") {
                            SettingsRow(
                                icon: "waveform.circle.fill",
                                iconColor: engine.isRunning ? .green : .red,
                                title: "Engine Status",
                                subtitle: engine.isRunning ? "Audio processing active" : "Engine stopped"
                            ) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(engine.isRunning ? Color.green : Color.red)
                                        .frame(width: 10, height: 10)
                                    Text(engine.isRunning ? "Running" : "Stopped")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(engine.isRunning ? .green : .red)
                                }
                            }

                            GlassDivider()

                            SettingsRow(
                                icon: "mic.fill",
                                iconColor: engine.hasPermission ? .green : .orange,
                                title: "Microphone Access",
                                subtitle: engine.hasPermission ? "Permission granted" : "Permission required"
                            ) {
                                Image(systemName: engine.hasPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(engine.hasPermission ? .green : .orange)
                            }
                        }

                        // Audio Input Section
                        SettingsSection(title: "Audio Input") {
                            SettingsRow(
                                icon: engine.currentInputDeviceType.icon,
                                iconColor: engine.currentInputDeviceType.color,
                                title: "Input Device",
                                subtitle: engine.currentInputDeviceName
                            ) {
                                Button {
                                    engine.refreshInputDevices()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            GlassDivider()

                            SettingsRow(
                                icon: "slider.horizontal.3",
                                iconColor: .purple,
                                title: "Input Level",
                                subtitle: "Current signal strength"
                            ) {
                                // Mini level meter
                                HStack(spacing: 2) {
                                    ForEach(0..<8, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(
                                                i < Int(engine.inputLevel * 8)
                                                    ? (i < 6 ? Color.green : Color.orange)
                                                    : Color.primary.opacity(0.15)
                                            )
                                            .frame(width: 4, height: 16)
                                    }
                                }
                            }
                        }

                        // Effects Chain Section
                        SettingsSection(title: "Effects Chain") {
                            SettingsRow(
                                icon: "square.stack.3d.up.fill",
                                iconColor: .riffPrimary,
                                title: "Active Effects",
                                subtitle: "\(engine.effectsChain.filter { $0.isEnabled }.count) of \(engine.effectsChain.count) enabled"
                            ) {
                                Text("\(engine.effectsChain.filter { $0.isEnabled }.count)")
                                    .font(.title2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Color.riffPrimary)
                            }

                            GlassDivider()

                            SettingsRow(
                                icon: "arrow.counterclockwise",
                                iconColor: .orange,
                                title: "Reset Effects",
                                subtitle: "Restore default chain"
                            ) {
                                Button("Reset") {
                                    showResetConfirmation = true
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 14)
                                .glassEffect(.regular.tint(.orange.opacity(0.15)), in: Capsule())
                                .buttonStyle(.plain)
                            }
                        }

                        // About Section
                        SettingsSection(title: "About") {
                            // App Info Header
                            HStack(spacing: 16) {
                                Image("RiffNodeLogo")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                                    .foregroundStyle(Color.riffPrimary)
                                    .padding(12)
                                    .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.12)), in: RoundedRectangle(cornerRadius: 16))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("RiffNode")
                                        .font(.title2.bold())

                                    Text("Version 1.0")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Text("Swift Student Challenge 2026")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()
                            }
                            .padding(.bottom, Spacing.sm)

                            GlassDivider()

                            SettingsInfoRow(label: "Built with", value: "Swift 6 & SwiftUI")
                            GlassDivider()
                            SettingsInfoRow(label: "UI Framework", value: "iOS 26 Liquid Glass")
                            GlassDivider()
                            SettingsInfoRow(label: "Audio Engine", value: "AVAudioEngine")
                            GlassDivider()
                            SettingsInfoRow(label: "Architecture", value: "Clean Architecture")
                        }

                        // Description
                        VStack(spacing: Spacing.sm) {
                            Text("Guitar Effects Playground")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("RiffNode is a visual guitar effects playground. Connect your guitar through an audio interface and explore a world of effects with AI-powered tone assistance, real-time spectrum analysis, and hands-free gesture control.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, Spacing.lg)
                    }
                    .padding(.vertical, Spacing.md)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset Effects Chain?", isPresented: $showResetConfirmation) {
                Button("Reset to Default", role: .destructive) {
                    // Reset effects chain to default
                    engine.effectsChain.forEach { effect in
                        if !effect.isEnabled {
                            engine.toggleEffect(effect)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will enable all effects and reset their parameters to default values.")
            }
        }
        #if os(macOS)
        .frame(width: 450, height: 650)
        #endif
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.lg + 4)

            VStack(spacing: 0) {
                content
            }
            .padding(Spacing.md)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, Spacing.lg)
        }
    }
}

// MARK: - Settings Row

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            // Labels
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Trailing content
            trailing
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Info Row

private struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Settings Section Header

private struct SettingsSectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.bottom, Spacing.xs)
    }
}

// MARK: - Glass Status Row

struct GlassStatusRow: View {
    let label: String
    let value: String
    let isPositive: Bool

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isPositive ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(value)
                    .foregroundStyle(isPositive ? .green : .red)
            }
        }
    }
}

// MARK: - Chord Suggestion Chip
// Appears above the chatbot FAB when a chord is detected with high confidence.
// Lets the user one-tap into an AI tone suggestion without interrupting their playing.

struct ChordSuggestionChip: View {
    let suggestion: String
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.purple)

            Text(suggestion)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button(action: onApply) {
                Text("Apply")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.purple.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.purple.opacity(0.12)), in: Capsule())
    }
}

// MARK: - Gesture Control Pill
// Compact toggle in the left panel. Shows face-detection status when active.

struct GestureControlPill: View {
    @Bindable var controller: VisionGestureController
    @Binding var isEnabled: Bool

    var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isEnabled ? .purple : .secondary)
                    .symbolEffect(.pulse, options: .repeating, value: isEnabled && controller.faceDetected)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Gesture Control")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                Spacer()

                Circle()
                    .fill(statusColor.opacity(0.8))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(
                .regular.tint(isEnabled ? .purple.opacity(0.1) : .clear),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        guard isEnabled else { return "Tap to enable" }
        return controller.faceDetected ? "Face Detected" : "Looking for face..."
    }

    private var statusColor: Color {
        guard isEnabled else { return .secondary }
        return controller.faceDetected ? .green : .orange
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
