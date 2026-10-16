import SwiftUI

// MARK: - Domain Colors
// How domain types look. Kept in Presentation so the Domain layer stays free of UI frameworks.

extension EffectCategory {
    var color: Color {
        switch self {
        case .dynamics: return .riffDynamics
        case .filterPitch: return .riffFilter
        case .gainDirt: return .riffGain
        case .modulation: return .riffModulation
        case .timeAmbience: return .riffAmbience
        }
    }
}

extension EffectType {
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
}

extension EffectPreset.PresetCategory {
    var color: Color {
        switch self {
        case .clean: return .riffDynamics
        case .crunch: return .riffGain
        case .heavy: return Color(red: 0.7, green: 0.4, blue: 0.4)
        case .ambient: return .riffAmbience
        }
    }
}

extension EQBand.BandType {
    var color: Color {
        switch self {
        case .highPass: return .red
        case .lowShelf: return .orange
        case .peak: return .green
        case .highShelf: return .cyan
        case .lowPass: return .purple
        }
    }
}

extension GuideTint {
    var color: Color {
        switch self {
        case .effect(let type): type.color
        case .category(let category): category.color
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        case .white: .white
        }
    }
}

extension EffectInfoProviding {
    var color: Color { tint.color }
}

extension EffectCategoryProviding {
    var color: Color { tint.color }
}

extension AudioInputDeviceType {
    var color: Color {
        switch self {
        case .none: return .gray
        case .builtInMicrophone: return .blue
        case .usbAudioInterface: return .green
        case .headset: return .orange
        case .bluetooth: return .purple
        case .external: return .cyan
        }
    }
}

// MARK: - Stompbox Enclosures
// The paint each pedal type is famous for on a real board (generic, no brands).

extension EffectType {
    var enclosureColor: Color {
        switch self {
        case .compressor: Color(red: 0.18, green: 0.42, blue: 0.70)   // blue
        case .equalizer: Color(red: 0.82, green: 0.82, blue: 0.80)    // silver-white
        case .overdrive: Color(red: 0.24, green: 0.62, blue: 0.36)    // green
        case .distortion: Color(red: 0.94, green: 0.55, blue: 0.16)   // orange
        case .fuzz: Color(red: 0.74, green: 0.75, blue: 0.77)         // brushed silver
        case .chorus: Color(red: 0.36, green: 0.72, blue: 0.86)       // light blue
        case .phaser: Color(red: 0.88, green: 0.36, blue: 0.13)       // burnt orange
        case .flanger: Color(red: 0.42, green: 0.31, blue: 0.70)      // purple
        case .tremolo: Color(red: 0.18, green: 0.52, blue: 0.50)      // teal
        case .delay: Color(red: 0.90, green: 0.90, blue: 0.88)        // white
        case .reverb: Color(red: 0.17, green: 0.23, blue: 0.34)       // navy
        }
    }

    /// Light paint takes dark lettering, like the real thing.
    var enclosureIsLight: Bool {
        switch self {
        case .equalizer, .fuzz, .delay, .chorus: true
        default: false
        }
    }

    /// How many knobs the pedal has on top.
    var knobCount: Int {
        switch self {
        case .tremolo, .reverb: 2
        default: 3
        }
    }
}
