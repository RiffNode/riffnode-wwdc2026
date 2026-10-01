import SwiftUI

// MARK: - Effect Guide Data Layer
// Following Clean Architecture: Separating Data from Presentation
// Following Single Responsibility Principle: Each struct has one job
// Following DRY Principle: Reusing EffectType educational content

// MARK: - Protocols (Interface Segregation & Dependency Inversion)

/// Protocol for providing effect information
/// Following Interface Segregation: Small, focused protocol
protocol EffectInfoProviding {
    var name: String { get }
    var icon: String { get }
    var color: Color { get }
    var function: String { get }
    var sound: String { get }
    var howToUse: String { get }
    var signalChainPosition: String { get }
    var famousUsers: String { get }
}

/// Protocol for effect categories
/// Following Interface Segregation: Separate protocol for categories
protocol EffectCategoryProviding {
    var name: String { get }
    var icon: String { get }
    var color: Color { get }
    var description: String { get }
    var effects: [any EffectInfoProviding] { get }
}

/// Protocol for the effect guide service
/// Following Dependency Inversion: Depend on abstraction, not concretion
protocol EffectGuideServiceProtocol: Sendable {
    var categories: [any EffectCategoryProviding] { get }
    func category(for id: String) -> (any EffectCategoryProviding)?
}

// MARK: - Domain Models

/// Effect information model
/// Following Single Responsibility: Only holds effect data
struct EffectInfoModel: EffectInfoProviding, Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let function: String
    let sound: String
    let howToUse: String
    let signalChainPosition: String
    let famousUsers: String
    /// Non-nil when this effect is available in the app's pedalboard
    let effectType: EffectType?

    /// Initialize from EffectType - reusing existing educational content
    /// Following DRY Principle
    init(from effectType: EffectType) {
        self.effectType = effectType
        self.name = effectType.rawValue
        self.icon = effectType.icon
        self.color = effectType.color
        self.function = effectType.effectDescription
        self.sound = effectType.commonGenres.joined(separator: ", ")
        self.howToUse = effectType.howToUse
        self.signalChainPosition = effectType.signalChainPosition
        self.famousUsers = effectType.famousExamples
    }

    /// Manual initialization for effects not in EffectType (educational-only)
    init(name: String, icon: String, color: Color, function: String, sound: String, howToUse: String, signalChainPosition: String, famousUsers: String) {
        self.effectType = nil
        self.name = name
        self.icon = icon
        self.color = color
        self.function = function
        self.sound = sound
        self.howToUse = howToUse
        self.signalChainPosition = signalChainPosition
        self.famousUsers = famousUsers
    }
}

/// Effect category model
/// Following Single Responsibility: Only holds category data
struct EffectCategoryModel: EffectCategoryProviding, Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let description: String
    let effects: [any EffectInfoProviding]
    
    /// Initialize from EffectCategory - reusing existing data
    init(from category: EffectCategory, effects: [any EffectInfoProviding]) {
        self.id = category.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
        self.name = category.rawValue
        self.icon = category.icon
        self.color = category.color
        self.description = category.description
        self.effects = effects
    }
    
    /// Manual initialization
    init(id: String, name: String, icon: String, color: Color, description: String, effects: [any EffectInfoProviding]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.description = description
        self.effects = effects
    }
}

// MARK: - Effect Guide Service
// Following Single Responsibility: Only provides effect guide data
// Following Open/Closed: Open for extension (new categories), closed for modification

final class EffectGuideService: EffectGuideServiceProtocol, @unchecked Sendable {
    // Note: @unchecked Sendable is safe here because:
    // 1. All properties are immutable (let)
    // 2. No mutable state after initialization
    
    // MARK: - Singleton (for simplicity in SwiftUI)
    static let shared = EffectGuideService()
    
    // MARK: - Properties
    
    let categories: [any EffectCategoryProviding]
    
    // MARK: - Initialization
    
    private init() {
        self.categories = Self.buildCategories()
    }
    
    // MARK: - Public Methods
    
    func category(for id: String) -> (any EffectCategoryProviding)? {
        categories.first { ($0 as? EffectCategoryModel)?.id == id }
    }
    
    // MARK: - Private Factory Methods
    // Following Factory Pattern for creating complex objects
    // Integrates with EffectType and EffectCategory for consistency
    
