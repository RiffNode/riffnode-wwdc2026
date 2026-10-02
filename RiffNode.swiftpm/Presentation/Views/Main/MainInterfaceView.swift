import SwiftUI

// MARK: - Main Interface View
// Pure rendering: all services and glue logic live in MainViewModel.

struct MainInterfaceView: View {
    @State private var viewModel: MainViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init(engine: AudioEngineManager, presetService: PresetProviding) {
        _viewModel = State(initialValue: MainViewModel(engine: engine, presetService: presetService))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let engine = viewModel.engine

        // Pro-app layout: sidebar (sections + live input + jam track), content in the
        // middle, and the Tone Assistant as an inspector on the right.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RiffSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } detail: {
            NavigationStack {
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
                        AnalyzeView(
                            fftAnalyzer: viewModel.fftAnalyzer,
                            chordDetector: viewModel.chordDetector,
                            engine: engine,
                            onOpenEQ: { viewModel.selectedTab = .parametricEQ }
                        )
                    case .learnEffects:
                        EffectGuideView(engine: engine)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.riffBackground)
                .navigationTitle(viewModel.selectedTab.rawValue)
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar { mainToolbar(viewModel: viewModel) }
            }
            .inspector(isPresented: $viewModel.showingChatbot) {
                AIChatbotOverlayView(
                    controller: viewModel.chatbotController,
                    processor: viewModel.semanticProcessor,
                    engine: engine,
                    isExpanded: $viewModel.showingChatbot,
                    presentation: .inspector
                )
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView(engine: engine)
        }
        .sheet(isPresented: $viewModel.showingPresets) {
            PresetPickerView(engine: engine, presetService: viewModel.presetService)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 400, minHeight: 500)
                #endif
        }
        // Chord → tone suggestion, bottom-trailing above the content
        .overlay(alignment: .bottomTrailing) {
            if let suggestion = viewModel.chordAISuggestion {
                ChordSuggestionChip(
                    suggestion: suggestion,
                    onApply: viewModel.applyChordSuggestion,
                    onDismiss: viewModel.dismissChordSuggestion
                )
                .padding(Spacing.lg)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
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

// MARK: - Toolbar

@MainActor @ToolbarContentBuilder
private func mainToolbar(viewModel: MainViewModel) -> some ToolbarContent {
    let engine = viewModel.engine
    ToolbarItemGroup(placement: .primaryAction) {
        Button {
            viewModel.toggleEngine()
        } label: {
            Label(engine.isRunning ? "Stop Engine" : "Start Engine",
                  systemImage: engine.isRunning ? "stop.fill" : "play.fill")
        }
        .help(engine.isRunning ? "Stop the audio engine (⌘↩)" : "Start the audio engine (⌘↩)")

        Button {
            viewModel.showingPresets = true
        } label: {
            Label("Presets", systemImage: "square.stack.3d.up")
        }

        Button {
            viewModel.showingSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
        }

        Button {
            withAnimation { viewModel.showingChatbot.toggle() }
        } label: {
            Label("Tone Assistant", systemImage: "apple.intelligence")
        }
        .help("Tone Assistant (⌘J)")
    }
}

// MARK: - Sidebar

private struct RiffSidebar: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        let engine = viewModel.engine
        List(selection: Binding(
            get: { Optional(viewModel.selectedTab) },
            set: { if let tab = $0 { viewModel.selectedTab = tab } }
        )) {
            Section {
                ForEach(MainViewModel.MainTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }

            Section("Input") {
                InputSourceCard(engine: engine, chordDetector: viewModel.chordDetector)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("Jam Track") {
                BackingTrackView(engine: engine)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("Hands-free") {
                GestureControlPill(
                    controller: viewModel.gestureController,
                    isEnabled: $viewModel.gestureControlEnabled
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("RiffNode")
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
