import Foundation

@MainActor
final class TestEngine: EffectsChainManaging, AudioEngineControlling {
    var effectsChain: [EffectNode] = []
    var isPedalboardBypassed = false
    var presetApplyCount = 0
    var isRunning = false
    var hasPermission = false
    var errorMessage: String?
    let currentInputDeviceName = "Test input"
    let currentInputDeviceType: AudioInputDeviceType = .none
    var permissionRequests = 0
    var setupCalls = 0

    func requestMicrophonePermission() async { permissionRequests += 1 }
    func setupEngine() async throws { setupCalls += 1 }
    func enableLiveInput() async throws { await requestMicrophonePermission() }
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
    func refreshInputDevices() {}
    func addEffect(_ type: EffectType) { effectsChain.append(EffectNode(type: type)) }
    func removeEffect(at index: Int) { effectsChain.remove(at: index) }
    func moveEffect(from source: IndexSet, to destination: Int) {}
    func toggleEffect(_ effect: EffectNode) { effect.isEnabled.toggle() }
    func updateEffectParameter(_ effect: EffectNode, key: String, value: Float) { effect.parameters[key] = value }
    func setPedalModel(_ effect: EffectNode, modelID: String) { effect.modelID = modelID }
    func clearEffects() { effectsChain = [] }
    func resetEffectsToDefaults() { effectsChain = []; isPedalboardBypassed = false }
    func applyPreset(_ preset: EffectPreset) {
        effectsChain = preset.effects.map { $0.toEffectNode() }
        presetApplyCount += 1
    }
    func ensureEffectInChain(_ type: EffectType) {
        if !effectsChain.contains(where: { $0.type == type }) { addEffect(type) }
    }
    func rebuildEffectsChain() {}
}

/// A board that only remembers its tone document, for the undo history.
@MainActor
final class FakeBoard: ToneSharing {
    var drive: Float = 50
    func makeToneDocument(named name: String) -> ToneDocument {
        ToneDocument(name: name, chain: [EffectNode(type: .overdrive, parameters: ["drive": drive, "tone": 50, "level": 50])],
                     amp: AmpSettings(), eqBands: [])
    }
    func applyToneDocument(_ document: ToneDocument) {
        drive = document.pedals.first?.parameters["drive"] ?? 0
    }
}

final class MemoryToneStore: ToneStoring, @unchecked Sendable {
    var saved: ToneDocument?
    func load() -> ToneDocument? { saved }
    func save(_ document: ToneDocument) { saved = document }
}