    private static func buildCategories() -> [EffectCategoryModel] {
        [
            buildDynamicsCategory(),
            buildFilterPitchCategory(),
            buildGainDirtCategory(),
            buildModulationCategory(),
            buildTimeAmbienceCategory(),
            buildUtilityCategory()
        ]
    }
    
    private static func buildDynamicsCategory() -> EffectCategoryModel {
        // Use EffectCategory for category info
        let category = EffectCategory.dynamics
        
        // Build effects from EffectType + additional educational effects
        var effects: [any EffectInfoProviding] = []
        
        // Add available pedal effects from EffectType
        effects.append(EffectInfoModel(from: .compressor))
        
        // Add additional educational effects not available as pedals
        effects.append(EffectInfoModel(
            name: "Noise Gate",
            icon: "door.left.hand.closed",
            color: .red,
            function: "Cuts off the signal when volume drops below a threshold to eliminate hum or hiss.",
            sound: "Complete silence when you aren't playing. Tight, controlled stops.",
            howToUse: "Essential for high-gain metal tones to eliminate unwanted noise between riffs.",
            signalChainPosition: "AFTER GAIN - Place after your distortion/overdrive pedals.",
            famousUsers: "Metallica, Meshuggah, any metal guitarist"
        ))
        
        effects.append(EffectInfoModel(
            name: "Boost",
            icon: "arrow.up.circle.fill",
            color: .yellow,
            function: "Increases volume without adding distortion (Clean Boost).",
            sound: "Louder, but clean. Can push amp into natural breakup.",
            howToUse: "Make solos stand out or push an amplifier into natural overdrive.",
            signalChainPosition: "FLEXIBLE - Before dirt for more gain, after for volume boost.",
            famousUsers: "Eric Johnson, Brian May"
        ))
        
        effects.append(EffectInfoModel(
            name: "Volume Pedal",
            icon: "speaker.wave.3.fill",
            color: .gray,
            function: "Controls master volume with your foot.",
            sound: "No tonal change - just volume control.",
            howToUse: "Great for 'swells' (fading in notes like a violin) or muting.",
            signalChainPosition: "FLEXIBLE - Early for swells, late for master volume.",
            famousUsers: "Ambient guitarists, pedal steel players"
        ))
        
        return EffectCategoryModel(
            from: category,
            effects: effects
        )
    }
    
    private static func buildFilterPitchCategory() -> EffectCategoryModel {
        let category = EffectCategory.filterPitch
        
        var effects: [any EffectInfoProviding] = []
        
        // Add EQ from EffectType
        effects.append(EffectInfoModel(from: .equalizer))
        
        // Add additional filter/pitch effects
        effects.append(EffectInfoModel(
            name: "Wah-Wah",
            icon: "mouth.fill",
            color: .purple,
            function: "A sweeping bandpass filter controlled by a foot treadle.",
            sound: "Mimics the human voice saying 'Wah.' Expressive and vocal-like.",
            howToUse: "Funk rhythms, expressive solos, or as a cocked (fixed) filter for unique tones.",
            signalChainPosition: "EARLY - Before or after dirt, experiment to taste.",
            famousUsers: "Jimi Hendrix, John Frusciante, Kirk Hammett"
        ))
        
        effects.append(EffectInfoModel(
            name: "Octave / Pitch Shifter",
            icon: "music.note",
            color: .blue,
            function: "Adds a synthesized note an octave above or below what you play.",
            sound: "Makes guitar sound like a bass (octave down) or synthesizer.",
            howToUse: "Bass lines on guitar, thick synth-like tones, or harmonized leads.",
            signalChainPosition: "EARLY - Before dirt for best tracking.",
            famousUsers: "Jack White, Royal Blood, Tom Morello"
        ))
        
        effects.append(EffectInfoModel(
            name: "Whammy",
            icon: "arrow.up.and.down",
            color: .red,
            function: "Pitch shifter controlled by treadle for dramatic pitch bends.",
            sound: "Dive-bombs, harmonized pitch shifts, crazy sound effects.",
            howToUse: "Extreme pitch bending without a tremolo bar.",
            signalChainPosition: "EARLY - Before other effects for clean tracking.",
            famousUsers: "Tom Morello, Dimebag Darrell, Matt Bellamy"
        ))
        
        return EffectCategoryModel(from: category, effects: effects)
    }
    
