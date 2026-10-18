import SwiftUI
import Observation

// MARK: - Main View Model
// Owns the main screen's services and the glue logic between them:
// audio analysis wiring, head-gesture handling, chord → AI tone suggestions,
// and the events the notch announces. MainInterfaceView only renders this state.

@Observable
@MainActor
final class MainViewModel {

    enum MainTab: String, CaseIterable {
        case pedalboard = "Pedalboard"
        case parametricEQ = "EQ & Tone"
        case learnEffects = "Learn"

        var icon: String {
            switch self {
            case .pedalboard: return "slider.horizontal.below.square.filled.and.square"
            case .parametricEQ: return "slider.horizontal.3"
            case .learnEffects: return "text.book.closed"
            }
        }
    }

    /// Identity + bypass state of the chain, used to describe what changed.
    struct ChainSnapshot: Equatable {
        let ids: [UUID]
        let enabled: [Bool]
    }

    // MARK: - Dependencies

    let engine: any AudioManaging
    let presetService: PresetProviding

    let fftAnalyzer: any SpectrumAnalyzing
    /// USB / Bluetooth MIDI foot controllers.
    let midi: any FootswitchListening
    let chordDetector: any ChordAnalyzing
    let gestureController: any GestureControlling
    let semanticProcessor: any ToneAssisting
    let musicApp: any MusicAppControlling
    let songAnalyzer: any SongAnalyzing
    let effectGuide: any EffectGuideServiceProtocol
    let chatbotController = AIChatbotController()
    let performanceController = PerformanceModeController()
    let notch = RiffNotchController()

    // MARK: - UI State

    var selectedTab: MainTab = .pedalboard
    var showingSettings = false
    var showingPresets = false
    var showingChatbot = false
    var showingPerformanceMode = false
    var gestureControlEnabled = false

    // MARK: - Chord AI Bridge State

    private(set) var chordAISuggestion: String?
    private(set) var chordAIPrompt: String?
    @ObservationIgnored private var lastSuggestedChord = ""
    @ObservationIgnored private var chordSuggestionTask: Task<Void, Never>?

    init(dependencies d: AppDependencies) {
        engine = d.engine
        presetService = d.presets
        fftAnalyzer = d.spectrum
        midi = d.footswitch
        chordDetector = d.chords
        gestureController = d.gestures
        semanticProcessor = d.toneAssistant
        musicApp = d.musicApp
        songAnalyzer = d.songAnalyzer
        effectGuide = d.effectGuide
    }

    // MARK: - Computed Properties

    var chainSnapshot: ChainSnapshot {
        ChainSnapshot(
            ids: engine.effectsChain.map(\.id),
            enabled: engine.effectsChain.map(\.isEnabled)
        )
    }

    var currentPresetName: String {
        engine.currentPreset?.name ?? "Custom Tone"
    }

    // MARK: - Lifecycle

    func onAppear() {
        midi.onEvent = { [weak self] event in self?.handleFootswitch(event) }
        midi.start()
        gestureController.onGestureDetected = { [weak self] gesture in
            self?.handleGesture(gesture)
        }
        // Your mouth is the wah pedal: closed = heel down (dark), open = toe down (bright)
        gestureController.onMouthOpenValueChanged = { [engine, performanceController] value in
            engine.setWah(value)
            performanceController.updateWahPosition(value)
        }
        engine.onAudioSamplesAvailable = { [engine, fftAnalyzer, chordDetector] samples in
            if samples.count >= 2048 {
                // Analysers default to 44.1 kHz; most devices run at 48 kHz, which would
                // shift every detected pitch by ~1.5 semitones.
                let sampleRate = engine.analysisSampleRate
                if fftAnalyzer.sampleRate != sampleRate { fftAnalyzer.sampleRate = sampleRate }
                if chordDetector.sampleRate != Float(sampleRate) { chordDetector.sampleRate = Float(sampleRate) }
                fftAnalyzer.analyze(samples: samples)
                chordDetector.analyze(samples: samples)
            }
        }
    }

    func setGestureControl(enabled: Bool) async {
        if enabled {
            try? await gestureController.start()
            gestureControlEnabled = gestureController.isRunning
            if gestureController.isRunning {
                notch.announce(icon: "eye.fill", title: "Gesture Control On",
                               detail: "Nod to switch presets · open your mouth to wah", tint: .purple, priority: .engine)
            }
        } else {
            gestureController.stop()
            engine.setWah(nil)
        }
    }

    // MARK: - Footswitch

    private func handleFootswitch(_ event: FootswitchEvent) {
        switch event {
        case .programChange(let number):
            let presets = presetService.presets
            guard presets.indices.contains(number) else { return }
            performanceController.currentPresetIndex = number
            engine.applyPreset(presets[number])
        case .nextPreset: stepPreset(by: 1)
        case .previousPreset: stepPreset(by: -1)
        case .looper: engine.looperControls.press()
        case .tunerMute: engine.isTunerMuted.toggle()
        }
    }

    // MARK: - Transport & Presets

    func toggleEngine() {
        if engine.isRunning {
            engine.stop()
        } else {
            try? engine.start()
        }
    }

    /// Moves through the preset list (wrapping). Used by head nods and the notch.
    func stepPreset(by offset: Int) {
        let presets = presetService.presets
        guard !presets.isEmpty else { return }
        let index = (performanceController.currentPresetIndex + offset + presets.count) % presets.count
        performanceController.currentPresetIndex = index
        engine.applyPreset(presets[index])
    }

    func toggle(_ effect: EffectNode) {
        engine.toggleEffect(effect)
    }

