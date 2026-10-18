import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Generable Output Types

/// What the on-device model fills in for a described sound. It only names the sound –
/// style, gain, space, signature pedals – and ToneRecipeBook turns that into knob values.
/// Tested on the iOS 27 / macOS 27 model: it recognises styles and songs well (~2 s) but
/// picks poor raw numbers ("more reverb" → mix 5), so it is never asked for numbers.
#if canImport(FoundationModels)
@available(iOS 26, macOS 26, *)
@Generable
enum SketchStyle {
    case clean, jazz, blues, classicRock, hardRock, metal, punk, grunge, funk, country
    case surf, eighties, ambient, shoegaze, psychedelic, lofi, ballad
}

@available(iOS 26, macOS 26, *)
@Generable
enum SketchGain { case clean, light, crunchy, heavy }

@available(iOS 26, macOS 26, *)
@Generable
enum SketchSpace { case dry, room, hall, huge }

@available(iOS 26, macOS 26, *)
@Generable
enum SketchPedal {
    case compressor, overdrive, distortion, fuzz, chorus, phaser, flanger, tremolo, delay, reverb
}

@available(iOS 26, macOS 26, *)
@Generable
struct ToneSketch {
    @Guide(description: "The closest style")
    var style: SketchStyle
    var gain: SketchGain
    var space: SketchSpace
    @Guide(description: "Extra pedals this sound is known for, beyond drive and reverb", .maximumCount(3))
    var signaturePedals: [SketchPedal]
    @Guide(description: "Why this suits the request, in under 15 words, no exclamation marks")
    var reason: String
}
#endif

// MARK: - Fallback Types (for older OS versions)

/// Fallback tone parameters when Foundation Models unavailable
struct FallbackToneParameters: Sendable {
    // Reverb
    var reverbMix: Double = 40
    var reverbDecay: Double = 2.0
    // Delay
    var delayMix: Double = 30
    var delayTime: Double = 0.3
    var delayFeedback: Double = 40
    // Distortion
    var distortionDrive: Double = 50
    var distortionTone: Double = 50
    var distortionLevel: Double = 50
    // Overdrive
    var overdriveDrive: Double = 40
    var overdriveTone: Double = 50
    var overdriveLevel: Double = 50
    // Fuzz
    var fuzzAmount: Double = 0
    var fuzzTone: Double = 50
    var fuzzLevel: Double = 50
    // Chorus
    var chorusRate: Double = 1.0
    var chorusDepth: Double = 40
    var chorusMix: Double = 50
    // Phaser
    var phaserRate: Double = 0.5
    var phaserDepth: Double = 0
    var phaserFeedback: Double = 30
    // Flanger
    var flangerRate: Double = 0.3
    var flangerDepth: Double = 0
    var flangerFeedback: Double = 50
    // Tremolo
    var tremoloRate: Double = 5.0
    var tremoloDepth: Double = 0
    // Compressor
    var compressorThreshold: Double = -20
    var compressorRatio: Double = 4
    var compressorAttack: Double = 10
    var compressorRelease: Double = 100
    // EQ
    var eqBass: Double = 0
    var eqMid: Double = 0
    var eqTreble: Double = 0
    var explanation: String = "Default tone settings"
}