    private static func buildGainDirtCategory() -> EffectCategoryModel {
        let category = EffectCategory.gainDirt
        
        // Use EffectType for available pedal effects
        let effects: [any EffectInfoProviding] = [
            EffectInfoModel(from: .overdrive),
            EffectInfoModel(from: .distortion),
            EffectInfoModel(from: .fuzz)
        ]
        
        return EffectCategoryModel(from: category, effects: effects)
    }
    
    private static func buildModulationCategory() -> EffectCategoryModel {
        let category = EffectCategory.modulation
        
        var effects: [any EffectInfoProviding] = []
        
        // Add available modulation effects from EffectType
        effects.append(EffectInfoModel(from: .chorus))
        effects.append(EffectInfoModel(from: .phaser))
        effects.append(EffectInfoModel(from: .flanger))
        effects.append(EffectInfoModel(from: .tremolo))
        
        // Add additional modulation effects
        effects.append(EffectInfoModel(
            name: "Vibrato",
            icon: "waveform.path.ecg",
            color: .purple,
            function: "Rhythmic fluctuation in PITCH (sharp-flat-sharp-flat).",
            sound: "Wobbly, seasick pitch modulation.",
            howToUse: "Adding expression, lo-fi textures, unique character.",
            signalChainPosition: "LATE - Similar to tremolo positioning.",
            famousUsers: "Robin Guthrie, My Bloody Valentine"
        ))
        
        effects.append(EffectInfoModel(
            name: "Uni-Vibe",
            icon: "sun.max.fill",
            color: .orange,
            function: "A vintage photo-optical vibrato/phaser effect. It uses a rotating light and photocells to create a warm, organic modulation quite different from a standard phaser.",
            sound: "Throbbing, psychedelic pulse. Warmer and more organic than a typical phaser.",
            howToUse: "Classic psychedelic tones, expressive leads. Associated with 60s/70s rock.",
            signalChainPosition: "AFTER DIRT - Before time effects.",
            famousUsers: "Jimi Hendrix, Robin Trower, David Gilmour"
        ))
        
        return EffectCategoryModel(from: category, effects: effects)
    }
    
    private static func buildTimeAmbienceCategory() -> EffectCategoryModel {
        let category = EffectCategory.timeAmbience
        
        // Use EffectType for available time effects
        let effects: [any EffectInfoProviding] = [
            EffectInfoModel(from: .delay),
            EffectInfoModel(from: .reverb)
        ]
        
        return EffectCategoryModel(from: category, effects: effects)
    }
    
    private static func buildUtilityCategory() -> EffectCategoryModel {
        // Utility category not in EffectCategory enum, create manually
        let effects: [any EffectInfoProviding] = [
            EffectInfoModel(
                name: "Tuner",
                icon: "tuningfork",
                color: .white,
                function: "Keeps your guitar in pitch.",
                sound: "No sound change - mutes signal while tuning.",
                howToUse: "Essential for staying in tune during performances.",
                signalChainPosition: "FIRST - At the very start of your chain.",
                famousUsers: "Everyone!"
            ),
            EffectInfoModel(
                name: "Looper",
                icon: "repeat.circle",
                color: .green,
                function: "Records a phrase and plays it back endlessly.",
                sound: "Layers of yourself playing together.",
                howToUse: "Practice, jamming, live solo performances.",
                signalChainPosition: "LAST - After everything else to capture your full tone.",
                famousUsers: "Ed Sheeran, KT Tunstall, Tash Sultana"
            ),
            EffectInfoModel(
                name: "Buffer",
                icon: "bolt.horizontal.fill",
                color: .yellow,
                function: "Preserves signal strength and high frequencies.",
                sound: "Restores clarity lost through long cables and many pedals.",
                howToUse: "When using more than 5-6 pedals or long cable runs.",
                signalChainPosition: "FIRST and/or LAST - At chain start and end.",
                famousUsers: "Any guitarist with a large pedalboard"
            )
        ]
        
        return EffectCategoryModel(
            id: "utility",
            name: "Utility",
            icon: "wrench.and.screwdriver",
            color: .gray,
            description: "Essential tools that don't change the sound but are vital for function.",
            effects: effects
        )
    }
}