    // MARK: - Gestures

    func handleGesture(_ gesture: FaceGesture) {
        if performanceController.isActive {
            performanceController.handleGesture(gesture, engine: engine, presets: presetService.presets)
            return
        }
        switch gesture {
        case .headNodDown:
            stepPreset(by: 1)
        case .headNodUp:
            stepPreset(by: -1)
        case .headTiltLeft:
            engine.effectsChain.filter { $0.isEnabled }.forEach { engine.toggleEffect($0) }
        case .headTiltRight:
            engine.effectsChain.filter { !$0.isEnabled }.forEach { engine.toggleEffect($0) }
        case .mouthOpen:
            break  // the mouth drives the wah continuously; opening it shouldn't also flip a pedal
        case .eyebrowRaise:
            if let comp = engine.effectsChain.first(where: { $0.type == .compressor }) {
                engine.toggleEffect(comp)
            }
        }

        let detail: String
        switch gesture {
        case .headNodDown, .headNodUp: detail = currentPresetName
        default: detail = gesture.defaultAction
        }
        notch.announce(icon: gesture.icon, title: gesture.rawValue, detail: detail,
                       tint: .purple, priority: .gesture)
    }

    // MARK: - Notch Announcements

    func presetDidApply() {
        guard let preset = engine.currentPreset else { return }
        notch.announce(icon: preset.icon, title: preset.name,
                       detail: preset.category.rawValue, tint: preset.category.color, priority: .preset)
    }

    func chainDidChange(from old: ChainSnapshot, to new: ChainSnapshot) {
        guard engine.auditionEffect == nil else { return }  // Learn-tab previews aren't edits
        if old.ids == new.ids {
            let changed = zip(engine.effectsChain, zip(old.enabled, new.enabled))
                .filter { $1.0 != $1.1 }
                .map(\.0)
            guard let effect = changed.first else { return }
            if changed.count == 1 {
                notch.announce(icon: effect.type.icon, title: effect.type.rawValue,
                               detail: effect.isEnabled ? "On" : "Bypassed",
                               tint: effect.isEnabled ? effect.type.color : .gray, priority: .pedal)
            } else {
                let active = new.enabled.filter { $0 }.count
                notch.announce(icon: "square.stack.3d.up.fill", title: "\(changed.count) pedals switched",
                               detail: "\(active) active", priority: .pedal)
            }
        } else {
            let active = new.enabled.filter { $0 }.count
            notch.announce(icon: "wand.and.stars", title: "Tone updated",
                           detail: "\(active) of \(new.ids.count) pedals active", priority: .chain)
        }
    }

    func engineRunningDidChange(_ isRunning: Bool) {
        if !isRunning { chordDetector.reset() }
        notch.announce(icon: isRunning ? "waveform" : "stop.fill",
                       title: isRunning ? "Engine Live" : "Engine Stopped",
                       detail: engine.currentInputDeviceName,
                       tint: isRunning ? .green : .red, priority: .engine)
    }

    func demoRiffDidChange(_ isPlaying: Bool) {
        chordDetector.reset()
        notch.announce(icon: isPlaying ? "guitars.fill" : "stop.fill",
                       title: isPlaying ? "Demo Riff" : "Demo Riff Stopped",
                       detail: isPlaying ? "Playing through your pedals" : nil,
                       tint: .orange, priority: .engine)
    }

    // MARK: - Chord AI Bridge

    func chordDidChange(_ newChord: String) {
        // Only suggest for chords the player is actually holding – not single notes,
        // and not the demo riff, which changes chord every bar on its own
        guard newChord != "—", newChord != lastSuggestedChord,
              !newChord.hasSuffix("note"), !engine.isDemoRiffPlaying, engine.auditionEffect == nil else {
            chordSuggestionTask?.cancel()
            if newChord == "—" || engine.isDemoRiffPlaying { withAnimation { chordAISuggestion = nil } }
            return
        }
        chordSuggestionTask?.cancel()
        chordSuggestionTask = Task { [weak self] in
            // Debounce: wait 2s for chord to stabilise
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            guard self.chordDetector.confidence > 0.55,
                  self.chordDetector.detectedChord == newChord else { return }
            withAnimation(.spring(duration: 0.4)) {
                self.chordAISuggestion = Self.displayText(for: newChord)
                self.chordAIPrompt = Self.aiPrompt(for: newChord)
            }
        }
    }

    func applyChordSuggestion() {
        guard let prompt = chordAIPrompt else { return }
        chatbotController.inputText = prompt
        showingChatbot = true
        dismissChordSuggestion()
    }

    func dismissChordSuggestion() {
        withAnimation(.spring(duration: 0.3)) { chordAISuggestion = nil }
        lastSuggestedChord = chordDetector.detectedChord
    }

    private static func displayText(for chord: String) -> String {
        if chord.contains("Major") { return "Detected \(chord) — clean tone?" }
        if chord.contains("7")     { return "Detected \(chord) — bluesy drive?" }
        if chord.contains("5")     { return "Detected \(chord) — rock crunch?" }
        if chord.contains("m")     { return "Detected \(chord) — warm blues?" }
        return "Detected \(chord) — AI tone?"
    }

    private static func aiPrompt(for chord: String) -> String {
        if chord.contains("Major") { return "bright clean tone for playing \(chord)" }
        if chord.contains("7")     { return "bluesy overdrive for \(chord)" }
        if chord.contains("5")     { return "heavy rock crunch for \(chord) power chord" }
        if chord.contains("m")     { return "warm blues tone for \(chord)" }
        return "suggest a matching tone for playing \(chord)"
    }
}
