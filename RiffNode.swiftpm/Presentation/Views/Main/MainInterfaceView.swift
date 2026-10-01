import SwiftUI

// MARK: - Main Interface View
// Pure rendering: all services and glue logic live in MainViewModel.

struct MainInterfaceView: View {
    @State private var viewModel: MainViewModel
    @State private var containerWidth: CGFloat = 1200

    /// Narrower side panel on smaller windows (iPad portrait, split view)
    /// so the pedalboard keeps room for more pedals.
    private var sidePanelWidth: CGFloat {
        containerWidth < 1100 ? 320 : 380
    }

    init(engine: AudioEngineManager, presetService: PresetProviding) {
        _viewModel = State(initialValue: MainViewModel(engine: engine, presetService: presetService))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let engine = viewModel.engine

        VStack(spacing: 0) {
            // Floating glass top bar – sits just below the notch
            GlassTopBarView(
                engine: engine,
                chordDetector: viewModel.chordDetector,
                showingSettings: $viewModel.showingSettings,
                showingPresets: $viewModel.showingPresets
            )
            .padding(.horizontal, Spacing.md)
            .padding(.top, RiffNotchMetrics.closedHeight + Spacing.xs)

            HStack(spacing: Spacing.md) {
                // Left panel – all glass cards sit inside one container
                // so neighbouring cards fuse into a single liquid shape
                ScrollView {
                    GlassEffectContainer(spacing: 16) {
                        VStack(spacing: Spacing.md) {
                            DemoRiffPill(engine: engine)

                            AudioVisualizationPanel(engine: engine)

                            // Spectrum + chord badge fuse with the cards above / below
                            MiniSpectrumIndicator(analyzer: viewModel.fftAnalyzer)

                            CompactChordBadge(detector: viewModel.chordDetector)

                            BackingTrackView(engine: engine)

                            GestureControlPill(
                                controller: viewModel.gestureController,
                                isEnabled: $viewModel.gestureControlEnabled
                            )
                        }
                    }
                    .padding(Spacing.md)
                }
                .scrollIndicators(.hidden)
                .frame(width: sidePanelWidth)

                // Right panel with tab switching
                VStack(spacing: 0) {
                    GlassTabBar(selection: $viewModel.selectedTab, tint: Color.riffPrimary) { tab in
                        tab.icon
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)

                    Group {
                        switch viewModel.selectedTab {
                        case .pedalboard:
                            EffectsChainView(engine: engine)
                        case .parametricEQ:
                            ScrollView {
                                ParametricEQView(engine: engine, analyzer: viewModel.fftAnalyzer)
                                    .padding()
                            }
                        case .aiTools:
                            AIToolsView(
                                fftAnalyzer: viewModel.fftAnalyzer,
                                chordDetector: viewModel.chordDetector,
                                engine: engine
                            )
                        case .learnEffects:
                            EffectGuideView(engine: engine)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .animation(.smooth(duration: 0.25), value: viewModel.selectedTab)
                }
                .frame(maxWidth: .infinity)
                .padding(.trailing, Spacing.md)
            }
            .padding(.top, Spacing.sm)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView(engine: engine)
        }
        .sheet(isPresented: $viewModel.showingPresets) {
            PresetPickerView(engine: engine, presetService: viewModel.presetService)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 400, minHeight: 500)
                #endif
        }
        // AI Chatbot Overlay + Chord Suggestion Chip
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: Spacing.sm) {
                if let suggestion = viewModel.chordAISuggestion {
                    ChordSuggestionChip(
                        suggestion: suggestion,
                        onApply: viewModel.applyChordSuggestion,
                        onDismiss: viewModel.dismissChordSuggestion
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                AIChatbotOverlayView(
                    controller: viewModel.chatbotController,
                    processor: viewModel.semanticProcessor,
                    engine: engine,
                    isExpanded: $viewModel.showingChatbot
                )
            }
            .padding(Spacing.lg)
        }
        // Dynamic Island–style notch: live status, event banners, quick controls
        .overlay(alignment: .top) {
            RiffNotchHost(viewModel: viewModel)
        }
        // Performance Mode - fullscreen pedalboard with gesture control
        .fullScreenCover(isPresented: $viewModel.showingPerformanceMode) {
            PerformanceModeView(
                engine: engine,
                gestureController: viewModel.gestureController,
                controller: viewModel.performanceController,
                presets: viewModel.presetService.presets,
                onExit: { viewModel.showingPerformanceMode = false }
            )
        }
        .onChange(of: viewModel.chordDetector.detectedChord) { _, newChord in
            viewModel.chordDidChange(newChord)
        }
        .onChange(of: viewModel.gestureControlEnabled) { _, enabled in
            Task { await viewModel.setGestureControl(enabled: enabled) }
        }
        .onChange(of: engine.presetApplyCount) { _, _ in
            viewModel.presetDidApply()
        }
        .onChange(of: viewModel.chainSnapshot) { old, new in
            viewModel.chainDidChange(from: old, to: new)
        }
        .onChange(of: engine.isRunning) { _, isRunning in
            viewModel.engineRunningDidChange(isRunning)
        }
        .onChange(of: engine.isDemoRiffPlaying) { _, isPlaying in
            viewModel.demoRiffDidChange(isPlaying)
        }
        .background { MainKeyboardShortcuts(viewModel: viewModel) }
        .onReceive(NotificationCenter.default.publisher(for: .enterPerformanceMode)) { _ in
            viewModel.showingPerformanceMode = true
        }
        .onAppear {
            viewModel.onAppear()
        }
    }
}

// MARK: - Keyboard Shortcuts
// Hardware-keyboard shortcuts for Mac and iPad. Hold ⌘ on iPad to see them.

private struct MainKeyboardShortcuts: View {
    let viewModel: MainViewModel

    var body: some View {
        Group {
            Button("Start or Stop Engine", action: viewModel.toggleEngine)
                .keyboardShortcut(.return, modifiers: .command)
            Button("Play or Stop Demo Riff") { viewModel.engine.toggleDemoRiff() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Next Preset") { viewModel.stepPreset(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Preset") { viewModel.stepPreset(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Quick Controls", action: viewModel.notch.toggle)
                .keyboardShortcut("k", modifiers: .command)
            Button("Tone Assistant") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewModel.showingChatbot.toggle() }
            }
            .keyboardShortcut("j", modifiers: .command)
            ForEach(Array(MainViewModel.MainTab.allCases.enumerated()), id: \.offset) { index, tab in
                Button(tab.rawValue) { viewModel.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
