import Foundation

// MARK: - Preset Service
// Following Clean Architecture: Application Layer
// Following Single Responsibility Principle: Only manages presets
// Following Open/Closed Principle: Can be extended with new preset sources

/// Service for managing effect presets
/// Protocol-based for Dependency Inversion
final class PresetService: PresetProviding {

    // MARK: - Properties

    private(set) var presets: [EffectPreset]

    // MARK: - Initialization

    init(presets: [EffectPreset]? = nil) {
        self.presets = presets ?? PresetService.builtInPresets
    }

    // MARK: - PresetProviding

    func preset(for id: UUID) -> EffectPreset? {
        presets.first { $0.id == id }
    }

    func presets(for category: EffectPreset.PresetCategory) -> [EffectPreset] {
        presets.filter { $0.category == category }
    }

    // MARK: - Preset Management

    func addPreset(_ preset: EffectPreset) {
        presets.append(preset)
    }

    func removePreset(id: UUID) {
        presets.removeAll { $0.id == id }
    }

    // MARK: - Built-in Presets
    // Following Factory Pattern for preset creation

    static let builtInPresets: [EffectPreset] = [
        // Clean Presets
        EffectPreset(
            name: "Clean & Clear",
            icon: "sparkles",
            description: "Crystal clear tone with subtle reverb",
            effects: [
                EffectPreset.PresetEffect(type: .compressor, isEnabled: true, parameters: ["threshold": -15, "ratio": 3, "attack": 20]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 20, "decay": 1.0])
            ],
            category: .clean
        ),
        EffectPreset(
            name: "Slapback Echo",
            icon: "waveform.path",
            description: "Vintage rockabilly slapback",
            effects: [
                EffectPreset.PresetEffect(type: .compressor, isEnabled: true, parameters: ["threshold": -10, "ratio": 2, "attack": 10]),
                EffectPreset.PresetEffect(type: .delay, isEnabled: true, parameters: ["time": 0.12, "feedback": 10, "mix": 35])
            ],
            category: .clean
        ),
        EffectPreset(
            name: "80s Clean",
            icon: "person.3.fill",
            description: "Shimmering clean tone with chorus",
            effects: [
                EffectPreset.PresetEffect(type: .compressor, isEnabled: true, parameters: ["threshold": -12, "ratio": 3, "attack": 15]),
                EffectPreset.PresetEffect(type: .chorus, isEnabled: true, parameters: ["rate": 1.5, "depth": 60, "mix": 50]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 30, "decay": 1.5])
            ],
            category: .clean
        ),
        
        // Crunch Presets
        EffectPreset(
            name: "Warm Blues",
            icon: "sun.max.fill",
            description: "Warm overdrive with smooth delay",
            effects: [
                EffectPreset.PresetEffect(type: .compressor, isEnabled: true, parameters: ["threshold": -15, "ratio": 4, "attack": 20]),
                EffectPreset.PresetEffect(type: .overdrive, isEnabled: true, parameters: ["drive": 40, "tone": 55, "level": 50]),
                EffectPreset.PresetEffect(type: .delay, isEnabled: true, parameters: ["time": 0.4, "feedback": 25, "mix": 20]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 25, "decay": 1.2])
            ],
            category: .crunch
        ),
        EffectPreset(
            name: "Classic Rock",
            icon: "bolt.fill",
            description: "Punchy distortion for rock tones",
            effects: [
                EffectPreset.PresetEffect(type: .distortion, isEnabled: true, parameters: ["drive": 55, "tone": 50, "level": 55]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 30, "decay": 1.0])
            ],
            category: .crunch
        ),
        EffectPreset(
            name: "Crunch Time",
            icon: "guitars.fill",
            description: "Edge of breakup tone",
            effects: [
                EffectPreset.PresetEffect(type: .overdrive, isEnabled: true, parameters: ["drive": 35, "tone": 60, "level": 50]),
                EffectPreset.PresetEffect(type: .equalizer, isEnabled: true, parameters: ["bass": 1, "mid": 2, "treble": 1])
            ],
            category: .crunch
        ),
        EffectPreset(
            name: "Funky Phaser",
            icon: "circle.hexagongrid.fill",
            description: "70s funk with phaser and light overdrive",
            effects: [
                EffectPreset.PresetEffect(type: .compressor, isEnabled: true, parameters: ["threshold": -12, "ratio": 4, "attack": 10]),
                EffectPreset.PresetEffect(type: .overdrive, isEnabled: true, parameters: ["drive": 25, "tone": 45, "level": 45]),
                EffectPreset.PresetEffect(type: .phaser, isEnabled: true, parameters: ["rate": 0.8, "depth": 70, "feedback": 40])
            ],
            category: .crunch
        ),
        
        // Heavy Presets
        EffectPreset(
            name: "Metal Zone",
            icon: "flame.fill",
            description: "High gain for heavy riffs",
            effects: [
                EffectPreset.PresetEffect(type: .distortion, isEnabled: true, parameters: ["drive": 85, "tone": 55, "level": 60]),
                EffectPreset.PresetEffect(type: .equalizer, isEnabled: true, parameters: ["bass": 3, "mid": -2, "treble": 4]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 15, "decay": 0.8])
            ],
            category: .heavy
        ),
        EffectPreset(
            name: "Fuzz Face",
            icon: "cloud.fill",
            description: "Classic psychedelic fuzz tone",
            effects: [
                EffectPreset.PresetEffect(type: .fuzz, isEnabled: true, parameters: ["fuzz": 75, "tone": 45, "level": 55]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 35, "decay": 1.5])
            ],
            category: .heavy
        ),
        EffectPreset(
            name: "Djent Machine",
            icon: "bolt.horizontal.fill",
            description: "Tight, percussive modern metal",
            effects: [
                EffectPreset.PresetEffect(type: .compressor, isEnabled: true, parameters: ["threshold": -20, "ratio": 8, "attack": 5]),
                EffectPreset.PresetEffect(type: .distortion, isEnabled: true, parameters: ["drive": 70, "tone": 60, "level": 55]),
                EffectPreset.PresetEffect(type: .equalizer, isEnabled: true, parameters: ["bass": 2, "mid": 3, "treble": 2])
            ],
            category: .heavy
        ),
        
        // Ambient Presets
        EffectPreset(
            name: "Ambient Dreams",
            icon: "moon.stars.fill",
            description: "Spacious delays and lush reverb",
            effects: [
                EffectPreset.PresetEffect(type: .chorus, isEnabled: true, parameters: ["rate": 0.5, "depth": 40, "mix": 30]),
                EffectPreset.PresetEffect(type: .delay, isEnabled: true, parameters: ["time": 0.6, "feedback": 50, "mix": 40]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 70, "decay": 3.0])
            ],
            category: .ambient
        ),
        EffectPreset(
            name: "Shimmer",
            icon: "star.fill",
            description: "Ethereal ambient soundscape",
            effects: [
                EffectPreset.PresetEffect(type: .tremolo, isEnabled: true, parameters: ["rate": 3.0, "depth": 30]),
                EffectPreset.PresetEffect(type: .delay, isEnabled: true, parameters: ["time": 0.8, "feedback": 60, "mix": 35]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 80, "decay": 4.0])
            ],
            category: .ambient
        ),
        EffectPreset(
            name: "Surf Rock",
            icon: "water.waves",
            description: "Classic surf guitar with tremolo and reverb",
            effects: [
                EffectPreset.PresetEffect(type: .tremolo, isEnabled: true, parameters: ["rate": 6.0, "depth": 60]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 55, "decay": 2.0])
            ],
            category: .ambient
        ),
        EffectPreset(
            name: "Shoegaze",
            icon: "cloud.fog.fill",
            description: "Wall of sound with modulation and reverb",
            effects: [
                EffectPreset.PresetEffect(type: .fuzz, isEnabled: true, parameters: ["fuzz": 50, "tone": 40, "level": 45]),
                EffectPreset.PresetEffect(type: .chorus, isEnabled: true, parameters: ["rate": 0.8, "depth": 70, "mix": 50]),
                EffectPreset.PresetEffect(type: .flanger, isEnabled: true, parameters: ["rate": 0.2, "depth": 40, "feedback": 30]),
                EffectPreset.PresetEffect(type: .delay, isEnabled: true, parameters: ["time": 0.5, "feedback": 45, "mix": 35]),
                EffectPreset.PresetEffect(type: .reverb, isEnabled: true, parameters: ["wetDryMix": 75, "decay": 3.5])
            ],
            category: .ambient
        )
    ]
}

// MARK: - Preset Factory
// Following Factory Pattern for creating presets from effect chains

extension PresetService {

    /// Creates a preset from the current effects chain
    static func createPreset(
        name: String,
        description: String,
        icon: String,
        category: EffectPreset.PresetCategory,
        from effectsChain: [EffectNode]
    ) -> EffectPreset {
        let presetEffects = effectsChain.map { node in
            EffectPreset.PresetEffect(
                type: node.type,
                isEnabled: node.isEnabled,
                parameters: node.parameters
            )
        }

        return EffectPreset(
            name: name,
            icon: icon,
            description: description,
            effects: presetEffects,
            category: category
        )
    }
}
