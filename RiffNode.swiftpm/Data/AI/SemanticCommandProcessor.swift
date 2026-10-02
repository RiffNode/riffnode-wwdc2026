import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Generable Output Types

/// Structured output for the on-device model. The schema is kept deliberately small:
/// only the pedals a request touches, with at most three settings each. The earlier
/// design asked for all 32 parameters on every request, which took ~15 s to generate.
#if canImport(FoundationModels)
@available(iOS 26, macOS 26, *)
@Generable
enum ToneCommandMode {
    /// Replace the whole tone ("heavy metal", "jazz clean")
    case preset
    /// Change only the pedals mentioned ("add reverb", "more bass")
    case additive
    /// Turn pedals off ("remove delay")
    case remove
    /// Not a tone request – a greeting, thanks, or a question. Reply only; change nothing.
    case chat
}

@available(iOS 26, macOS 26, *)
@Generable
enum ToneEffect {
    case compressor, overdrive, distortion, fuzz, chorus, phaser, flanger, tremolo, delay, reverb, equalizer
}

@available(iOS 26, macOS 26, *)
@Generable
struct ToneSetting {
    @Guide(description: "A parameter of this pedal", .anyOf([
        "drive", "tone", "level", "rate", "depth", "mix", "feedback", "time", "decay",
        "threshold", "ratio", "attack", "release", "bass", "mid", "treble"
    ]))
    var name: String
    var value: Double
}

@available(iOS 26, macOS 26, *)
@Generable
struct PedalSetting {
    var effect: ToneEffect
    @Guide(description: "Only the settings that define this sound", .maximumCount(3))
    var settings: [ToneSetting]
}

@available(iOS 26, macOS 26, *)
@Generable
struct EffectRecommendation {
    var mode: ToneCommandMode
    @Guide(description: "Pedals to turn on, with their settings", .maximumCount(5))
    var pedals: [PedalSetting]
    @Guide(description: "Pedals to turn off; only for additive or remove", .maximumCount(5))
    var pedalsToTurnOff: [ToneEffect]
    @Guide(description: "One short, musical sentence about the tone")
    var explanation: String
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

/// Fallback effect recommendation when Foundation Models unavailable
struct FallbackEffectRecommendation: Sendable {
    var commandMode: String = "preset"
    var enabledEffects: [String] = ["distortion", "reverb"]
    var disabledEffects: [String] = []
    var parameters: FallbackToneParameters = FallbackToneParameters()
}

// MARK: - Semantic Command Processor

/// Processes natural language commands into DSP parameters using Foundation Models
/// Gracefully degrades to preset-based suggestions on older devices
@Observable
@MainActor
final class SemanticCommandProcessor {

    // MARK: - State

    private(set) var isProcessing = false
    private(set) var lastCommand: String = ""
    private(set) var lastEnabledEffects: [String] = []
    private(set) var lastDisabledEffects: [String] = []
    private(set) var lastDeletedEffects: [String] = []          // actually removed from chain
    private(set) var lastParameterOverrides: [String: Float] = [:] // e.g. ["distortion.level": 80]
    private(set) var lastCommandMode: String = "preset" // "preset", "additive", "remove", "delete", "set"
    private(set) var lastParameters: FallbackToneParameters?
    private(set) var lastExplanation: String = ""
    private(set) var errorMessage: String?
    private(set) var isAvailable = false

    /// Which engine produced the latest answer – shown to the user so the
    /// offline fallback is never presented as Apple Intelligence.
    enum Responder: Equatable {
        case appleIntelligence
        case offlineMatcher
    }
    private(set) var lastResponder: Responder = .offlineMatcher

    /// Why Apple Intelligence isn't being used (nil when it is).
    private(set) var unavailableReason: String?

    /// A live, step-by-step account of what the assistant is doing, built from the model's
    /// streamed partial output – so the wait shows progress instead of a spinner.
    struct ThinkingStep: Identifiable, Equatable {
        let id: String
        var text: String
        var isDone: Bool
    }
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
            You are RiffNode's guitar tone expert. Turn the player's request into pedal settings.

            Mode – pick one:
            preset: a whole style or genre ("heavy metal", "jazz clean", "for this Em riff"). Replaces the tone.
            additive: change only the pedals mentioned ("add reverb", "more bass", "faster tremolo"). Use the current pedalboard you are given.
            remove: turn pedals off ("remove delay", "no distortion").
            chat: anything that is not asking for a sound – greetings ("hi"), thanks, or questions ("what does a phaser do?"). Leave pedals empty and answer in the explanation.
            Only change the tone when the player asks for one. Never invent a request.

