import SwiftUI
import Observation

// MARK: - Effects Chain View Model

/// Handles effects chain manipulation logic
@Observable
@MainActor
final class EffectsChainViewModel {

    // MARK: - State

    var selectedEffect: EffectNode?

    // MARK: - Dependencies

    private let effectsManager: EffectsChainManaging

    // MARK: - Initialization

    init(effectsManager: EffectsChainManaging) {
        self.effectsManager = effectsManager
    }

    // MARK: - Computed Properties

    var effects: [EffectNode] {
        effectsManager.effectsChain
    }

    var availableEffectTypes: [EffectType] {
        EffectType.allCases
    }

    // MARK: - Actions

    func addEffect(_ type: EffectType) {
        withAnimation(.spring(duration: 0.3)) {
            effectsManager.addEffect(type)
        }
    }

    func removeEffect(at index: Int) {
        withAnimation {
            if selectedEffect?.id == effects[safe: index]?.id {
                selectedEffect = nil
            }
            effectsManager.removeEffect(at: index)
        }
    }

    func moveEffect(from source: IndexSet, to destination: Int) {
        withAnimation(.spring(duration: 0.3)) {
            effectsManager.moveEffect(from: source, to: destination)
        }
    }

    func toggleEffect(_ effect: EffectNode) {
        effectsManager.toggleEffect(effect)
    }

    func updateParameter(_ effect: EffectNode, key: String, value: Float) {
        effectsManager.updateEffectParameter(effect, key: key, value: value)
    }

    func selectEffect(_ effect: EffectNode?) {
        withAnimation(.spring(duration: 0.3)) {
            if selectedEffect?.id == effect?.id {
                selectedEffect = nil
            } else {
                selectedEffect = effect
            }
        }
    }

    func isSelected(_ effect: EffectNode) -> Bool {
        selectedEffect?.id == effect.id
    }

    func parameterBinding(for effect: EffectNode, key: String) -> Binding<Float> {
        Binding(
            get: { effect.parameters[key] ?? 0 },
            set: { [weak self] newValue in
                self?.updateParameter(effect, key: key, value: newValue)
            }
        )
    }
}
