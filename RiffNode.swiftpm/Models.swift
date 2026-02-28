import SwiftUI
import Observation

// MARK: - Domain Models
// Following Clean Architecture: Domain Layer
// Following Single Responsibility Principle: Each model represents one concept

// MARK: - Effect Category

/// Categories of guitar effects following industry-standard groupings
/// Following Open/Closed Principle: New categories can be added without modifying existing code
enum EffectCategory: String, CaseIterable, Identifiable, Sendable {
    case dynamics = "Dynamics"
    case filterPitch = "Filter & Pitch"
    case gainDirt = "Gain / Dirt"
    case modulation = "Modulation"
    case timeAmbience = "Time & Ambience"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        // Simple category indicators
        case .dynamics: return "d.circle"
        case .filterPitch: return "f.circle"
        case .gainDirt: return "g.circle"
        case .modulation: return "m.circle"
        case .timeAmbience: return "t.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .dynamics: return .riffDynamics
        case .filterPitch: return .riffFilter
        case .gainDirt: return .riffGain
        case .modulation: return .riffModulation
        case .timeAmbience: return .riffAmbience
        }
    }
    
    var description: String {
        switch self {
        case .dynamics:
            return "Control the volume and consistency of your signal."
        case .filterPitch:
            return "Alter the frequencies or musical pitch of your notes."
        case .gainDirt:
            return "Simulate the sound of an amplifier being pushed to its limit."
        case .modulation:
            return "Add movement, width, or a swirling quality to the sound."
        case .timeAmbience:
            return "Simulate physical space and echoes."
        }
    }
}

// MARK: - Effect Type

/// Represents the type of audio effect available in the signal chain
/// Following Interface Segregation: Each effect type knows its own properties
enum EffectType: String, CaseIterable, Identifiable, Codable, Sendable {
    // Dynamics
    case compressor = "Compressor"
    
    // Filter & Pitch
    case equalizer = "EQ"
    
    // Gain / Dirt
    case overdrive = "Overdrive"
    case distortion = "Distortion"
    case fuzz = "Fuzz"
    
    // Modulation
    case chorus = "Chorus"
    case phaser = "Phaser"
    case flanger = "Flanger"
    case tremolo = "Tremolo"
    
    // Time & Ambience
    case delay = "Delay"
    case reverb = "Reverb"

    var id: String { rawValue }
    
    // MARK: - Category
    
    var category: EffectCategory {
        switch self {
        case .compressor:
            return .dynamics
        case .equalizer:
            return .filterPitch
        case .overdrive, .distortion, .fuzz:
            return .gainDirt
        case .chorus, .phaser, .flanger, .tremolo:
            return .modulation
        case .delay, .reverb:
            return .timeAmbience
        }
    }

    var icon: String {
        switch self {
        // Simple, clean icons
        case .compressor: return "c.circle.fill"
        case .equalizer: return "e.circle.fill"
        case .overdrive: return "o.circle.fill"
        case .distortion: return "d.circle.fill"
        case .fuzz: return "f.circle.fill"
        case .chorus: return "c.circle.fill"
        case .phaser: return "p.circle.fill"
        case .flanger: return "f.circle.fill"
        case .tremolo: return "t.circle.fill"
        case .delay: return "d.circle.fill"
        case .reverb: return "r.circle.fill"
        }
    }

    /// Short abbreviation for the effect
    var abbreviation: String {
        switch self {
        case .compressor: return "CMP"
        case .equalizer: return "EQ"
        case .overdrive: return "OD"
        case .distortion: return "DST"
        case .fuzz: return "FZ"
        case .chorus: return "CHR"
        case .phaser: return "PHS"
        case .flanger: return "FLG"
        case .tremolo: return "TRM"
        case .delay: return "DLY"
        case .reverb: return "REV"
        }
    }