extension FallbackToneParameters {
    /// Writes one model-chosen setting, clamped to the pedal's real range.
    mutating func set(_ name: String, to value: Double, for effect: String) {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
        switch (effect, name) {
        case ("reverb", "mix"): reverbMix = clamp(value, 0, 100)
        case ("reverb", "decay"): reverbDecay = clamp(value, 0.1, 10)
        case ("delay", "mix"): delayMix = clamp(value, 0, 100)
        case ("delay", "time"): delayTime = clamp(value, 0.05, 2)
        case ("delay", "feedback"): delayFeedback = clamp(value, 0, 90)
        case ("distortion", "drive"): distortionDrive = clamp(value, 0, 100)
        case ("distortion", "tone"): distortionTone = clamp(value, 0, 100)
        case ("distortion", "level"): distortionLevel = clamp(value, 0, 100)
        case ("overdrive", "drive"): overdriveDrive = clamp(value, 0, 100)
        case ("overdrive", "tone"): overdriveTone = clamp(value, 0, 100)
        case ("overdrive", "level"): overdriveLevel = clamp(value, 0, 100)
        case ("fuzz", "drive"): fuzzAmount = clamp(value, 0, 100)
        case ("fuzz", "tone"): fuzzTone = clamp(value, 0, 100)
        case ("fuzz", "level"): fuzzLevel = clamp(value, 0, 100)
        case ("chorus", "rate"): chorusRate = clamp(value, 0.1, 10)
        case ("chorus", "depth"): chorusDepth = clamp(value, 0, 100)
        case ("chorus", "mix"): chorusMix = clamp(value, 0, 100)
        case ("phaser", "rate"): phaserRate = clamp(value, 0.1, 5)
        case ("phaser", "depth"): phaserDepth = clamp(value, 0, 100)
        case ("phaser", "feedback"): phaserFeedback = clamp(value, 0, 100)
        case ("flanger", "rate"): flangerRate = clamp(value, 0.1, 2)
        case ("flanger", "depth"): flangerDepth = clamp(value, 0, 100)
        case ("flanger", "feedback"): flangerFeedback = clamp(value, 0, 100)
        case ("tremolo", "rate"): tremoloRate = clamp(value, 0.5, 15)
        case ("tremolo", "depth"): tremoloDepth = clamp(value, 0, 100)
        case ("compressor", "threshold"): compressorThreshold = clamp(value, -40, 0)
        case ("compressor", "ratio"): compressorRatio = clamp(value, 1, 20)
        case ("compressor", "attack"): compressorAttack = clamp(value, 0.1, 100)
        case ("compressor", "release"): compressorRelease = clamp(value, 10, 500)
        case ("equalizer", "bass"): eqBass = clamp(value, -12, 12)
        case ("equalizer", "mid"): eqMid = clamp(value, -12, 12)
        case ("equalizer", "treble"): eqTreble = clamp(value, -12, 12)
        default: break  // a setting that doesn't belong to this pedal
        }
    }
}

// MARK: - Semantic Command Processor

/// Processes natural language commands into DSP parameters using Foundation Models
/// Gracefully degrades to preset-based suggestions on older devices
@Observable
@MainActor
final class SemanticCommandProcessor: ToneAssisting {

    // MARK: - State

    private(set) var isProcessing = false
    private(set) var lastCommand: String = ""
    private(set) var lastEnabledEffects: [String] = []
    private(set) var lastDisabledEffects: [String] = []
    private(set) var lastDeletedEffects: [String] = []          // actually removed from chain
    private(set) var lastParameterOverrides: [String: Float] = [:] // e.g. ["distortion.level": 80]
    private struct ParameterEdit {
        let type: EffectType
        let key: String
        let value: Float
        let isRelative: Bool
    }
    private var pendingParameterEdit: ParameterEdit?
    private(set) var lastCommandMode: String = "preset" // "preset", "additive", "remove", "delete", "set"
    private(set) var lastParameters: FallbackToneParameters?
    private(set) var lastExplanation: String = ""
    private(set) var errorMessage: String?
    private(set) var isAvailable = false

    /// Which engine produced the latest answer – shown to the user so the
    /// offline fallback is never presented as Apple Intelligence.
    typealias Responder = ToneResponder
    private(set) var lastResponder: Responder = .offlineMatcher

    /// Why Apple Intelligence isn't being used (nil when it is).
    private(set) var unavailableReason: String?

    /// A live, step-by-step account of what the assistant is doing, built from the model's
    /// streamed partial output – so the wait shows progress instead of a spinner.
    typealias ThinkingStep = AssistantThinkingStep
    private(set) var thinkingSteps: [ThinkingStep] = []

    // MARK: - Foundation Models Session

    #if canImport(FoundationModels)
    /// A fresh, prewarmed session waiting for the next request. Each request gets its own
    /// session so history never grows past the model's context window; the current
    /// pedalboard is sent with every prompt instead.
    @available(iOS 26, macOS 26, *)
    private var preparedSession: LanguageModelSession?
    #endif
    private var instructions = ""

    // MARK: - Initialization

    init() {
        Task {
            await checkAvailability()
        }
    }

    // MARK: - Availability Check

