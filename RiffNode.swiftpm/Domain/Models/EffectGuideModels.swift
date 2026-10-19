import Foundation

// MARK: - Effect Guide Models
// What the Learn tab teaches. Domain types: colours are named by GuideTint and resolved in Presentation.
// Following Single Responsibility Principle: Each struct has one job
// Following DRY Principle: Reusing EffectType educational content

// MARK: - Domain Models

/// Effect information model
/// Following Single Responsibility: Only holds effect data
struct EffectInfoModel: EffectInfoProviding, Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let tint: GuideTint
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
        self.tint = .effect(effectType)
        self.function = effectType.effectDescription
        self.sound = effectType.commonGenres.joined(separator: ", ")
        self.howToUse = effectType.howToUse
        self.signalChainPosition = effectType.signalChainPosition
        self.famousUsers = effectType.famousExamples
    }

    /// Manual initialization for effects not in EffectType (educational-only)
    init(name: String, icon: String, tint: GuideTint, function: String, sound: String, howToUse: String, signalChainPosition: String, famousUsers: String) {
        self.effectType = nil
        self.name = name
        self.icon = icon
        self.tint = tint
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
    let tint: GuideTint
    let description: String
    let effects: [any EffectInfoProviding]
    
    /// Initialize from EffectCategory - reusing existing data
    init(from category: EffectCategory, effects: [any EffectInfoProviding]) {
        self.id = category.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
        self.name = category.rawValue
        self.icon = category.icon
        self.tint = .category(category)
        self.description = category.description
        self.effects = effects
    }
    
    /// Manual initialization
    init(id: String, name: String, icon: String, tint: GuideTint, description: String, effects: [any EffectInfoProviding]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.tint = tint
        self.description = description
        self.effects = effects
    }
}

// MARK: - Guide Tint

/// A colour name for guide content, resolved to a real colour by the Presentation layer.
enum GuideTint: Sendable {
    case effect(EffectType)
    case category(EffectCategory)
    case red, orange, yellow, green, blue, purple, gray, white
}