    var color: Color {
        switch self {
        case .compressor: return .riffDynamics
        case .equalizer: return .riffFilter
        case .overdrive: return .riffGain
        case .distortion: return .riffGain
        case .fuzz: return Color(red: 0.7, green: 0.45, blue: 0.55) // Warm rose
        case .chorus: return .riffModulation
        case .phaser: return .riffModulation
        case .flanger: return .riffModulation
        case .tremolo: return Color(red: 0.65, green: 0.5, blue: 0.6) // Soft mauve
        case .delay: return .riffAmbience
        case .reverb: return .riffAmbience
        }
    }

    var defaultParameters: [String: Float] {
        switch self {
        case .compressor:
            return ["threshold": -20, "ratio": 4, "attack": 10, "release": 100]
        case .equalizer:
            return ["bass": 0, "mid": 0, "treble": 0]
        case .overdrive:
            return ["drive": 30, "tone": 50, "level": 50]
        case .distortion:
            return ["drive": 50, "tone": 50, "level": 50]
        case .fuzz:
            return ["fuzz": 70, "tone": 50, "level": 50]
        case .chorus:
            return ["rate": 1.0, "depth": 50, "mix": 50]
        case .phaser:
            return ["rate": 0.5, "depth": 50, "feedback": 30]
        case .flanger:
            return ["rate": 0.3, "depth": 50, "feedback": 50]
        case .tremolo:
            return ["rate": 5.0, "depth": 50]
        case .delay:
            return ["time": 0.3, "feedback": 40, "mix": 30]
        case .reverb:
            return ["wetDryMix": 40, "decay": 1.5]
        }
    }
    
    // MARK: - Signal Chain Position
    
    /// Recommended order in signal chain (lower = earlier)
    var recommendedOrder: Int {
        switch self {
        case .fuzz: return 0        // Vintage fuzz pedals are buffer-sensitive — first in chain
        case .compressor: return 1
        case .equalizer: return 2
        case .overdrive: return 3
        case .distortion: return 4
        case .phaser: return 5
        case .chorus: return 6
        case .flanger: return 7
        case .tremolo: return 8
        case .delay: return 9
        case .reverb: return 10
        }
    }
    
    // MARK: - Educational Content
    
    /// What this effect does
    var effectDescription: String {
        switch self {
        case .compressor:
            return "Compressor squashes the dynamic range - makes loud sounds quieter and quiet sounds louder. Increases sustain and makes the tone sound 'tight' and percussive."
        case .equalizer:
            return "EQ (Equalizer) adjusts the balance of frequencies in your signal. Use it to cut muddy frequencies or boost presence in your tone."
        case .overdrive:
            return "Overdrive provides soft clipping that simulates a tube amp turned up loud. Warm, natural, and dynamic - responds to your playing dynamics."
        case .distortion:
            return "Distortion clips the audio signal harder for aggressive, compressed, saturated tone. More aggressive than overdrive with consistent gain regardless of dynamics."
        case .fuzz:
            return "Fuzz creates square wave clipping for woolly, buzzing, thick tone. Sounds like a broken speaker (in a good way). Thick and sustaining."
        case .chorus:
            return "Chorus simulates multiple instruments playing slightly out of tune. Creates a lush, watery, shimmering sound that adds width and depth."
        case .phaser:
            return "Phaser creates a sweeping, whooshing sound by phase cancellation. Like a jet plane passing by, but smoother and more musical."
        case .flanger:
            return "Flanger is similar to phaser but more metallic and intense. Creates the dramatic 'jet plane' swooshing effect."
        case .tremolo:
            return "Tremolo creates rhythmic fluctuation in VOLUME (loud-soft-loud-soft). Produces a pulsating, hypnotic sound."
        case .delay:
            return "Delay repeats the note you played (echo). Digital delay gives crisp, exact repeats while analog/tape gives warm, degrading repeats."
        case .reverb:
            return "Reverb simulates the natural decay of sound in a space. Makes your guitar sound like it's playing in a room, hall, or cathedral."
        }
    }
    
