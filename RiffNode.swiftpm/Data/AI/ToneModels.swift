import Foundation

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
