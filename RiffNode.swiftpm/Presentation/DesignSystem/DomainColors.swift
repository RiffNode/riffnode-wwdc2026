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