    /// How to use this effect
    var howToUse: String {
        switch self {
        case .compressor:
            return "Use for consistent volume, increased sustain, or to add 'punch' to your clean tone. Essential for J-Pop/Rock clean tones."
        case .equalizer:
            return "Cut frequencies that sound bad before boosting what sounds good. Reduce bass if muddy, boost mids to cut through, add treble for clarity."
        case .overdrive:
            return "Main rhythm tone for rock, blues. Start with low drive and increase to taste. Stacks well with other pedals."
        case .distortion:
            return "Hard rock rhythms, searing leads, heavy riffs. Works great for consistent high-gain tones."
        case .fuzz:
            return "Psychedelic rock, garage rock, or thick wall-of-sound solos. Often sounds best FIRST in chain."
        case .chorus:
            return "Clean tones, 80s sounds, adding shimmer to cleans. Great for arpeggios and clean passages."
        case .phaser:
            return "Funky rhythms, psychedelic leads, adding movement. Works on both clean and dirty tones."
        case .flanger:
            return "Special effects, psychedelic moments, dramatic transitions. Use sparingly for maximum impact."
        case .tremolo:
            return "Surf rock, ambient textures, rhythmic patterns. Classic effect for vintage tones."
        case .delay:
            return "Adding depth, rhythmic patterns, ambient textures. Set time to match your song's tempo."
        case .reverb:
            return "Use small amounts (20-40%) for natural room sound. Increase for ambient, atmospheric tones. Less is often more!"
        }
    }
    
    /// Where this effect should go in the signal chain
    var signalChainPosition: String {
        switch self {
        case .compressor:
            return "FIRST - Place at the very beginning of your chain for consistent dynamics."
        case .equalizer:
            return "FLEXIBLE - Can go early (tone shaping) or late (final adjustment). Try both!"
        case .overdrive, .distortion:
            return "EARLY - After dynamics, before modulation and time effects."
        case .fuzz:
            return "VERY EARLY - Often sounds best first in chain, even before tuner."
        case .chorus, .phaser, .flanger:
            return "AFTER DIRT - In the modulation section of your chain."
        case .tremolo:
            return "LATE - After modulation, before or after delay/reverb."
        case .delay:
            return "LATE - After dirt and modulation, before or after reverb."
        case .reverb:
            return "LAST - Final effect in the chain for natural ambience."
        }
    }
    
    /// Music genres that commonly use this effect
    var commonGenres: [String] {
        switch self {
        case .compressor:
            return ["Country", "J-Pop/Rock", "Funk", "Clean Styles"]
        case .equalizer:
            return ["All genres - essential for tone shaping"]
        case .overdrive:
            return ["Blues", "Rock", "Country", "J-Pop"]
        case .distortion:
            return ["Rock", "Metal", "Punk", "Grunge"]
        case .fuzz:
            return ["Psychedelic", "Garage Rock", "Stoner Rock"]
        case .chorus:
            return ["80s Rock", "Pop", "Shoegaze", "Clean Styles"]
        case .phaser:
            return ["Funk", "Psychedelic", "Progressive Rock"]
        case .flanger:
            return ["Rock", "Metal Solos", "Psychedelic"]
        case .tremolo:
            return ["Surf Rock", "Ambient", "Indie", "Vintage"]
        case .delay:
            return ["Ambient", "Post-Rock", "Country", "U2-style"]
        case .reverb:
            return ["Ambient", "Shoegaze", "Surf Rock", "Jazz"]
        }
    }
    
    /// Famous songs/artists known for this effect
    var famousExamples: String {
        switch self {
        case .compressor:
            return "David Gilmour, Tame Impala, Country players, Mrs. GREEN APPLE"
        case .equalizer:
            return "Every professional guitarist uses EQ to shape their signature tone"
        case .overdrive:
            return "Stevie Ray Vaughan, John Mayer, Eric Clapton, AC/DC (amp-driven crunch)"
        case .distortion:
            return "Metallica, Nirvana (Kurt Cobain's Boss DS-1), Smashing Pumpkins, Green Day"
        case .fuzz:
            return "Jimi Hendrix, Jack White, The Black Keys"
        case .chorus:
            return "Nirvana 'Come As You Are', The Police, 80s everything"
        case .phaser:
            return "Van Halen 'Eruption', Pink Floyd, Tame Impala"
        case .flanger:
            return "Eddie Van Halen, Heart 'Barracuda'"
        case .tremolo:
            return "Dick Dale (Surf Rock), My Bloody Valentine, Green Day 'Boulevard of Broken Dreams'"
        case .delay:
            return "U2 'Where The Streets Have No Name', Pink Floyd"
        case .reverb:
            return "Dick Dale (Surf), My Bloody Valentine, Ambient artists"
        }
    }
}

