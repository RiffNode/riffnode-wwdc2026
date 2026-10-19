import Foundation

// MARK: - View Model Tests
// MainViewModel built from fakes: AppDependencies holds only Domain protocols, so the
// main screen's glue – footswitch, head gestures, presets, notch, undo seeding – runs
// here without an audio engine, a camera or MIDI hardware.

// MARK: - Fakes

@MainActor
final class FakeEngine: AudioManaging {
    // Engine
    var isRunning = false
    var hasPermission = true
    var errorMessage: String?
    var currentInputDeviceName = "Test Input"
    var currentInputDeviceType = AudioInputDeviceType.usbAudioInterface
    func requestMicrophonePermission() async {}
    func setupEngine() async throws {}
    func enableLiveInput() async throws {}
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
    func refreshInputDevices() {}

    // Levels, analysis, latency
    var inputLevel: Float = 0
    var outputLevel: Float = 0
    var analysisSampleRate: Double = 48_000
    var onAudioSamplesAvailable: (@MainActor ([Float]) -> Void)?
    private(set) var currentPreset: EffectPreset?
    var roundTripLatencyMs: Double = 0
    var bufferDurationMs: Double = 0
    var isBluetoothOutput = false
    func refreshLatency() {}

    // Chain
    var isPedalboardBypassed = false
    var effectsChain: [EffectNode] = []
    var presetApplyCount = 0
    func addEffect(_ type: EffectType) { effectsChain.append(EffectNode(type: type)) }
    func removeEffect(at index: Int) { effectsChain.remove(at: index) }
    func moveEffect(from source: IndexSet, to destination: Int) { effectsChain.move(fromOffsets: source, toOffset: destination) }
    func toggleEffect(_ effect: EffectNode) { effect.isEnabled.toggle() }
    func updateEffectParameter(_ effect: EffectNode, key: String, value: Float) { effect.parameters[key] = value }
    func setPedalModel(_ effect: EffectNode, modelID: String) { effect.modelID = modelID }
    func clearEffects() { effectsChain = [] }
    func resetEffectsToDefaults() {}
    func applyPreset(_ preset: EffectPreset) {
        currentPreset = preset
        effectsChain = preset.effects.map { $0.toEffectNode() }
        presetApplyCount += 1
    }
    func ensureEffectInChain(_ type: EffectType) { if !effectsChain.contains(where: { $0.type == type }) { addEffect(type) } }
    func rebuildEffectsChain() {}

    // Amp, input, EQ
    var ampSettings = AmpSettings()
    func ampResponse(at frequencies: [Float]) -> [Float] { frequencies.map { _ in 0 } }
    var cabinetIRName: String?
    func loadCabinetIR(from url: URL) async throws {}
    var neuralModelName: String?
    func loadNeuralModel(from url: URL) async throws {}
    var inputSettings = InputSettings()
    func inputResponse(at frequencies: [Float]) -> [Float] { frequencies.map { _ in 0 } }
    var isTunerMuted = false
    var parametricEQBands: [EQBand] = []
    func resetEQ() {}
    func applyToneSuggestion(_ suggestion: ToneSuggestion) {}

    // Sharing
    func makeToneDocument(named name: String) -> ToneDocument {
        ToneDocument(name: name, chain: effectsChain, amp: ampSettings, eqBands: parametricEQBands, input: inputSettings)
    }
    func applyToneDocument(_ document: ToneDocument) {
        effectsChain = document.effectNodes
        inputSettings = document.inputSettings(over: inputSettings)
    }

    // Demo riff
    var selectedDemoRiff = DemoRiff.allCases[0]
    var demoRecordings: [String] = []
    var selectedDemoRecording: String?
    func importDemoRecordings(from urls: [URL]) throws {}
    func playDemoRecording(named name: String) {}
    func removeDemoRecording(named name: String) {}
    var isDemoRiffPlaying = false
    var canPlayDemoRiff = true
    func toggleDemoRiff() { isDemoRiffPlaying.toggle() }
    func startDemoRiff() { isDemoRiffPlaying = true }
    func stopDemoRiff() { isDemoRiffPlaying = false }

    // Audition, probe, expression
    var auditionEffect: EffectType?
    var auditionModelID: String?
    var isAuditionBypassed = false
    func startAudition(_ type: EffectType, modelID: String?) { auditionEffect = type; auditionModelID = modelID }
    func setAuditionBypassed(_ bypassed: Bool) { isAuditionBypassed = bypassed }
    func stopAudition() { auditionEffect = nil }
    func probe(_ effect: EffectNode, owner: UUID) {}
    func stopProbe(owner: UUID) {}
    func probeAnalysis() -> SignalAnalysis { SignalAnalysis() }
    private(set) var wahPositions: [Float?] = []
    func setWah(_ position: Float?) { wahPositions.append(position) }
    func setExpressionValue(_ value: Float, for effectType: EffectType) {}

    // Practice tools
    let looper = FakeLooper()
    var playAlong: any BackingTrackManaging { fatalError("not used by MainViewModel") }
    var metronomeControls: any MetronomeControlling { fatalError("not used by MainViewModel") }
    var looperControls: any LooperControlling { looper }
}