            Pedal settings (ranges):
            compressor threshold -40…0, ratio 1…20, attack 0.1…100, release 10…500
            overdrive / distortion / fuzz: drive 0…100, tone 0…100, level 0…100
            chorus rate 0.1…10 Hz, depth 0…100, mix 0…100
            phaser rate 0.1…5 Hz, depth 0…100, feedback 0…100
            flanger rate 0.1…2 Hz, depth 0…100, feedback 0…100
            tremolo rate 0.5…15 Hz, depth 0…100
            delay time 0.05…2 s, feedback 0…90, mix 0…100
            reverb mix 0…100, decay 0.1…10 s
            equalizer bass/mid/treble -12…12 dB

            Recipes:
            heavy metal: distortion drive 90 tone 35, equalizer bass 5 mid -4 treble 3
            jazz clean: compressor threshold -18 ratio 3, reverb mix 25 decay 1.2, equalizer treble -3
            blues: overdrive drive 50 tone 65, reverb mix 30
            classic rock: overdrive drive 60, reverb mix 25, equalizer mid 3
            80s clean: chorus rate 0.8 depth 70 mix 65, delay time 0.35 mix 45, reverb mix 35
            ambient: reverb mix 85 decay 6, delay time 0.55 feedback 55 mix 55, chorus depth 40
            shoegaze: distortion drive 65 tone 30, chorus depth 80, reverb mix 85 decay 5
            surf: reverb mix 90 decay 3.5, tremolo rate 4.5 depth 75
            funk: compressor threshold -22 ratio 6, equalizer treble 3
            psychedelic: fuzz drive 75, phaser rate 0.6 depth 70 feedback 60, reverb mix 55
            If the player names a chord: minor suits warm overdrive, major suits clean sparkle, power chords suit distortion.

            Use at most 5 pedals and only the settings that matter.

            Explanation: one or two calm, specific sentences in your own words about this request:
            which pedals you chose and why they fit it. No hype, no exclamation marks.
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

    /// Process a natural language command and return effect recommendations
    /// - Parameter pedalboard: a short description of the current chain, so the model
    ///   can make relative changes ("more reverb") without needing chat history.
    func processCommand(_ command: String, pedalboard: String? = nil) async -> Bool {
        isProcessing = true
        lastCommand = command
        errorMessage = nil
        thinkingSteps = [ThinkingStep(id: "context", text: "Reading your request", isDone: true)]

        // Only real tone requests may change the pedalboard. Greetings and questions are
        // recognised here, before the model – the small on-device model tends to answer
        // everything with a tone otherwise.
        switch Self.classify(command) {
        case .smallTalk:
            finishChat(Self.smallTalkReply(for: command), by: .offlineMatcher)
            return true
        case .question:
            await answerQuestion(command)
            return true
        case .tone:
            break
        }

        defer { isProcessing = false }

        #if canImport(FoundationModels)
        refreshAvailability()
        if #available(iOS 26, macOS 26, *), isAvailable {
            let session = preparedSession ?? LanguageModelSession(instructions: instructions)
            preparedSession = nil
            defer { prepareNextSession() }
            do {
                let prompt = pedalboard.map { "Current pedalboard: \($0)\nRequest: \(command)" } ?? command
                setStep("model", "Asking Apple Intelligence", done: false)
                let stream = session.streamResponse(to: prompt, generating: EffectRecommendation.self)
                for try await snapshot in stream {
                    updateThinkingSteps(from: snapshot.content)
                }
                let result = try await stream.collect().content
                markAllStepsDone()

                lastCommandMode = String(describing: result.mode)
                lastEnabledEffects = result.pedals
                    .map { String(describing: $0.effect) }
                    .removingDuplicates()
                lastDisabledEffects = result.pedalsToTurnOff
                    .map { String(describing: $0) }
                    .removingDuplicates()

                // Start from sensible defaults; overwrite only what the model chose
                var parameters = FallbackToneParameters()
                for pedal in result.pedals {
                    for setting in pedal.settings {
                        parameters.set(setting.name, to: setting.value, for: String(describing: pedal.effect))
                    }
                }
                let explanation = result.explanation.prefix(1).uppercased() + result.explanation.dropFirst()
                parameters.explanation = explanation
                lastParameters = parameters
                lastExplanation = explanation
                lastResponder = .appleIntelligence
                return true
            } catch {
                errorMessage = "Apple Intelligence couldn't answer: \(error.localizedDescription)"
                setStep("fallback", "Apple Intelligence couldn't answer – using the offline matcher", done: true)
                // Fall through to the offline matcher
            }
        } else {
            setStep("fallback", "Matching your words to a tone (offline)", done: true)
        }
        #endif

        // Fallback: instant keyword matching
        lastResponder = .offlineMatcher
        return processCommandFallback(command)
    }

    // MARK: - Request Classification