// MARK: - Effect Type Provider Protocol
// Following Dependency Inversion: Provide effect types through abstraction

protocol EffectTypeProviding {
    static var allEffectTypes: [EffectType] { get }
    static func effectTypes(for category: EffectCategory) -> [EffectType]
}

extension EffectType: EffectTypeProviding {
    static var allEffectTypes: [EffectType] {
        EffectType.allCases
    }
    
    static func effectTypes(for category: EffectCategory) -> [EffectType] {
        EffectType.allCases.filter { $0.category == category }
    }
}

// MARK: - Effect Node

/// Represents a single effect in the signal chain
/// Observable to allow UI to react to parameter changes
/// Following Single Responsibility: Only manages effect state
@Observable
final class EffectNode: Identifiable, @unchecked Sendable {
    let id: UUID
    let type: EffectType
    var isEnabled: Bool
    var parameters: [String: Float]

    init(id: UUID = UUID(), type: EffectType, isEnabled: Bool = true, parameters: [String: Float]? = nil) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
        self.parameters = parameters ?? type.defaultParameters
    }

    /// Creates a copy of this effect node
    func copy() -> EffectNode {
        EffectNode(type: type, isEnabled: isEnabled, parameters: parameters)
    }
}

// MARK: - Effect Preset

/// Represents a preset configuration of effects
/// Following Single Responsibility: Only holds preset data
struct EffectPreset: Identifiable, Hashable {
    let id: UUID
    let name: String
    let icon: String
    let description: String
    let effects: [PresetEffect]
    let category: PresetCategory

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        description: String,
        effects: [PresetEffect],
        category: PresetCategory
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.effects = effects
        self.category = category
    }

    enum PresetCategory: String, CaseIterable {
        case clean = "Clean"
        case crunch = "Crunch"
        case heavy = "Heavy"
        case ambient = "Ambient"

        var color: Color {
            switch self {
            case .clean: return .riffDynamics
            case .crunch: return .riffGain
            case .heavy: return Color(red: 0.7, green: 0.4, blue: 0.4)
            case .ambient: return .riffAmbience
            }
        }
    }

    struct PresetEffect: Hashable {
        let type: EffectType
        let isEnabled: Bool
        let parameters: [String: Float]

        func toEffectNode() -> EffectNode {
            EffectNode(type: type, isEnabled: isEnabled, parameters: parameters)
        }
    }
}

// MARK: - Audio Visualization Data

/// Data structure for audio visualization
/// Following Single Responsibility: Only holds visualization data
struct AudioVisualizationData {
    var waveformSamples: [Float]
    var inputLevel: Float
    var outputLevel: Float

    static let empty = AudioVisualizationData(
        waveformSamples: Array(repeating: 0, count: 128),
        inputLevel: 0,
        outputLevel: 0
    )
}

// MARK: - Waveform Sample (for Charts)

struct WaveformSample: Identifiable {
    let id: Int
    let amplitude: Float
}

// MARK: - Audio Engine State

/// Represents the current state of the audio engine
/// Following Single Responsibility: Only holds engine state
struct AudioEngineState {
    var isRunning: Bool
    var hasPermission: Bool
    var errorMessage: String?

    static let initial = AudioEngineState(
        isRunning: false,
        hasPermission: false,
        errorMessage: nil
    )
}

// MARK: - Backing Track State

/// Represents the current state of backing track playback
/// Following Single Responsibility: Only holds backing track state
struct BackingTrackState {
    var isPlaying: Bool
    var isLoaded: Bool
    var trackName: String?
    var volume: Float

    static let initial = BackingTrackState(
        isPlaying: false,
        isLoaded: false,
        trackName: nil,
        volume: 0.5
    )
}
