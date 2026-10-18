import Foundation

// MARK: - Offline Tone Matcher
// Works out what a request means for the pedalboard without the language model – the
// fallback when Apple Intelligence isn't available, and the fast path for direct commands.
// Pure: it reads only the request and returns what changed, so it can be tested alone.

/// The outcome of a request. A nil field means "leave as it was".
struct ToneMatch {
    /// True when the request was understood and should be applied.
    var matched = false
    var mode: String?
    var explanation: String?
    var enabled: [String]?
    var disabled: [String]?
    var deleted: [String]?
    var parameters: FallbackToneParameters?
    var parameterOverrides: [String: Float]?
}

enum OfflineToneMatcher {

    static func match(_ command: String) -> ToneMatch {
        var m = ToneMatch()
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
                m.deleted = []
                m.mode = "preset"
                m.parameters = params
                m.explanation = params.explanation
                return m
            }

            let names = deleted.map { $0.capitalized }.joined(separator: ", ")
            params.explanation = "Removed \(names) from your pedalboard."
            m.deleted = deleted
            m.enabled = []
            m.disabled = []
            m.mode = commandMode
            m.parameters = params
            m.explanation = params.explanation
            m.matched = true
            return m
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
                m.parameterOverrides = [:]
                m.enabled = [result]
                m.disabled = []
                m.deleted = []
                m.mode = "set"
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            } else {
                params.explanation = "Try something like: 'set compressor threshold to -25', 'overdrive drive 70', 'chorus rate 2', 'delay time 0.4'."
                m.mode = "preset"
                m.parameters = params
                m.explanation = params.explanation
                return m
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
                m.enabled = []
                m.disabled = []
                m.mode = "preset"
                m.parameters = params
                m.explanation = params.explanation
                return m
            }

            let names = disabledEffects.map { $0.capitalized }.joined(separator: ", ")
            params.explanation = "Turned off: \(names)."
            m.enabled = []
            m.disabled = disabledEffects
            m.mode = commandMode
            m.parameters = params
            m.explanation = params.explanation
            m.matched = true
            return m
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
                return m
            }
            m.enabled = effects
            m.disabled = []
            m.mode = commandMode
            m.parameters = params
            m.explanation = params.explanation
            m.matched = true
            return m
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
                return m
            }
            m.enabled = effects
            m.disabled = []
            m.mode = commandMode
            m.parameters = params
            m.explanation = params.explanation
            m.matched = true
            return m
        }

        // ── Add a specific single effect ───────────────────────────────────
        if isAddIntent || lower.count < 20 {
            if lower.contains("reverb") {
                commandMode = "additive"
                effects = ["reverb"]
                params.reverbMix = lower.contains("more") || lower.contains("lot") ? 75 : 50
                params.reverbDecay = 2.5
                params.explanation = "Added reverb to give your tone space and depth."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("delay") || lower.contains("echo") {
                commandMode = "additive"
                effects = ["delay"]
                params.delayMix = 40
                params.delayTime = 0.35
                params.delayFeedback = 35
                params.explanation = "Added delay for rhythmic echoes and depth."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("chorus") {
                commandMode = "additive"
                effects = ["chorus"]
                params.chorusDepth = 50
                params.explanation = "Added chorus for a lush, shimmering sound."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("phaser") {
                commandMode = "additive"
                effects = ["phaser"]
                params.phaserDepth = 50
                params.explanation = "Added phaser for a sweeping, psychedelic effect."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("flanger") {
                commandMode = "additive"
                effects = ["flanger"]
                params.flangerDepth = 50
                params.explanation = "Added flanger for a metallic, jet-sweep effect."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("tremolo") {
                commandMode = "additive"
                effects = ["tremolo"]
                params.tremoloDepth = 60
                params.explanation = "Added tremolo for a pulsating, rhythmic volume effect."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("fuzz") {
                commandMode = "additive"
                effects = ["fuzz"]
                params.fuzzAmount = 70
                params.explanation = "Added fuzz for a thick, buzzy, vintage saturation."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("overdrive") || lower.contains("drive") {
                commandMode = "additive"
                effects = ["overdrive"]
                params.overdriveDrive = 50
                params.explanation = "Added overdrive for a warm, tube-like crunch."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("distortion") {
                commandMode = "additive"
                effects = ["distortion"]
                params.distortionDrive = 60
                params.explanation = "Added distortion for aggressive, hard-clipped gain."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("compressor") || lower.contains("compress") {
                commandMode = "additive"
                effects = ["compressor"]
                params.explanation = "Added compressor for tighter dynamics and more sustain."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
            }
            if lower.contains("eq") || lower.contains("equalizer") || lower.contains("bass") || lower.contains("treble") || lower.contains("mid") {
                commandMode = "additive"
                effects = ["equalizer"]
                if lower.contains("bass") { params.eqBass = lower.contains("boost") || lower.contains("more") ? 5 : 3 }
                if lower.contains("treble") || lower.contains("bright") { params.eqTreble = 4 }
                if lower.contains("mid") { params.eqMid = lower.contains("scoop") || lower.contains("cut") ? -4 : 3 }
                params.explanation = "Applied EQ adjustments to shape your frequency response."
                m.enabled = effects
                m.disabled = []
                m.mode = commandMode
                m.parameters = params
                m.explanation = params.explanation
                m.matched = true
                return m
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
            m.enabled = []
            m.disabled = []
            m.mode = "preset"
            m.parameters = params
            m.explanation = params.explanation
            return m
        }

        m.enabled = effects
        m.disabled = []
        m.mode = commandMode
        m.parameters = params
        m.explanation = params.explanation
        m.matched = true
        return m
    }

    /// Parses "set [effect] [param] to [value]" style commands.
    /// Mutates `params` in place and returns the canonical effect name, or nil if unrecognized.
    private static func parseParameterCommand(_ lower: String, params: inout FallbackToneParameters) -> String? {

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
}
