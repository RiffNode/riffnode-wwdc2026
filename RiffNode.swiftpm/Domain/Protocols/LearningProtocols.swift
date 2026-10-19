import Foundation

// MARK: - Learning Protocols
// What the Learn tab reads: effect families, the effects in them, and the service that
// provides them. The models live in Domain/Models; these are the contracts.

/// Protocol for providing effect information
/// Following Interface Segregation: Small, focused protocol
protocol EffectInfoProviding {
    var name: String { get }
    var icon: String { get }
    var tint: GuideTint { get }
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
    var tint: GuideTint { get }
    var description: String { get }
    var effects: [any EffectInfoProviding] { get }
}

/// Protocol for the effect guide service
/// Following Dependency Inversion: Depend on abstraction, not concretion
protocol EffectGuideServiceProtocol: Sendable {
    var categories: [any EffectCategoryProviding] { get }
    func category(for id: String) -> (any EffectCategoryProviding)?
}

/// Lists the effect types, all or by family.
protocol EffectTypeProviding {
    static var allEffectTypes: [EffectType] { get }
    static func effectTypes(for category: EffectCategory) -> [EffectType]
}