@main
struct CoreRegressionTests {
    @MainActor static var checks = 0
    @MainActor static var failures: [String] = []

    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() { failures.append(name); print("FAIL: \(name)") }
    }

    static func sine(_ frequency: Double, rate: Double, amplitude: Double = 0.2, harmonics: Bool = false) -> [Float] {
        (0..<4096).map { i in
            let phase = 2 * Double.pi * frequency * Double(i) / rate
            return Float(amplitude * (sin(phase) + (harmonics ? 0.6 * sin(2 * phase) + 0.3 * sin(3 * phase) : 0)))
        }
    }

    @MainActor static func main() async {
        for rate in [44100.0, 48000.0] {
            for frequency in [82.4069, 110, 146.8324, 195.9977, 246.9417, 329.6276, 1108.7305] {
                for harmonics in [false, true] {
                    let result = ChordDetector.computePitchEstimate(samples: sine(frequency, rate: rate, harmonics: harmonics), sampleRate: Float(rate))
                    let cents = 1200 * log2(Double(result.frequency) / frequency)
                    check(abs(cents) < 5, "Pitch \(frequency) at \(rate), harmonics \(harmonics): \(cents) cents")
                    check(result.confidence > 0.8, "Pitch certainty \(frequency) at \(rate)")
                }
            }
            for amplitude in [0.01, 0.1, 0.5] {
                // A fresh analyzer avoids release smoothing from an earlier louder signal.
                let fft = FFTAnalyzer()
                fft.sampleRate = rate
                fft.analyze(samples: sine(rate * 100 / 2048, rate: rate, amplitude: amplitude))
                let measuredDB = (fft.logMagnitudes.max() ?? 0) * 80 - 80
                let expectedDB = Float(20 * log10(amplitude))
                check(abs(measuredDB - expectedDB) < 0.15, "FFT \(amplitude), \(rate): \(measuredDB) vs \(expectedDB)")
            }
        }
        check(ChordDetector.computePitchBackground(samples: [Float](repeating: 0, count: 4096), sampleRate: 48000) == 0, "Silence rejects pitch")
        check(ChordDetector.computePitchBackground(samples: [Float](repeating: 0.2, count: 4096), sampleRate: 48000) == 0, "DC rejects pitch")
        var seed: UInt64 = 42
        let noise: [Float] = (0..<4096).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            return Float(Int32(truncatingIfNeeded: seed >> 32)) / Float(Int32.max) * 0.2
        }
        check(ChordDetector.computePitchBackground(samples: noise, sampleRate: 48000) == 0, "Noise rejects pitch")
        let detector = ChordDetector()
        detector.sampleRate = 48000
        detector.applyPitchResult(440, samples: sine(440, rate: 48000))
        detector.applyPitchResult(0, samples: [Float](repeating: 0, count: 4096))
        check(detector.detectedNote == "—" && !detector.isInTune && detector.detectedChord == "—", "Silence clears displayed note")
        check(abs(AudioMeter.decibels(0.1) + 20) < 0.001, "RMS 0.1 = -20 dBFS")
        check(AudioMeter.normalized(1) == 1, "Full-scale meter reaches top")
        check(AudioMeter.normalized(0) == 0, "Silent meter is zero")
        check(AudioMeter.normalized(0.5) > AudioMeter.normalized(0.2), "Meter preserves high-level differences")

        let engine = TestEngine()
        engine.effectsChain = [EffectNode(type: .distortion, parameters: ["drive": 80, "tone": 85, "level": 90])]
        let processor = SemanticCommandProcessor()
        let set = await processor.processCommand("set distortion drive to 70")
        check(set, "Set drive recognized")
        processor.applyToEngine(engine)
        check(engine.effectsChain[0].parameters == ["drive": 70, "tone": 85, "level": 90], "Single-knob edit preserves tone and level")
        for expected in [Float(50), Float(60)] {
            _ = await processor.processCommand("more reverb")
            processor.applyToEngine(engine)
            let reverb = engine.effectsChain.first(where: { $0.type == .reverb })!
            check(reverb.parameters["wetDryMix"] == expected, "Relative reverb increases to \(expected)")
            check(reverb.parameters["decay"] == 1.5, "Relative reverb preserves decay")
        }
        _ = await processor.processCommand("set delay time to 500 ms")
        processor.applyToEngine(engine)
        check(engine.effectsChain.first(where: { $0.type == .delay })?.parameters["time"] == 0.5, "Delay milliseconds convert to seconds")
        _ = await processor.processCommand("distortion tone 20")
        processor.applyToEngine(engine)
        check(engine.effectsChain[0].parameters["tone"] == 20 && engine.effectsChain[0].parameters["drive"] == 70, "Shorthand parameter edit")
        _ = await processor.processCommand("set distortion drive to 900")
        processor.applyToEngine(engine)
        check(engine.effectsChain[0].parameters["drive"] == 100, "Drive is clamped")
        _ = await processor.processCommand("less gain")
        processor.applyToEngine(engine)
        check(engine.effectsChain[0].parameters["drive"] == 90, "Less gain is relative")
        _ = await processor.processCommand("turn off delay")
        processor.applyToEngine(engine)
        check(engine.effectsChain.first(where: { $0.type == .delay })?.isEnabled == false, "Bypass command remains supported")

        // The offline matcher on its own: pure input → outcome
        let deleteMatch = OfflineToneMatcher.match("delete reverb")
        check(deleteMatch.matched && deleteMatch.mode == "delete" && deleteMatch.deleted == ["reverb"], "Matcher deletes a named pedal")
        let bypassMatch = OfflineToneMatcher.match("turn off chorus")
        check(bypassMatch.matched && bypassMatch.mode == "remove" && bypassMatch.disabled?.contains("chorus") == true, "Matcher bypasses a named pedal")
        let genreMatch = OfflineToneMatcher.match("heavy metal")
        check(genreMatch.matched && genreMatch.enabled?.contains("distortion") == true, "Matcher turns a style into pedals")
        let unknownMatch = OfflineToneMatcher.match("qwertyuiop")
        check(!unknownMatch.matched && unknownMatch.explanation?.isEmpty == false, "Matcher explains what it couldn't understand")
        let missingMatch = OfflineToneMatcher.match("delete")
        check(!missingMatch.matched, "Matcher refuses a delete with no pedal named")

        // Undo history: settled changes are one step each; undo/redo walk them; autosave restores
        let board = FakeBoard()
        let store = MemoryToneStore()
        let history = BoardHistory(store: store, board: board)
        history.record(board.makeToneDocument(named: "Current"))          // the starting board
        for value in [Float(60), 62, 64, 70] {                            // a knob drag: one step
            board.drive = value
            history.record(board.makeToneDocument(named: "Current"))
        }
        try? await Task.sleep(for: .milliseconds(800))
        board.drive = 90
        history.record(board.makeToneDocument(named: "Current"))
        try? await Task.sleep(for: .milliseconds(800))
        history.undo()
        check(board.drive == 70, "Undo returns to the settled drag result")
        history.undo()
        check(board.drive == 50 && !history.canUndo, "Second undo returns to the start")
        history.redo(); history.redo()
        check(board.drive == 90 && !history.canRedo, "Redo walks forward again")
        board.drive = 10
        let restored = BoardHistory(store: store, board: board)
        restored.restoreSavedBoard()
        check(board.drive == 90, "The saved board is restored at launch")

        let setupEngine = TestEngine()
        let setup = SetupViewModel(audioEngine: setupEngine)
        await setup.performNextStep()
        check(setupEngine.permissionRequests == 0 && setup.isSetupComplete && setupEngine.isRunning, "Demo setup requires no microphone permission")

        let chatEngine = TestEngine()
        let chat = AIChatbotController()
        await chat.sendMessage("set distortion drive to 25", processor: processor, engine: chatEngine)
        let first = chat.messages.last!
        await chat.sendMessage("set distortion drive to 80", processor: processor, engine: chatEngine)
        chat.applyEffects(from: first, processor: processor, engine: chatEngine)
        check(chatEngine.effectsChain.first(where: { $0.type == .distortion })?.parameters["drive"] == 25, "Old chat reply restores its own snapshot")

        print("\(checks - failures.count)/\(checks) regression checks passed")
        if !failures.isEmpty { exit(1) }
    }

}
