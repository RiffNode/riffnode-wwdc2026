import Foundation

// MARK: - Tone Recipe Book
// Turns a described sound – a style, how much gain, how much space, a few signature pedals –
// into concrete knob settings. The on-device model is good at recognising what a player
// means ("Comfortably Numb solo" → classic rock, heavy gain, huge space, delay) but poor at
// picking numbers, so the numbers come from here and are always in a musical range.

enum ToneStyle: String, CaseIterable, Sendable {
    case clean, jazz, blues, classicRock, hardRock, metal, punk, grunge, funk, country
    case surf, eighties, ambient, shoegaze, psychedelic, lofi, ballad

    var title: String {
        switch self {
        case .classicRock: "Classic rock"
        case .hardRock: "Hard rock"
        case .eighties: "80s"
        case .lofi: "Lo-fi"
        default: rawValue.capitalized
        }
    }
}

enum ToneGain: String, CaseIterable, Sendable { case clean, light, crunchy, heavy }
enum ToneSpace: String, CaseIterable, Sendable { case dry, room, hall, huge }

struct ToneSketchValues: Sendable {
    var style: ToneStyle
    var gain: ToneGain
    var space: ToneSpace
    var signaturePedals: [String]
    var reason: String
}

enum ToneRecipeBook {

    /// The pedals to switch on and their settings for a sketched sound.
    static func build(_ sketch: ToneSketchValues) -> (effects: [String], parameters: FallbackToneParameters) {
        var p = FallbackToneParameters()
        var effects: [String] = []

        // 1. Gain – which drive pedal, and how hard
        switch (sketch.gain, sketch.style) {
        case (.clean, _):
            break
        case (_, .psychedelic) where sketch.gain != .light:
            effects.append("fuzz"); p.fuzzAmount = sketch.gain == .heavy ? 80 : 60; p.fuzzTone = 55
        case (.light, _):
            effects.append("overdrive"); p.overdriveDrive = 30; p.overdriveTone = 55
        case (.crunchy, .punk), (.crunchy, .grunge):
            effects.append("distortion"); p.distortionDrive = 50; p.distortionTone = 50
        case (.crunchy, _):
            effects.append("overdrive"); p.overdriveDrive = 65; p.overdriveTone = 60
        case (.heavy, _):
            effects.append("distortion"); p.distortionDrive = sketch.style == .metal ? 88 : 75
            p.distortionTone = sketch.style == .metal ? 40 : 55
        }

        // 2. Space – reverb size
        switch sketch.space {
        case .dry:
            if sketch.style == .jazz || sketch.style == .country {
                effects.append("reverb"); p.reverbMix = 12; p.reverbDecay = 0.8
            }
        case .room: effects.append("reverb"); p.reverbMix = 25; p.reverbDecay = 1.5
        case .hall: effects.append("reverb"); p.reverbMix = 45; p.reverbDecay = 3
        case .huge: effects.append("reverb"); p.reverbMix = 70; p.reverbDecay = 6
        }

        // 3. The style's own character
        switch sketch.style {
        case .clean:
            effects.append("compressor"); p.compressorThreshold = -18; p.compressorRatio = 3
            effects.append("equalizer"); p.eqTreble = 3
        case .jazz:
            effects.append("compressor"); p.compressorThreshold = -18; p.compressorRatio = 3
            effects.append("equalizer"); p.eqBass = 2; p.eqTreble = -4
        case .blues:
            effects.append("equalizer"); p.eqMid = 3
        case .classicRock, .hardRock:
            effects.append("equalizer"); p.eqMid = 3; p.eqTreble = 1
        case .metal:
            effects.append("equalizer"); p.eqBass = 4; p.eqMid = -4; p.eqTreble = 3
            p.reverbMix = min(p.reverbMix, 18)
        case .punk, .grunge:
            effects.append("equalizer"); p.eqBass = 3; p.eqMid = sketch.style == .grunge ? -2 : 1
        case .funk:
            effects.append("compressor"); p.compressorThreshold = -24; p.compressorRatio = 6; p.compressorAttack = 5
            effects.append("equalizer"); p.eqTreble = 4; p.eqBass = -2
        case .country:
            effects.append("compressor"); p.compressorThreshold = -20; p.compressorRatio = 5
            effects.append("delay"); p.delayTime = 0.12; p.delayFeedback = 10; p.delayMix = 25
            effects.append("equalizer"); p.eqTreble = 4
        case .surf:
            effects.append("tremolo"); p.tremoloRate = 5; p.tremoloDepth = 55
            if !effects.contains("reverb") { effects.append("reverb") }
            p.reverbMix = max(p.reverbMix, 70); p.reverbDecay = max(p.reverbDecay, 3)
        case .eighties:
            effects.append("chorus"); p.chorusRate = 0.8; p.chorusDepth = 65; p.chorusMix = 55
            effects.append("delay"); p.delayTime = 0.38; p.delayFeedback = 35; p.delayMix = 35
        case .ambient:
            effects.append("delay"); p.delayTime = 0.55; p.delayFeedback = 55; p.delayMix = 45
            effects.append("chorus"); p.chorusRate = 0.4; p.chorusDepth = 40; p.chorusMix = 35
        case .shoegaze:
            effects.append("chorus"); p.chorusRate = 0.6; p.chorusDepth = 80; p.chorusMix = 60
            if !effects.contains("reverb") { effects.append("reverb") }
            p.reverbMix = max(p.reverbMix, 75); p.reverbDecay = max(p.reverbDecay, 5)
        case .psychedelic:
            effects.append("phaser"); p.phaserRate = 0.6; p.phaserDepth = 70; p.phaserFeedback = 55
        case .lofi:
            effects.append("tremolo"); p.tremoloRate = 3; p.tremoloDepth = 20
            effects.append("equalizer"); p.eqTreble = -6; p.eqBass = 2
        case .ballad:
            effects.append("compressor"); p.compressorThreshold = -16; p.compressorRatio = 3
            effects.append("delay"); p.delayTime = 0.45; p.delayFeedback = 30; p.delayMix = 25
        }

        // 4. Pedals the song is known for, on sensible settings unless the style already set them
        for pedal in sketch.signaturePedals where !effects.contains(pedal) {
            switch pedal {
            case "delay": p.delayTime = 0.42; p.delayFeedback = 40; p.delayMix = 35
            case "chorus": p.chorusRate = 0.9; p.chorusDepth = 55; p.chorusMix = 45
            case "phaser": p.phaserRate = 0.5; p.phaserDepth = 60; p.phaserFeedback = 40
            case "flanger": p.flangerRate = 0.25; p.flangerDepth = 60; p.flangerFeedback = 55
            case "tremolo": p.tremoloRate = 5; p.tremoloDepth = 55
            case "compressor": p.compressorThreshold = -20; p.compressorRatio = 4
            case "fuzz": p.fuzzAmount = 70; p.fuzzTone = 55
            case "overdrive": p.overdriveDrive = 45
            case "distortion": p.distortionDrive = 65
            case "reverb": p.reverbMix = max(p.reverbMix, 35); p.reverbDecay = max(p.reverbDecay, 2)
            default: continue
            }
            effects.append(pedal)
        }

        // Keep the count reasonable – a drive, a space and up to three colours
        effects = Array(effects.removingDuplicates().prefix(6))
        p.explanation = sketch.reason
        return (effects, p)
    }
}