    private func checkAvailability() async {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            // Set instructions once at session creation — the model caches this context
            // so each respond() call only processes the short user message, not the full prompt
            let instructions = """
            You are a guitar tone expert. Describe the sound the player asks for: its style, how much gain, \
            how much space, and any pedals it is known for (for example a solo with long echoes needs delay; \
            a wobbling sound needs tremolo or chorus).
            """
            self.instructions = instructions
            refreshAvailability()
        } else {
            isAvailable = false
            unavailableReason = "Requires iOS 26 or macOS 26"
        }
        #else
        isAvailable = false
        unavailableReason = "Foundation Models isn't available on this platform"
        #endif
    }

    /// Re-checks the on-device model. Cheap, so it runs before every request:
    /// a model that was still downloading may be ready now.
    private func refreshAvailability() {
        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, *) else { return }
        switch SystemLanguageModel.default.availability {
        case .available:
            isAvailable = true
            unavailableReason = nil
            if preparedSession == nil { prepareNextSession() }
        case .unavailable(let reason):
            isAvailable = false
            preparedSession = nil
            switch reason {
            case .deviceNotEligible:
                unavailableReason = "This device doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                unavailableReason = "Apple Intelligence is turned off in Settings"
            case .modelNotReady:
                unavailableReason = "The on-device model is still downloading"
            @unknown default:
                unavailableReason = "Apple Intelligence is unavailable"
            }
        }
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26, macOS 26, *)
    private func prepareNextSession() {
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        preparedSession = session
    }
    #endif

    // MARK: - Process Command

    /// Handles one message from the player.
    /// - Greetings and thanks get a local reply; nothing changes.
    /// - Questions are answered in words (Apple Intelligence, or the effect guide offline).
    /// - Commands that name a pedal ("more reverb", "remove delay") run instantly and exactly
    ///   through the local parser – the small model is unreliable at these.
    /// - Described sounds ("Comfortably Numb solo", "dreamy and spacey") go to Apple
    ///   Intelligence, which sketches the sound; ToneRecipeBook sets the knobs.
    /// - Parameter pedalboard: kept for callers; described sounds replace the whole tone.
    func processCommand(_ command: String, pedalboard: String? = nil) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }
        lastCommand = command
        pendingParameterEdit = nil
        errorMessage = nil
        lastDeletedEffects = []
        thinkingSteps = [ThinkingStep(id: "context", text: "Reading your request", isDone: true)]

        switch Self.classify(command) {
        case .smallTalk:
            finishChat(Self.smallTalkReply(for: command), by: .offlineMatcher)
            return true
        case .question:
            await answerQuestion(command)
            return true
        case .command:
            setStep("local", "Adjusting the pedals you named", done: true)
            lastResponder = .offlineMatcher
            if processParameterEdit(command) { return true }
            return processCommandFallback(command)
        case .tone:
            break
        }

        #if canImport(FoundationModels)
        refreshAvailability()
        if #available(iOS 26, macOS 26, *), isAvailable {
            let session = preparedSession ?? LanguageModelSession(instructions: instructions)
            preparedSession = nil
            defer { prepareNextSession() }
            do {
                setStep("model", "Apple Intelligence is listening to your description", done: false)
                let stream = session.streamResponse(to: command, generating: ToneSketch.self)
                for try await snapshot in stream {
                    updateThinkingSteps(from: snapshot.content)
                }
                let sketch = try await stream.collect().content
                // Pedals the player named themselves always make it in
                applySketch(sketch, alsoNamed: command)
                return true
            } catch {
                errorMessage = "Apple Intelligence couldn't answer: \(error.localizedDescription)"
                setStep("fallback", "Apple Intelligence couldn't answer – using the offline matcher", done: true)
            }
        } else {
            setStep("fallback", "Matching your words to a tone (offline)", done: true)
        }
        #endif

        lastResponder = .offlineMatcher
        return processCommandFallback(command)
    }

    // MARK: - Tone from a Photo (iOS / macOS 27)

    /// True when the on-device model can look at images (OS 27 multimodal prompts).
    var canReadImages: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 27, macOS 27, *) {
            return SystemLanguageModel.default.isAvailable
                && SystemLanguageModel.default.capabilities.contains(.vision)
        }
        #endif
        return false
    }

    /// Looks at a photo – an album cover, a gig poster, a pedalboard – and dials in the
    /// guitar sound it evokes. On device; the image never leaves it.
    func processImage(at url: URL) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }
        lastCommand = "Photo"
        errorMessage = nil
        lastDeletedEffects = []
        thinkingSteps = [ThinkingStep(id: "context", text: "Looking at your photo", isDone: false)]

        #if canImport(FoundationModels)
        if #available(iOS 27, macOS 27, *), canReadImages {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let stream = session.streamResponse(generating: ToneSketch.self) {
                    "What guitar tone does this picture evoke? Think about its era, mood and genre."
                    Attachment(imageURL: url)
                }
                for try await snapshot in stream {
                    setStep("context", "Looking at your photo", done: true)
                    updateThinkingSteps(from: snapshot.content)
                }
                let sketch = try await stream.collect().content
                applySketch(sketch)
                return true
            } catch {
                errorMessage = "Apple Intelligence couldn't read that photo."
            }
        }
        #endif
        markAllStepsDone()
        lastResponder = .offlineMatcher
        lastCommandMode = "chat"
        lastExplanation = "Reading photos needs Apple Intelligence on iOS or macOS 27. Describe the sound in words instead – \"80s chorus\", \"surf rock\"."
        return true
    }

    #if canImport(FoundationModels)
    /// Turns a model sketch into knob settings via the recipe book.
    @available(iOS 26, macOS 26, *)
    private func applySketch(_ sketch: ToneSketch, alsoNamed command: String = "") {
        let named = Self.mentionedPedals(in: command)
        let values = ToneSketchValues(
            style: ToneStyle(rawValue: String(describing: sketch.style)) ?? .clean,
            gain: ToneGain(rawValue: String(describing: sketch.gain)) ?? .light,
            space: ToneSpace(rawValue: String(describing: sketch.space)) ?? .room,
            signaturePedals: (sketch.signaturePedals.map { String(describing: $0) } + named).removingDuplicates(),
            reason: sketch.reason
        )
        let (effects, parameters) = ToneRecipeBook.build(values)
        setStep("recipe", "Setting the knobs from the \(values.style.title) recipe", done: true)
        markAllStepsDone()

        let reason = values.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let explanation = "\(values.style.title), \(values.gain.rawValue) gain, \(values.space.rawValue) space. "
            + (reason.prefix(1).uppercased() + reason.dropFirst())
            + (reason.hasSuffix(".") ? "" : ".")
        var finalParameters = parameters
        finalParameters.explanation = explanation

        lastCommandMode = "preset"
        lastEnabledEffects = effects
        lastDisabledEffects = []
        lastParameters = finalParameters
        lastExplanation = explanation
        lastResponder = .appleIntelligence
    }
    #endif

    /// Pedal names that appear in the text, in the model's vocabulary.
    private static func mentionedPedals(in text: String) -> [String] {
        let lower = text.lowercased()
        let names: [(String, [String])] = [
            ("delay", ["delay", "echo"]), ("reverb", ["reverb"]), ("chorus", ["chorus"]),
            ("phaser", ["phaser"]), ("flanger", ["flanger"]), ("tremolo", ["tremolo"]),
            ("fuzz", ["fuzz"]), ("compressor", ["compressor", "compression"]),
        ]
        return names.filter { _, words in words.contains { lower.contains($0) } }.map(\.0)
    }

    // MARK: - Request Classification

    enum RequestKind { case smallTalk, question, command, tone }

    private static let smallTalkWords: Set<String> = [
        "hi", "hello", "hey", "yo", "hiya", "thanks", "thank", "you", "thx", "ty", "ok", "okay",
        "cool", "nice", "great", "awesome", "good", "morning", "evening", "bye", "sup", "lol", "wow"
    ]
    private static let questionWords: Set<String> = [
        "what", "whats", "how", "why", "which", "who", "when", "where", "does", "do", "is", "are", "can", "should"
    ]
    private static let toneVerbs = [
        "add", "remove", "more", "less", "turn", "make", "give", "set", "boost", "cut", "increase",
        "decrease", "want", "need", "bypass", "enable", "disable", "switch", "sound like", "dial", "tone for"
    ]

    static func classify(_ text: String) -> RequestKind {
        let lower = text.lowercased()
        let words = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return .smallTalk }

        if words.count <= 4 && words.allSatisfy(smallTalkWords.contains) { return .smallTalk }

        let asksSomething = lower.trimmingCharacters(in: .whitespaces).hasSuffix("?")
            || questionWords.contains(words[0])
        let requestsChange = toneVerbs.contains { lower.contains($0) }
        if asksSomething && !requestsChange { return .question }

        // A command names a pedal or knob and says what to do with it ("more reverb",
        // "turn off the delay", "less gain, brighter", "set delay time 0.4").
        let namesKnob = knobWords.contains { lower.contains($0) }
        let startsWithVerb = commandVerbs.contains { words[0] == $0 || lower.hasPrefix($0 + " ") }
        if namesKnob && (startsWithVerb || words.count <= 2 || lower.contains(where: \.isNumber)) { return .command }
        if commandVerbs.contains(words[0]) && ["brighter", "darker", "louder", "quieter", "warmer"].contains(where: lower.contains) {
            return .command
        }
        return .tone
    }

    private static let knobWords = [
        "reverb", "delay", "echo", "chorus", "phaser", "flanger", "tremolo", "distortion", "overdrive",
        "drive", "fuzz", "compressor", "eq", "equalizer", "bass", "treble", "mid", "gain", "brighter", "darker"
    ]
    private static let commandVerbs = [
        "add", "more", "less", "remove", "delete", "turn", "set", "increase", "decrease", "boost", "cut",
        "enable", "disable", "bypass", "no", "without", "lower", "raise", "reduce", "crank", "put", "change",
        "make", "kill", "drop", "get"
    ]

    private static func smallTalkReply(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("thank") || lower.contains("thx") || lower == "ty" {
            return "You're welcome. Ask for another sound whenever you like."
        }
        if lower.contains("bye") { return "See you – keep playing." }
        return "Hi. Describe a sound – \"warm jazz clean\", \"add some reverb\", \"80s chorus\" – and I'll set up your pedals."
    }

    private func finishChat(_ reply: String, by responder: Responder) {
        lastCommandMode = "chat"
        lastEnabledEffects = []
        lastDisabledEffects = []
        lastParameters = nil
        lastExplanation = reply
        lastResponder = responder
        markAllStepsDone()
    }

    /// Answers a question in words only. Uses Apple Intelligence when available; offline it
    /// answers from RiffNode's own effect guide when the question names a pedal.
    private func answerQuestion(_ question: String) async {
        #if canImport(FoundationModels)
        refreshAvailability()
        if #available(iOS 26, macOS 26, *), isAvailable {
            setStep("answer", "Answering your question", done: false)
            let tutor = LanguageModelSession(instructions: """
                You are RiffNode's guitar tutor. Answer the player's question about guitar tone, \
                effects or music in at most two short, plain sentences. If it fits, suggest one \
                sound they could ask RiffNode for. No exclamation marks.
                """)
            if let answer = try? await tutor.respond(to: question).content {
                setStep("answer", "Answering your question", done: true)
                finishChat(answer.trimmingCharacters(in: .whitespacesAndNewlines), by: .appleIntelligence)
                return
            }
        }
        #endif
        let lower = question.lowercased()
        if let type = EffectType.allCases.first(where: { lower.contains($0.rawValue.lowercased()) }) {
            finishChat(type.effectDescription, by: .offlineMatcher)
        } else {
            finishChat("I can answer questions about the pedals offline – try \"what does a phaser do?\" – or ask for a sound to dial in.", by: .offlineMatcher)
        }
    }

    // MARK: - Thinking Steps

    private func setStep(_ id: String, _ text: String, done: Bool) {
        if let index = thinkingSteps.firstIndex(where: { $0.id == id }) {
            guard thinkingSteps[index].text != text || thinkingSteps[index].isDone != done else { return }
            thinkingSteps[index].text = text
            thinkingSteps[index].isDone = done
        } else {
            thinkingSteps.append(ThinkingStep(id: id, text: text, isDone: done))
        }
    }

    private func markAllStepsDone() {
        for index in thinkingSteps.indices { thinkingSteps[index].isDone = true }
    }

    #if canImport(FoundationModels)
    /// Turns the partially generated sketch into readable steps. Fields arrive in schema
    /// order (style → gain → space → pedals → reason), so each step completes as the next begins.
    @available(iOS 26, macOS 26, *)
    private func updateThinkingSteps(from partial: ToneSketch.PartiallyGenerated) {
        setStep("model", "Apple Intelligence is listening to your description", done: true)
        if let style = partial.style {
            let title = ToneStyle(rawValue: String(describing: style))?.title ?? String(describing: style)
            setStep("style", "Sounds like: \(title)", done: true)
        }
        if let gain = partial.gain {
            let space = partial.space.map { ", \(String(describing: $0)) space" } ?? ""
            setStep("feel", "\(String(describing: gain).capitalized) gain\(space)", done: partial.space != nil)
        }
        if let pedals = partial.signaturePedals, !pedals.isEmpty {
            let names = pedals.map { String(describing: $0).capitalized }.joined(separator: " · ")
            setStep("pedals", "Known for: \(names)", done: partial.reason != nil)
        }
    }
    #endif

    // MARK: - Fallback Processing

    /// No model (or it declined): work the request out with the offline matcher.
    private func processCommandFallback(_ command: String) -> Bool {
        let match = OfflineToneMatcher.match(command)
        if let mode = match.mode { lastCommandMode = mode }
        if let explanation = match.explanation { lastExplanation = explanation }
        if let enabled = match.enabled { lastEnabledEffects = enabled }
        if let disabled = match.disabled { lastDisabledEffects = disabled }
        if let deleted = match.deleted { lastDeletedEffects = deleted }
        if let parameters = match.parameters { lastParameters = parameters }
        if let overrides = match.parameterOverrides { lastParameterOverrides = overrides }
        return match.matched
    }

    // MARK: - Apply to Engine

    /// Apply the last recommendation to the audio engine
    func applyToEngine(_ engine: any EffectsChainManaging) {
        if let edit = pendingParameterEdit {
            engine.ensureEffectInChain(edit.type)
            guard let effect = engine.effectsChain.first(where: { $0.type == edit.type }) else { return }
            let current = effect.parameters[edit.key] ?? edit.type.defaultParameters[edit.key] ?? 0
            let proposed = edit.isRelative ? current + edit.value : edit.value
            let range = Self.parameterRange(edit.key, for: edit.type)
            engine.updateEffectParameter(effect, key: edit.key, value: min(range.upperBound, max(range.lowerBound, proposed)))
            if !effect.isEnabled { engine.toggleEffect(effect) }
            return
        }
        guard lastCommandMode != "chat", let params = lastParameters else { return }

        // Ensure every effect the AI wants to enable actually exists in the chain.
        // This lets the default chain stay small; new pedals are inserted on demand.
        for name in lastEnabledEffects {
            if let type = effectTypeFromName(name) {
                engine.ensureEffectInChain(type)
            }
        }

        switch lastCommandMode {

        case "delete":
            engine.effectsChain.removeAll { lastDeletedEffects.contains(effectName(for: $0.type)) }

        case "remove":
            for effect in engine.effectsChain {
                if lastDisabledEffects.contains(effectName(for: effect.type)) {
                    effect.isEnabled = false
                }
            }

        case "set":
            for effect in engine.effectsChain {
                let name = effectName(for: effect.type)
                if lastEnabledEffects.contains(name) {
                    effect.isEnabled = true
                    applyParameters(to: effect, params: params, engine: engine)
                }
            }

        case "additive":
            for effect in engine.effectsChain {
                let name = effectName(for: effect.type)
                if lastEnabledEffects.contains(name) {
                    effect.isEnabled = true
                    applyParameters(to: effect, params: params, engine: engine)
                } else if lastDisabledEffects.contains(name) {
                    effect.isEnabled = false
                }
            }

        default: // "preset" — replace all effects
            for effect in engine.effectsChain {
                let name = effectName(for: effect.type)
                let enabled = lastEnabledEffects.contains(name)
                effect.isEnabled = enabled
                if enabled {
                    applyParameters(to: effect, params: params, engine: engine)
                }
            }
        }

        engine.rebuildEffectsChain()
    }

    // MARK: - Private Helpers

    // MARK: - Parameter Command Parser

    /// Explicit and relative edits touch one knob; all other settings remain intact.
    private func processParameterEdit(_ command: String) -> Bool {
        let lower = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let increases = ["more ", "increase ", "boost ", "crank ", "push ", "raise "]
        let decreases = ["less ", "decrease ", "reduce ", "dial back ", "lower ", "cut "]
        let relative = increases.contains(where: lower.hasPrefix) || decreases.contains(where: lower.hasPrefix)
        let hasNumber = lower.range(of: #"-?\d+(?:\.\d+)?(?![\w.])"#, options: .regularExpression) != nil
        let forbidden = ["remove ", "delete ", "disable ", "bypass ", "turn off "]
        guard !forbidden.contains(where: lower.hasPrefix), relative || hasNumber else { return false }

        let type: EffectType
        if lower.contains("reverb") { type = .reverb }
        else if lower.contains("delay") || lower.contains("echo") { type = .delay }
        else if lower.contains("fuzz") { type = .fuzz }
        else if lower.contains("distortion") || lower.contains("gain") || lower.contains("dirt") { type = .distortion }
        else if lower.contains("overdrive") || lower.contains("drive") { type = .overdrive }
        else if lower.contains("chorus") { type = .chorus }
        else if lower.contains("phaser") { type = .phaser }
        else if lower.contains("flanger") { type = .flanger }
        else if lower.contains("tremolo") { type = .tremolo }
        else if lower.contains("compress") { type = .compressor }
        else if ["bass", "mid", "treble", "bright", "dark", "eq", "equalizer"].contains(where: lower.contains) { type = .equalizer }
        else { return false }

        let key: String
        switch type {
        case .equalizer: key = lower.contains("bass") ? "bass" : (lower.contains("mid") || lower.contains("eq") ? "mid" : "treble")
        case .compressor:
            key = lower.contains("ratio") ? "ratio" : (lower.contains("attack") ? "attack" : (lower.contains("release") ? "release" : "threshold"))
        case .overdrive, .distortion, .fuzz:
            key = lower.contains("tone") ? "tone" : (["level", "vol", "output"].contains(where: lower.contains) ? "level" : (type == .fuzz ? "fuzz" : "drive"))
        case .delay:
            key = ["time", "sec", "ms"].contains(where: lower.contains) ? "time" : (["feedback", "regen", "repeat"].contains(where: lower.contains) ? "feedback" : "mix")
        case .reverb:
            key = ["decay", "time", "tail", "sec"].contains(where: lower.contains) ? "decay" : "wetDryMix"
        case .chorus, .phaser, .flanger, .tremolo:
            key = ["rate", "speed", "hz"].contains(where: lower.contains) ? "rate" : (["feedback", "regen"].contains(where: lower.contains) ? "feedback" : (["mix", "wet"].contains(where: lower.contains) ? "mix" : "depth"))
        }
        guard type.defaultParameters[key] != nil else { return false }
        let range = Self.parameterRange(key, for: type)
        var value: Float
        if relative {
            value = (range.upperBound - range.lowerBound) * 0.1
            if decreases.contains(where: lower.hasPrefix) { value = -value }
        } else {
            guard let match = lower.range(of: #"-?\d+(?:\.\d+)?"#, options: .regularExpression),
                  let number = Float(lower[match]), number.isFinite else { return false }
            value = number
            if key == "time", type == .delay, lower.contains("ms") { value /= 1000 }
        }
        pendingParameterEdit = ParameterEdit(type: type, key: key, value: value, isRelative: relative)
        lastParameters = nil
        lastEnabledEffects = [effectName(for: type)]
        lastDisabledEffects = []
        lastDeletedEffects = []
        lastCommandMode = "set"
        lastExplanation = relative
            ? "\(value >= 0 ? "Increased" : "Reduced") \(type.rawValue) \(key). Other settings stay the same."
            : "Set \(type.rawValue) \(key) to \(min(range.upperBound, max(range.lowerBound, value)))."
        return true
    }

    private static func parameterRange(_ key: String, for type: EffectType) -> ClosedRange<Float> {
        switch key {
        case "bass", "mid", "treble": return -12...12
        case "threshold": return -40...0
        case "ratio": return 1...20
        case "attack": return 0.1...100
        case "release": return 10...500
        case "time": return 0.05...2
        case "decay": return 0.1...10
        case "feedback": return 0...90
        case "rate":
            switch type {
            case .phaser: return 0.1...5
            case .flanger: return 0.1...2
            case .tremolo: return 0.5...15
            default: return 0.1...10
            }
        default: return 0...100
        }
    }

    // MARK: - Effect Name Canonicalization

    /// Maps any string the model might generate to one of our 11 canonical effect names.
    /// Returns nil if the string clearly isn't an effect (e.g. "bass +4", "mid scoop").
    private func canonicalEffectName(_ raw: String) -> String? {
        let s = raw.lowercased()
        if s.contains("reverb") || s.contains("room") || s.contains("hall") || s.contains("cathedral") || s.contains("plate") { return "reverb" }
        if s.contains("delay") || s.contains("echo") || s.contains("slapback") { return "delay" }
        if s.contains("fuzz") { return "fuzz" }                                   // before distortion (fuzz contains no 'distort')
        if s.contains("distort") || s.contains("hi-gain") || s.contains("high gain") || s.contains("metal") { return "distortion" }
        if s.contains("overdrive") || s.contains("over drive") || s.contains("crunch") { return "overdrive" }
        if s.contains("flanger") || s.contains("flange") { return "flanger" }    // before chorus
        if s.contains("chorus") || s.contains("doubl") { return "chorus" }
        if s.contains("phaser") || s.contains("phase") { return "phaser" }
        if s.contains("tremolo") || s.contains("trem") { return "tremolo" }
        if s.contains("compress") || s.contains("limiter") { return "compressor" }
        if s.contains("equaliz") || s.contains(" eq") || s == "eq" || s.contains("parametric") { return "equalizer" }
        return nil  // "bass +4", "mid scoop", numbers, etc. — discard
    }

    private func effectTypeFromName(_ name: String) -> EffectType? {
        switch name {
        case "reverb":      return .reverb
        case "delay":       return .delay
        case "distortion":  return .distortion
        case "overdrive":   return .overdrive
        case "fuzz":        return .fuzz
        case "chorus":      return .chorus
        case "phaser":      return .phaser
        case "flanger":     return .flanger
        case "tremolo":     return .tremolo
        case "compressor":  return .compressor
        case "equalizer":   return .equalizer
        default:            return nil
        }
    }

    private func effectName(for type: EffectType) -> String {
        switch type {
        case .reverb:      return "reverb"
        case .delay:       return "delay"
        case .distortion:  return "distortion"
        case .overdrive:   return "overdrive"
        case .fuzz:        return "fuzz"
        case .chorus:      return "chorus"
        case .phaser:      return "phaser"
        case .flanger:     return "flanger"
        case .tremolo:     return "tremolo"
        case .compressor:  return "compressor"
        case .equalizer:   return "equalizer"
        }
    }

    private func applyParameters(to effect: EffectNode, params: FallbackToneParameters, engine: any EffectsChainManaging) {
        switch effect.type {
        case .reverb:
            engine.updateEffectParameter(effect, key: "wetDryMix", value: Float(params.reverbMix))
            engine.updateEffectParameter(effect, key: "decay", value: Float(params.reverbDecay))

        case .delay:
            engine.updateEffectParameter(effect, key: "time", value: Float(params.delayTime))
            engine.updateEffectParameter(effect, key: "feedback", value: Float(params.delayFeedback))
            engine.updateEffectParameter(effect, key: "mix", value: Float(params.delayMix))

        case .distortion:
            engine.updateEffectParameter(effect, key: "drive", value: Float(params.distortionDrive))
            engine.updateEffectParameter(effect, key: "tone", value: Float(params.distortionTone))
            engine.updateEffectParameter(effect, key: "level", value: Float(params.distortionLevel))

        case .overdrive:
            engine.updateEffectParameter(effect, key: "drive", value: Float(params.overdriveDrive))
            engine.updateEffectParameter(effect, key: "tone", value: Float(params.overdriveTone))
            engine.updateEffectParameter(effect, key: "level", value: Float(params.overdriveLevel))

        case .fuzz:
            engine.updateEffectParameter(effect, key: "fuzz", value: Float(params.fuzzAmount))
            engine.updateEffectParameter(effect, key: "tone", value: Float(params.fuzzTone))
            engine.updateEffectParameter(effect, key: "level", value: Float(params.fuzzLevel))

        case .chorus:
            engine.updateEffectParameter(effect, key: "rate", value: Float(params.chorusRate))
            engine.updateEffectParameter(effect, key: "depth", value: Float(params.chorusDepth))
            engine.updateEffectParameter(effect, key: "mix", value: Float(params.chorusMix))

        case .phaser:
            engine.updateEffectParameter(effect, key: "rate", value: Float(params.phaserRate))
            engine.updateEffectParameter(effect, key: "depth", value: Float(params.phaserDepth))
            engine.updateEffectParameter(effect, key: "feedback", value: Float(params.phaserFeedback))

        case .flanger:
            engine.updateEffectParameter(effect, key: "rate", value: Float(params.flangerRate))
            engine.updateEffectParameter(effect, key: "depth", value: Float(params.flangerDepth))
            engine.updateEffectParameter(effect, key: "feedback", value: Float(params.flangerFeedback))

        case .tremolo:
            engine.updateEffectParameter(effect, key: "rate", value: Float(params.tremoloRate))
            engine.updateEffectParameter(effect, key: "depth", value: Float(params.tremoloDepth))

        case .equalizer:
            engine.updateEffectParameter(effect, key: "bass", value: Float(params.eqBass))
            engine.updateEffectParameter(effect, key: "mid", value: Float(params.eqMid))
            engine.updateEffectParameter(effect, key: "treble", value: Float(params.eqTreble))

        case .compressor:
            engine.updateEffectParameter(effect, key: "threshold", value: Float(params.compressorThreshold))
            engine.updateEffectParameter(effect, key: "ratio", value: Float(params.compressorRatio))
            engine.updateEffectParameter(effect, key: "attack", value: Float(params.compressorAttack))
            engine.updateEffectParameter(effect, key: "release", value: Float(params.compressorRelease))
        }
    }

    // MARK: - Reset Conversation

    func resetConversation() {
        pendingParameterEdit = nil
        // Sessions are per request, so there is no history to clear – just re-check the model
        refreshAvailability()
        lastCommand = ""
        lastEnabledEffects = []
        lastDisabledEffects = []
        lastDeletedEffects = []
        lastParameterOverrides = [:]
        lastCommandMode = "preset"
        lastParameters = nil
        lastExplanation = ""
        errorMessage = nil
    }
}

// MARK: - Array Helper

extension Array where Element: Equatable {
    func removingDuplicates() -> [Element] {
        var seen: [Element] = []
        for element in self {
            if !seen.contains(element) { seen.append(element) }
        }
        return seen
    }
}