    enum RequestKind { case smallTalk, question, tone }

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
        return .tone
    }

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
    /// Turns the partially generated answer into readable steps. Fields arrive in schema
    /// order (mode → pedals → settings → explanation), so each step completes as the next begins.
    @available(iOS 26, macOS 26, *)
    private func updateThinkingSteps(from partial: EffectRecommendation.PartiallyGenerated) {
        setStep("model", "Asking Apple Intelligence", done: true)

        if let mode = partial.mode {
            let label: String
            switch mode {
            case .preset: label = "Building a whole new tone"
            case .additive: label = "Adjusting only what you asked for"
            case .remove: label = "Turning pedals off"
            case .chat: label = "Answering you"
            }
            setStep("mode", label, done: true)
        }

        let pedals = partial.pedals ?? []
        let names = pedals.compactMap { $0.effect.map { String(describing: $0).capitalized } }
        let movedOn = partial.pedalsToTurnOff != nil || partial.explanation != nil
        if !names.isEmpty {
            setStep("pedals", "Picking pedals: " + names.joined(separator: " · "), done: movedOn)
        }

        if let last = pedals.last, let effect = last.effect,
           let setting = last.settings?.last, let name = setting.name {
            let value = setting.value.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "…"
            setStep("settings", "Setting \(String(describing: effect)) \(name) → \(value)", done: movedOn)
        }

        if let explanation = partial.explanation, !explanation.isEmpty {
            setStep("explain", "Writing a note about the tone", done: false)
        }
    }
    #endif

    // MARK: - Fallback Processing

    private func processCommandFallback(_ command: String) -> Bool {
        let lower = command.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var effects: [String] = []
        var disabledEffects: [String] = []
        var params = FallbackToneParameters()
        var commandMode = "preset"

        // ── Additive / single-effect commands ──────────────────────────────
        // Detect intent: "add X", "turn on X", "enable X", "more X", "with X",
        // or just the effect name alone

        let addPrefixes    = ["add ", "turn on ", "enable ", "activate ", "with ", "i want "]
        let removePrefixes = ["turn off ", "disable ", "bypass ", "without "]
        let deletePrefixes = ["delete ", "remove ", "get rid of ", "trash ", "erase "]
        let morePrefixes   = ["more ", "increase ", "boost ", "crank ", "push "]
        let lessPrefixes   = ["less ", "decrease ", "reduce ", "dial back ", "lower ", "cut "]
        let setPrefixes    = ["set ", "put ", "make it ", "change "]

        let isAddIntent    = addPrefixes.contains(where: { lower.hasPrefix($0) })
            || lower == "reverb" || lower == "delay" || lower == "chorus"
            || lower == "phaser" || lower == "flanger" || lower == "tremolo"
            || lower == "distortion" || lower == "overdrive" || lower == "fuzz"
            || lower == "compressor" || lower == "eq" || lower == "equalizer"

        let isDeleteIntent = deletePrefixes.contains(where: { lower.hasPrefix($0) })
        let isRemoveIntent = removePrefixes.contains(where: { lower.hasPrefix($0) })
        let isMoreIntent   = morePrefixes.contains(where: { lower.hasPrefix($0) })
        let isLessIntent   = lessPrefixes.contains(where: { lower.hasPrefix($0) })
        let isSetIntent    = setPrefixes.contains(where: { lower.hasPrefix($0) })
            && lower.contains(where: { $0.isNumber })

        // ── Delete a pedal from the chain entirely ─────────────────────────
        if isDeleteIntent {
            commandMode = "delete"
            var deleted: [String] = []
            if lower.contains("reverb")     { deleted.append("reverb") }
            if lower.contains("delay")      { deleted.append("delay") }
            if lower.contains("distortion") { deleted.append("distortion") }
            if lower.contains("overdrive")  { deleted.append("overdrive") }
            if lower.contains("fuzz")       { deleted.append("fuzz") }
            if lower.contains("chorus")     { deleted.append("chorus") }
            if lower.contains("phaser")     { deleted.append("phaser") }
            if lower.contains("flanger")    { deleted.append("flanger") }
            if lower.contains("tremolo")    { deleted.append("tremolo") }
            if lower.contains("compressor") { deleted.append("compressor") }
            if lower.contains("eq") || lower.contains("equalizer") { deleted.append("equalizer") }

            if deleted.isEmpty {
                params.explanation = "Couldn't find that pedal. Try 'delete reverb' or 'remove distortion pedal'."
                lastDeletedEffects = []
                lastCommandMode = "preset"
                lastParameters = params
                lastExplanation = params.explanation
                return false
            }

            let names = deleted.map { $0.capitalized }.joined(separator: ", ")
            params.explanation = "Removed \(names) from your pedalboard."
            lastDeletedEffects = deleted
            lastEnabledEffects = []
            lastDisabledEffects = []
            lastCommandMode = commandMode
            lastParameters = params
            lastExplanation = params.explanation
            return true
        }

        // ── Set a specific parameter value ────────────────────────────────────
        // Handles every knob on every pedal:
        //   "set compressor threshold to -30"
        //   "overdrive drive 70"
        //   "set chorus rate 2"
        //   "distortion tone 60"
        //   "delay time 0.5"
        if isSetIntent {
            if let result = parseParameterCommand(lower, params: &params) {
                lastParameterOverrides = [:]
                lastEnabledEffects = [result]
                lastDisabledEffects = []
                lastDeletedEffects = []
                lastCommandMode = "set"
                lastParameters = params
                lastExplanation = params.explanation
                return true
            } else {
                params.explanation = "Try something like: 'set compressor threshold to -25', 'overdrive drive 70', 'chorus rate 2', 'delay time 0.4'."
                lastCommandMode = "preset"
                lastParameters = params
                lastExplanation = params.explanation
                return false
            }
        }

        // ── Remove specific effects ──────────────────────────────────────────
        if isRemoveIntent {
            commandMode = "remove"
            if lower.contains("reverb")    { disabledEffects.append("reverb") }
            if lower.contains("delay")     { disabledEffects.append("delay") }
            if lower.contains("distortion"){ disabledEffects.append("distortion") }
            if lower.contains("overdrive") { disabledEffects.append("overdrive") }
            if lower.contains("fuzz")      { disabledEffects.append("fuzz") }
            if lower.contains("chorus")    { disabledEffects.append("chorus") }
            if lower.contains("phaser")    { disabledEffects.append("phaser") }
            if lower.contains("flanger")   { disabledEffects.append("flanger") }
            if lower.contains("tremolo")   { disabledEffects.append("tremolo") }
            if lower.contains("compressor"){ disabledEffects.append("compressor") }
            if lower.contains("eq") || lower.contains("equalizer") { disabledEffects.append("equalizer") }

            if disabledEffects.isEmpty {
                params.explanation = "I couldn't identify which effect to remove. Try 'remove reverb' or 'turn off delay'."
                lastEnabledEffects = []
                lastDisabledEffects = []
                lastCommandMode = "preset"
                lastParameters = params
                lastExplanation = params.explanation
                return false
            }

            let names = disabledEffects.map { $0.capitalized }.joined(separator: ", ")
            params.explanation = "Turned off: \(names)."
            lastEnabledEffects = []
            lastDisabledEffects = disabledEffects
            lastCommandMode = commandMode
            lastParameters = params
            lastExplanation = params.explanation
            return true
        }

        // ── "More X" — boost a parameter or enable an effect ──────────────
        if isMoreIntent {
            commandMode = "additive"
            if lower.contains("reverb") {
                effects = ["reverb"]
                params.reverbMix = 75
                params.reverbDecay = 3.5
                params.explanation = "Boosted reverb for a wider, more spacious sound."
            } else if lower.contains("delay") {
                effects = ["delay"]
                params.delayMix = 65
                params.delayTime = 0.4
                params.explanation = "Increased delay mix for more prominent echoes."
            } else if lower.contains("bass") {
                effects = ["equalizer"]
                params.eqBass = 5
                params.explanation = "Boosted the bass frequencies for a fuller, heavier sound."
            } else if lower.contains("treble") || lower.contains("high") || lower.contains("bright") {
                effects = ["equalizer"]
                params.eqTreble = 5
                params.explanation = "Boosted treble for a brighter, more cutting tone."
            } else if lower.contains("mid") {
                effects = ["equalizer"]
                params.eqMid = 4
                params.explanation = "Boosted mids to help cut through the mix."
            } else if lower.contains("gain") || lower.contains("distortion") || lower.contains("dirt") {
                effects = ["distortion"]
                params.distortionDrive = 80
                params.explanation = "Cranked the gain for a more aggressive, saturated tone."
            } else if lower.contains("overdrive") || lower.contains("drive") {
                effects = ["overdrive"]
                params.overdriveDrive = 70
                params.explanation = "Increased overdrive for a warmer, driven sound."
            } else if lower.contains("chorus") {
                effects = ["chorus"]
                params.chorusDepth = 70
                params.explanation = "Increased chorus depth for a lusher, shimmering sound."
            } else {
                params.explanation = "Try 'more reverb', 'more bass', 'more delay', or 'more gain'."
                return false
            }
            lastEnabledEffects = effects
            lastDisabledEffects = []
            lastCommandMode = commandMode
            lastParameters = params
            lastExplanation = params.explanation
            return true
        }

        // ── "Less X" — reduce a parameter ─────────────────────────────────
        if isLessIntent {
            commandMode = "additive"
            if lower.contains("reverb") {
                effects = ["reverb"]
                params.reverbMix = 20
                params.reverbDecay = 1.0
                params.explanation = "Reduced reverb for a drier, more upfront sound."
            } else if lower.contains("delay") {
                effects = ["delay"]
                params.delayMix = 15
                params.explanation = "Pulled back the delay for subtler echoes."
            } else if lower.contains("bass") {
                effects = ["equalizer"]
                params.eqBass = -4
                params.explanation = "Cut the bass for a tighter, cleaner low-end."
            } else if lower.contains("treble") || lower.contains("high") {
                effects = ["equalizer"]
                params.eqTreble = -4
                params.explanation = "Rolled off some treble for a warmer sound."
            } else if lower.contains("mid") {
                effects = ["equalizer"]
                params.eqMid = -4
                params.explanation = "Scooped the mids for a more scooped metal tone."
            } else if lower.contains("gain") || lower.contains("distortion") || lower.contains("dirt") {
                effects = ["distortion"]
                params.distortionDrive = 30
                params.explanation = "Backed off the gain for a cleaner crunch."
            } else {
                params.explanation = "Try 'less reverb', 'less bass', or 'less delay'."
                return false
            }
            lastEnabledEffects = effects
            lastDisabledEffects = []
            lastCommandMode = commandMode
            lastParameters = params
            lastExplanation = params.explanation
            return true
        }

        // ── Add a specific single effect ───────────────────────────────────
        if isAddIntent || lower.count < 20 {
            if lower.contains("reverb") {
                commandMode = "additive"
                effects = ["reverb"]
                params.reverbMix = lower.contains("more") || lower.contains("lot") ? 75 : 50
                params.reverbDecay = 2.5
                params.explanation = "Added reverb to give your tone space and depth."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("delay") || lower.contains("echo") {
                commandMode = "additive"
                effects = ["delay"]
                params.delayMix = 40
                params.delayTime = 0.35
                params.delayFeedback = 35
                params.explanation = "Added delay for rhythmic echoes and depth."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("chorus") {
                commandMode = "additive"
                effects = ["chorus"]
                params.chorusDepth = 50
                params.explanation = "Added chorus for a lush, shimmering sound."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("phaser") {
                commandMode = "additive"
                effects = ["phaser"]
                params.phaserDepth = 50
                params.explanation = "Added phaser for a sweeping, psychedelic effect."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("flanger") {
                commandMode = "additive"
                effects = ["flanger"]
                params.flangerDepth = 50
                params.explanation = "Added flanger for a metallic, jet-sweep effect."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("tremolo") {
                commandMode = "additive"
                effects = ["tremolo"]
                params.tremoloDepth = 60
                params.explanation = "Added tremolo for a pulsating, rhythmic volume effect."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("fuzz") {
                commandMode = "additive"
                effects = ["fuzz"]
                params.fuzzAmount = 70
                params.explanation = "Added fuzz for a thick, buzzy, vintage saturation."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("overdrive") || lower.contains("drive") {
                commandMode = "additive"
                effects = ["overdrive"]
                params.overdriveDrive = 50
                params.explanation = "Added overdrive for a warm, tube-like crunch."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("distortion") {
                commandMode = "additive"
                effects = ["distortion"]
                params.distortionDrive = 60
                params.explanation = "Added distortion for aggressive, hard-clipped gain."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("compressor") || lower.contains("compress") {
                commandMode = "additive"
                effects = ["compressor"]
                params.explanation = "Added compressor for tighter dynamics and more sustain."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
            if lower.contains("eq") || lower.contains("equalizer") || lower.contains("bass") || lower.contains("treble") || lower.contains("mid") {
                commandMode = "additive"
                effects = ["equalizer"]
                if lower.contains("bass") { params.eqBass = lower.contains("boost") || lower.contains("more") ? 5 : 3 }
                if lower.contains("treble") || lower.contains("bright") { params.eqTreble = 4 }
                if lower.contains("mid") { params.eqMid = lower.contains("scoop") || lower.contains("cut") ? -4 : 3 }
                params.explanation = "Applied EQ adjustments to shape your frequency response."
                lastEnabledEffects = effects
                lastDisabledEffects = []
                lastCommandMode = commandMode
                lastParameters = params
                lastExplanation = params.explanation
                return true
            }
        }

        // ── Full preset tones ──────────────────────────────────────────────
        commandMode = "preset"

        if lower.contains("spacey") || lower.contains("ambient") || lower.contains("atmospheric") || lower.contains("pad") {
            effects = ["reverb", "delay", "chorus"]
            params.reverbMix = 75
            params.reverbDecay = 5.0
            params.delayMix = 50
            params.delayTime = 0.5
            params.delayFeedback = 45
            params.chorusDepth = 40
            params.explanation = "Lush ambient tone with cavernous reverb, echoing delay, and gentle chorus — perfect for atmospheric playing."
        } else if lower.contains("shoegaze") || lower.contains("wall of sound") {
            effects = ["distortion", "chorus", "reverb"]
            params.distortionDrive = 65
            params.chorusDepth = 70
            params.reverbMix = 80
            params.reverbDecay = 4.0
            params.explanation = "Shoegaze wall-of-sound: heavy distortion drowned in thick chorus and cavernous reverb."
        } else if lower.contains("heavy") || lower.contains("metal") || lower.contains("djent") {
            effects = ["distortion", "equalizer"]
            params.distortionDrive = 85
            params.eqBass = 4
            params.eqMid = -3
            params.eqTreble = 2
            params.explanation = "High-gain metal tone with maxed distortion, scooped mids, and tight low-end."
        } else if lower.contains("classic rock") || lower.contains("hard rock") {
            effects = ["overdrive", "reverb", "equalizer"]
            params.overdriveDrive = 55
            params.reverbMix = 30
            params.eqMid = 2
            params.eqTreble = 1
            params.explanation = "Classic rock crunch with medium overdrive, natural room reverb, and a mid presence boost."
        } else if lower.contains("clean") || lower.contains("crystal") {
            effects = ["reverb", "equalizer", "compressor"]
            params.reverbMix = 25
            params.reverbDecay = 1.5
            params.eqTreble = 3
            params.explanation = "Crystal clean tone — sparkling highs, gentle reverb, and compressor for even dynamics."
        } else if lower.contains("jazz") {
            effects = ["reverb", "compressor", "equalizer"]
            params.reverbMix = 30
            params.reverbDecay = 1.8
            params.eqBass = 2
            params.eqMid = 1
            params.eqTreble = -2
            params.explanation = "Warm jazz tone: dark EQ, natural reverb, and compressor for that smooth, round character."
        } else if lower.contains("blues") || lower.contains("bb king") || lower.contains("srv") {
            effects = ["overdrive", "reverb", "equalizer"]
            params.overdriveDrive = 40
            params.reverbMix = 35
            params.reverbDecay = 1.8
            params.eqBass = 2
            params.eqMid = 3
            params.explanation = "Warm blues tone with smooth overdrive, punchy mids, and natural reverb."
        } else if lower.contains("warm") || lower.contains("vintage") {
            effects = ["overdrive", "reverb", "equalizer"]
            params.overdriveDrive = 40
            params.reverbMix = 35
            params.reverbDecay = 2.0
            params.eqBass = 3
            params.eqMid = 2
            params.explanation = "Warm vintage tone with gentle overdrive, thick bass, and natural room reverb."
        } else if lower.contains("80s") || lower.contains("eighties") || lower.contains("neon") {
            effects = ["chorus", "delay", "reverb"]
            params.chorusDepth = 65
            params.delayMix = 45
            params.delayTime = 0.35
            params.delayFeedback = 40
            params.reverbMix = 40
            params.reverbDecay = 2.5
            params.explanation = "Classic 80s sound: thick chorus modulation, rhythmic delay, and lush plate reverb."
        } else if lower.contains("surf") || lower.contains("dick dale") || lower.contains("tremolo") {
            effects = ["reverb", "tremolo", "equalizer"]
            params.reverbMix = 85
            params.reverbDecay = 3.0
            params.tremoloDepth = 70
            params.eqTreble = 3
            params.explanation = "Surf rock tone: massive reverb, pulsating tremolo, and a bright treble boost."
        } else if lower.contains("crunch") || lower.contains("rock") {
            effects = ["overdrive", "reverb"]
            params.overdriveDrive = 55
            params.reverbMix = 30
            params.explanation = "Rock crunch with medium overdrive and just enough reverb to sit in the room."
        } else if lower.contains("fuzz") || lower.contains("psychedelic") || lower.contains("garage") {
            effects = ["fuzz", "reverb", "phaser"]
            params.fuzzAmount = 75
            params.reverbMix = 55
            params.reverbDecay = 3.0
            params.phaserDepth = 50
            params.explanation = "Psychedelic fuzz tone with swirling phaser and deep reverb."
        } else if lower.contains("country") || lower.contains("twang") {
            effects = ["compressor", "overdrive", "delay", "equalizer"]
            params.overdriveDrive = 30
            params.delayMix = 30
            params.delayTime = 0.2
            params.delayFeedback = 20
            params.eqTreble = 3
            params.eqMid = -1
            params.explanation = "Twangy country tone: compressor for snap, light overdrive, slapback delay, and bright highs."
        } else if lower.contains("lead") || lower.contains("solo") {
            effects = ["overdrive", "delay", "reverb", "equalizer"]
            params.overdriveDrive = 60
            params.delayMix = 35
            params.delayTime = 0.4
            params.reverbMix = 30
            params.eqMid = 4
            params.eqTreble = 2
            params.explanation = "Lead solo tone: boosted mids to cut through, sustained overdrive, and space from delay + reverb."
        } else {
            // No match
            params.explanation = "I didn't recognize that tone. Try something like \"warm blues\", \"80s chorus\", \"add reverb\", or \"heavy metal\"."
            lastEnabledEffects = []
            lastDisabledEffects = []
            lastCommandMode = "preset"
            lastParameters = params
            lastExplanation = params.explanation
            return false
        }

        lastEnabledEffects = effects
        lastDisabledEffects = []
        lastCommandMode = commandMode
        lastParameters = params
        lastExplanation = params.explanation
        return true
    }

    // MARK: - Apply to Engine

    /// Apply the last recommendation to the audio engine
    func applyToEngine(_ engine: AudioEngineManager) {
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

    /// Parses "set [effect] [param] to [value]" style commands.
    /// Mutates `params` in place and returns the canonical effect name, or nil if unrecognized.
    private func parseParameterCommand(_ lower: String, params: inout FallbackToneParameters) -> String? {

        // Extract first number (supports negatives and decimals)
        let numberPattern = #"-?\d+\.?\d*"#
        guard let range = lower.range(of: numberPattern, options: .regularExpression),
              let value = Float(lower[range]) else { return nil }

        // ── Compressor ────────────────────────────────────────────────────────
        if lower.contains("compressor") || lower.contains("compress") {
            if lower.contains("threshold") || lower.contains("thresh") {
                params.compressorThreshold = Double(max(-40, min(0, value)))
                params.explanation = "Compressor threshold set to \(Int(value))dB."
            } else if lower.contains("ratio") {
                params.compressorRatio = Double(max(1, min(20, value)))
                params.explanation = "Compressor ratio set to \(String(format:"%.1f", value)):1."
            } else if lower.contains("attack") {
                params.compressorAttack = Double(max(0.1, min(100, value)))
                params.explanation = "Compressor attack set to \(Int(value))ms."
            } else if lower.contains("release") || lower.contains("rel") {
                params.compressorRelease = Double(max(10, min(500, value)))
                params.explanation = "Compressor release set to \(Int(value))ms."
            } else {
                params.compressorThreshold = Double(max(-40, min(0, value)))
                params.explanation = "Compressor threshold set to \(Int(value))dB."
            }
            return "compressor"
        }

        // ── Overdrive ─────────────────────────────────────────────────────────
        if lower.contains("overdrive") || (lower.contains("drive") && !lower.contains("distortion")) {
            if lower.contains("tone") {
                params.overdriveTone = Double(max(0, min(100, value)))
                params.explanation = "Overdrive tone set to \(Int(value))."
            } else if lower.contains("level") || lower.contains("vol") || lower.contains("output") {
                params.overdriveLevel = Double(max(0, min(100, value)))
                params.explanation = "Overdrive level set to \(Int(value))."
            } else {
                params.overdriveDrive = Double(max(0, min(100, value)))
                params.explanation = "Overdrive drive set to \(Int(value))."
            }
            return "overdrive"
        }

        // ── Distortion ────────────────────────────────────────────────────────
        if lower.contains("distortion") || lower.contains("dist") {
            if lower.contains("tone") {
                params.distortionTone = Double(max(0, min(100, value)))
                params.explanation = "Distortion tone set to \(Int(value))."
            } else if lower.contains("level") || lower.contains("vol") || lower.contains("output") {
                params.distortionLevel = Double(max(0, min(100, value)))
                params.explanation = "Distortion level set to \(Int(value))."
            } else {
                params.distortionDrive = Double(max(0, min(100, value)))
                params.explanation = "Distortion drive set to \(Int(value))."
            }
            return "distortion"
        }

        // ── Fuzz ──────────────────────────────────────────────────────────────
        if lower.contains("fuzz") {
            if lower.contains("tone") {
                params.fuzzTone = Double(max(0, min(100, value)))
                params.explanation = "Fuzz tone set to \(Int(value))."
            } else if lower.contains("level") || lower.contains("vol") || lower.contains("output") {
                params.fuzzLevel = Double(max(0, min(100, value)))
                params.explanation = "Fuzz level set to \(Int(value))."
            } else {
                params.fuzzAmount = Double(max(0, min(100, value)))
                params.explanation = "Fuzz amount set to \(Int(value))."
            }
            return "fuzz"
        }

        // ── Chorus ────────────────────────────────────────────────────────────
        if lower.contains("chorus") {
            if lower.contains("rate") || lower.contains("speed") || lower.contains("hz") {
                params.chorusRate = Double(max(0.1, min(10, value)))
                params.explanation = "Chorus rate set to \(String(format:"%.1f", value))Hz."
            } else if lower.contains("mix") || lower.contains("wet") {
                params.chorusMix = Double(max(0, min(100, value)))
                params.explanation = "Chorus mix set to \(Int(value))%."
            } else {
                params.chorusDepth = Double(max(0, min(100, value)))
                params.explanation = "Chorus depth set to \(Int(value))."
            }
            return "chorus"
        }

        // ── Phaser ────────────────────────────────────────────────────────────
        if lower.contains("phaser") || lower.contains("phase") {
            if lower.contains("rate") || lower.contains("speed") || lower.contains("hz") {
                params.phaserRate = Double(max(0.1, min(5, value)))
                params.explanation = "Phaser rate set to \(String(format:"%.1f", value))Hz."
            } else if lower.contains("feedback") || lower.contains("regen") {
                params.phaserFeedback = Double(max(0, min(100, value)))
                params.explanation = "Phaser feedback set to \(Int(value))."
            } else {
                params.phaserDepth = Double(max(0, min(100, value)))
                params.explanation = "Phaser depth set to \(Int(value))."
            }
            return "phaser"
        }

        // ── Flanger ───────────────────────────────────────────────────────────
        if lower.contains("flanger") || lower.contains("flange") {
            if lower.contains("rate") || lower.contains("speed") || lower.contains("hz") {
                params.flangerRate = Double(max(0.1, min(2, value)))
                params.explanation = "Flanger rate set to \(String(format:"%.2f", value))Hz."
            } else if lower.contains("feedback") || lower.contains("regen") {
                params.flangerFeedback = Double(max(0, min(100, value)))
                params.explanation = "Flanger feedback set to \(Int(value))."
            } else {
                params.flangerDepth = Double(max(0, min(100, value)))
                params.explanation = "Flanger depth set to \(Int(value))."
            }
            return "flanger"
        }

        // ── Tremolo ───────────────────────────────────────────────────────────
        if lower.contains("tremolo") || lower.contains("trem") {
            if lower.contains("rate") || lower.contains("speed") || lower.contains("hz") {
                params.tremoloRate = Double(max(0.5, min(15, value)))
                params.explanation = "Tremolo rate set to \(String(format:"%.1f", value))Hz."
            } else {
                params.tremoloDepth = Double(max(0, min(100, value)))
                params.explanation = "Tremolo depth set to \(Int(value))."
            }
            return "tremolo"
        }

        // ── Delay ─────────────────────────────────────────────────────────────
        if lower.contains("delay") || lower.contains("echo") {
            if lower.contains("time") || lower.contains("sec") || lower.contains("ms") {
                // Convert ms to seconds if needed
                let timeVal = value > 2.0 ? value / 1000.0 : value
                params.delayTime = Double(max(0.05, min(2.0, timeVal)))
                params.explanation = "Delay time set to \(String(format:"%.2f", params.delayTime))s."
            } else if lower.contains("feedback") || lower.contains("regen") || lower.contains("repeat") {
                params.delayFeedback = Double(max(0, min(90, value)))
                params.explanation = "Delay feedback set to \(Int(value))%."
            } else {
                params.delayMix = Double(max(0, min(100, value)))
                params.explanation = "Delay mix set to \(Int(value))%."
            }
            return "delay"
        }

        // ── Reverb ────────────────────────────────────────────────────────────
        if lower.contains("reverb") || lower.contains("room") || lower.contains("hall") {
            if lower.contains("decay") || lower.contains("time") || lower.contains("tail") || lower.contains("sec") {
                params.reverbDecay = Double(max(0.1, min(10, value)))
                params.explanation = "Reverb decay set to \(String(format:"%.1f", value))s."
            } else {
                params.reverbMix = Double(max(0, min(100, value)))
                params.explanation = "Reverb mix set to \(Int(value))%."
            }
            return "reverb"
        }

        // ── EQ ────────────────────────────────────────────────────────────────
        if lower.contains("bass") || lower.contains("low freq") {
            params.eqBass = Double(max(-12, min(12, value)))
            params.explanation = "Bass EQ set to \(value >= 0 ? "+" : "")\(Int(value))dB."
            return "equalizer"
        }
        if lower.contains("treble") || lower.contains("high freq") || lower.contains("presence") {
            params.eqTreble = Double(max(-12, min(12, value)))
            params.explanation = "Treble EQ set to \(value >= 0 ? "+" : "")\(Int(value))dB."
            return "equalizer"
        }
        if lower.contains("mid") {
            params.eqMid = Double(max(-12, min(12, value)))
            params.explanation = "Mid EQ set to \(value >= 0 ? "+" : "")\(Int(value))dB."
            return "equalizer"
        }
        if lower.contains("eq") || lower.contains("equaliz") {
            // Generic "set eq to X" — treat as mid
            params.eqMid = Double(max(-12, min(12, value)))
            params.explanation = "EQ mid set to \(value >= 0 ? "+" : "")\(Int(value))dB."
            return "equalizer"
        }

        return nil
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

    private func applyParameters(to effect: EffectNode, params: FallbackToneParameters, engine: AudioEngineManager) {
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

private extension Array where Element: Equatable {
    func removingDuplicates() -> [Element] {
        var seen: [Element] = []
        for element in self {
            if !seen.contains(element) { seen.append(element) }
        }
        return seen
    }
}