@MainActor
final class FakeLooper: LooperControlling {
    private(set) var presses = 0
    var state = LooperState.empty
    var loopDuration: TimeInterval = 0
    var canUndo = false
    var isReady = true
    func press() { presses += 1 }
    func stop() {}
    func undo() {}
    func clear() {}
}

struct FakePresets: PresetProviding {
    let presets: [EffectPreset] = ["Clean", "Crunch", "Lead"].map { name in
        EffectPreset(name: name, icon: "guitars", description: name,
                     effects: [.init(type: .overdrive, isEnabled: true, parameters: ["drive": 50])], category: .crunch)
    }
    func preset(for id: UUID) -> EffectPreset? { presets.first { $0.id == id } }
    func presets(for category: EffectPreset.PresetCategory) -> [EffectPreset] { presets.filter { $0.category == category } }
}

@MainActor
final class FakeSpectrum: SpectrumAnalyzing {
    var logFrequencies: [Float] = []
    var logMagnitudes: [Float] = []
    var sampleRate: Double = 44_100
    private(set) var analyses = 0
    func analyze(samples: [Float]) { analyses += 1 }
}

@MainActor
final class FakeChords: ChordAnalyzing {
    var detectedNote = "—"
    var detectedChord = "—"
    var confidence: Float = 0
    var centsDeviation: Float = 0
    var isInTune = false
    var sampleRate: Float = 44_100
    private(set) var resets = 0
    func analyze(samples: [Float]) {}
    func reset() { resets += 1 }
}

@MainActor
final class FakeFootswitch: FootswitchListening {
    var onEvent: (@MainActor (FootswitchEvent) -> Void)?
    var sourceNames: [String] = []
    var lastMessage: String?
    func start() {}
}

@MainActor
final class FakeGestures: GestureControlling {
    var isRunning = false
    var faceDetected = false
    var lastDetectedGesture: FaceGesture?
    var currentMouthOpenness: Float = 0
    var enabledGestures = Set(FaceGesture.allCases)
    var onGestureDetected: ((FaceGesture) -> Void)?
    var onMouthOpenValueChanged: ((Float) -> Void)?
    func start() async throws { isRunning = true }
    func stop() { isRunning = false }
}

@MainActor
final class FakeAssistant: ToneAssisting {
    var isAvailable = false
    var unavailableReason: String?
    var canReadImages = false
    var thinkingSteps: [AssistantThinkingStep] = []
    var lastCommandMode = ""
    var lastExplanation = ""
    var lastResponder = ToneResponder.offlineMatcher
    var lastEnabledEffects: [String] = []
    var lastDisabledEffects: [String] = []
    var lastDeletedEffects: [String] = []
    func processCommand(_ command: String, pedalboard: String?) async -> Bool { false }
    func processImage(at url: URL) async -> Bool { false }
    func applyToEngine(_ engine: any EffectsChainManaging) {}
}

@MainActor
final class FakeMusicApp: MusicAppControlling {
    var canControlAppleMusic = false
    var isAuthorized = false
    var isDenied = false
    var title: String?
    var artist: String?
    var isPlaying = false
    func requestAccess() async {}
    func refresh() {}
    func togglePlayback() {}
    func skipToNext() {}
    func skipToPrevious() {}
}

struct FakeSongAnalyzer: SongAnalyzing {
    var isAvailable: Bool { false }
    func analyze(url: URL) async throws -> SongAnalysis { throw CancellationError() }
}

struct FakeGuide: EffectGuideServiceProtocol {
    var categories: [any EffectCategoryProviding] { [] }
    func category(for id: String) -> (any EffectCategoryProviding)? { nil }
}

final class FakeToneStore: ToneStoring, @unchecked Sendable {
    var saved: ToneDocument?
    func load() -> ToneDocument? { saved }
    func save(_ document: ToneDocument) { saved = document }
}

// MARK: - Tests

@main
struct ViewModelTests {
    @MainActor static var checks = 0
    @MainActor static var failures: [String] = []

    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() { failures.append(name); print("FAIL: \(name)") }
    }

    @MainActor
    struct Fixture {
        let engine = FakeEngine()
        let footswitch = FakeFootswitch()
        let gestures = FakeGestures()
        let spectrum = FakeSpectrum()
        let chords = FakeChords()
        let store = FakeToneStore()
        let presets = FakePresets()
        let model: MainViewModel

        init() {
            model = MainViewModel(dependencies: AppDependencies(
                engine: engine, presets: presets, spectrum: spectrum, chords: chords,
                footswitch: footswitch, gestures: gestures, toneAssistant: FakeAssistant(),
                musicApp: FakeMusicApp(), songAnalyzer: FakeSongAnalyzer(), effectGuide: FakeGuide(),
                toneStore: store))
        }
    }

    @MainActor static func main() async {
        // Footswitch: program change, wrapping next/previous, looper, tuner mute
        do {
            let f = Fixture()
            f.model.onAppear()
            f.footswitch.onEvent?(.programChange(2))
            check(f.engine.currentPreset?.name == "Lead" && f.model.performanceController.currentPresetIndex == 2,
                  "Program change selects that preset")
            f.footswitch.onEvent?(.programChange(9))
            check(f.engine.currentPreset?.name == "Lead" && f.engine.presetApplyCount == 1,
                  "A program change past the list is ignored")
            f.footswitch.onEvent?(.nextPreset)
            check(f.engine.currentPreset?.name == "Clean", "Next preset wraps to the start")
            f.footswitch.onEvent?(.previousPreset)
            check(f.engine.currentPreset?.name == "Lead", "Previous preset wraps to the end")
            f.footswitch.onEvent?(.looper)
            check(f.engine.looper.presses == 1, "The looper footswitch presses the looper")
            f.footswitch.onEvent?(.tunerMute); let muted = f.engine.isTunerMuted
            f.footswitch.onEvent?(.tunerMute)
            check(muted && !f.engine.isTunerMuted, "The tuner footswitch mutes and unmutes")
            f.model.selectPreset(at: 1)
            check(f.engine.currentPreset?.name == "Crunch" && f.model.performanceController.currentPresetIndex == 1,
                  "Stage Mode's preset bar jumps to a preset")
        }

        // Head gestures
        do {
            let f = Fixture()
            f.engine.effectsChain = [EffectNode(type: .compressor), EffectNode(type: .overdrive),
                                     EffectNode(type: .delay, isEnabled: false)]
            f.model.onAppear()
            f.gestures.onGestureDetected?(.headTiltLeft)
            check(f.engine.effectsChain.allSatisfy { !$0.isEnabled }, "Tilting left bypasses every pedal")
            f.gestures.onGestureDetected?(.headTiltRight)
            check(f.engine.effectsChain.allSatisfy(\.isEnabled), "Tilting right switches every pedal on")
            f.gestures.onGestureDetected?(.eyebrowRaise)
            check(!f.engine.effectsChain[0].isEnabled && f.engine.effectsChain[1].isEnabled,
                  "Raising an eyebrow toggles only the compressor")
            f.gestures.onGestureDetected?(.mouthOpen)
            check(f.engine.effectsChain.map(\.isEnabled) == [false, true, true], "Opening the mouth flips no pedal")
            f.gestures.onGestureDetected?(.headNodDown)
            check(f.engine.currentPreset?.name == "Crunch", "Nodding down steps to the next preset")
            check(f.model.notch.activity?.title == FaceGesture.headNodDown.rawValue, "A gesture is announced in the notch")
            f.gestures.onMouthOpenValueChanged?(0.7)
            check(f.engine.wahPositions.last == 0.7, "The mouth drives the wah")
            await f.model.setGestureControl(enabled: false)
            check(f.engine.wahPositions.last == .some(nil), "Turning gestures off parks the wah")
        }

        // Analysis routing: the analysers follow the device's sample rate
        do {
            let f = Fixture()
            f.model.onAppear()
            f.engine.onAudioSamplesAvailable?([Float](repeating: 0, count: 1024))
            check(f.spectrum.analyses == 0, "Short buffers are not analysed")
            f.engine.onAudioSamplesAvailable?([Float](repeating: 0, count: 2048))
            check(f.spectrum.analyses == 1 && f.spectrum.sampleRate == 48_000 && f.chords.sampleRate == 48_000,
                  "Analysers run at the engine's sample rate")
            f.model.engineRunningDidChange(false)
            check(f.chords.resets == 1, "Stopping the engine clears the chord")
        }

        // The board document, undo seeding and Learn auditions
        do {
            let f = Fixture()
            var saved = InputSettings(); saved.cableFeet = 42
            f.store.saved = ToneDocument(name: "Saved", chain: [EffectNode(type: .fuzz)], amp: AmpSettings(),
                                         eqBands: [], input: saved)
            f.model.onAppear()
            check(f.engine.effectsChain.map(\.type) == [.fuzz] && f.engine.inputSettings.cableFeet == 42,
                  "Launch restores the saved board, input stage included")
            check(!f.model.history.canUndo, "The restored board is where undo starts")
            f.engine.startAudition(.chorus, modelID: nil)
            check(f.model.boardDocument == nil, "A Learn audition is never recorded as the board")
            let before = f.model.notch.activity?.id
            let snapshot = f.model.chainSnapshot
            f.engine.effectsChain[0].isEnabled = false
            f.model.chainDidChange(from: snapshot, to: f.model.chainSnapshot)
            check(f.model.notch.activity?.id == before, "Audition changes are not announced")
            f.engine.stopAudition()
            check(f.model.boardDocument != nil, "The board is recorded again after the audition")
        }

        // Chord suggestions skip the demo riff
        do {
            let f = Fixture()
            f.engine.isDemoRiffPlaying = true
            f.model.chordDidChange("A Minor")
            try? await Task.sleep(for: .milliseconds(50))
            check(f.model.chordAISuggestion == nil, "No chord suggestion while the demo riff plays")
        }

        if failures.isEmpty {
            print("\(checks)/\(checks) view model checks passed")
        } else {
            print("\(failures.count) of \(checks) view model checks failed")
            exit(1)
        }
    }
}
