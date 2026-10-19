import SwiftUI
import Observation

// MARK: - Performance Gesture Action

/// Defines an action that can be bound to a gesture
enum PerformanceGestureAction: String, CaseIterable, Identifiable {
    case toggleFirstEffect = "Toggle First Effect"
    case toggleSecondEffect = "Toggle Second Effect"
    case previousPreset = "Previous Preset"
    case nextPreset = "Next Preset"
    case bypassAll = "Bypass All"
    case enableAll = "Enable All"
    case momentaryBoost = "Momentary Boost"
    case wahControl = "Wah Control"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .toggleFirstEffect: return "1.circle.fill"
        case .toggleSecondEffect: return "2.circle.fill"
        case .previousPreset: return "chevron.left.circle"
        case .nextPreset: return "chevron.right.circle"
        case .bypassAll: return "slash.circle"
        case .enableAll: return "checkmark.circle"
        case .momentaryBoost: return "bolt.fill"
        case .wahControl: return "waveform.path"
        }
    }
}

// MARK: - Performance Mode Controller

/// Manages the performance mode state and gesture bindings
@Observable
@MainActor
final class PerformanceModeController {

    // MARK: - State

    private(set) var isActive = false
    private(set) var wahPosition: Float = 0
    private(set) var lastTriggeredGesture: FaceGesture?
    private(set) var lastTriggeredAction: PerformanceGestureAction?

    // Momentary boost state
    private(set) var isBoostActive = false
    private var preBoostLevels: [UUID: Float] = [:]

    // All effects bypass state
    private(set) var allBypassed = false

    // Current preset index for preset navigation
    var currentPresetIndex: Int = 0

    // MARK: - Gesture Bindings

    /// Map gestures to actions – the same ones the gesture guide and notch describe
    var gestureBindings: [FaceGesture: PerformanceGestureAction] = [
        .headNodDown: .nextPreset,
        .headNodUp: .previousPreset,
        .headTiltLeft: .bypassAll,
        .headTiltRight: .enableAll,
        .mouthOpen: .wahControl,
        .eyebrowRaise: .momentaryBoost
    ]

    // MARK: - Activate/Deactivate

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
        // Reset states
        wahPosition = 0
        lastTriggeredGesture = nil
        lastTriggeredAction = nil
        isBoostActive = false
        allBypassed = false
    }

    // MARK: - Handle Gestures

    /// Handle a detected gesture and execute the bound action
    func handleGesture(_ gesture: FaceGesture, engine: any EffectsChainManaging & ExpressionControlling, presets: [EffectPreset] = []) {
        guard isActive else { return }

        lastTriggeredGesture = gesture

        guard let action = gestureBindings[gesture] else { return }
        lastTriggeredAction = action

        executeAction(action, engine: engine, presets: presets)
    }

    /// Execute a specific action
    private func executeAction(_ action: PerformanceGestureAction, engine: any EffectsChainManaging & ExpressionControlling, presets: [EffectPreset]) {
        switch action {
        case .toggleFirstEffect:
            if let firstEffect = engine.effectsChain.first {
                engine.toggleEffect(firstEffect)
            }

        case .toggleSecondEffect:
            if engine.effectsChain.count > 1 {
                engine.toggleEffect(engine.effectsChain[1])
            }

        case .previousPreset:
            guard !presets.isEmpty else { return }
            currentPresetIndex = (currentPresetIndex - 1 + presets.count) % presets.count
            engine.applyPreset(presets[currentPresetIndex])

        case .nextPreset:
            guard !presets.isEmpty else { return }
            currentPresetIndex = (currentPresetIndex + 1) % presets.count
            engine.applyPreset(presets[currentPresetIndex])

        case .bypassAll:
            toggleBypassAll(engine: engine)

        case .enableAll:
            enableAllEffects(engine: engine)

        case .momentaryBoost:
            toggleMomentaryBoost(engine: engine)

        case .wahControl:
            // Handled via continuous mouth value updates
            break
        }
    }

    // MARK: - Wah/Expression Control

    /// Update wah position from mouth openness (0.0 to 1.0)
    func updateWahPosition(_ value: Float) {
        wahPosition = value
    }

    // MARK: - Bypass All

    /// Bypasses the whole board at once – each pedal keeps its own on/off state.
    func toggleBypassAll(engine: any EffectsChainManaging) {
        engine.isPedalboardBypassed.toggle()
        allBypassed = engine.isPedalboardBypassed
    }

    private func enableAllEffects(engine: any EffectsChainManaging & ExpressionControlling) {
        engine.isPedalboardBypassed = false
        for effect in engine.effectsChain where !effect.isEnabled {
            engine.toggleEffect(effect)
        }
        allBypassed = false
    }

    // MARK: - Momentary Boost

    func toggleMomentaryBoost(engine: any EffectsChainManaging & ExpressionControlling) {
        if isBoostActive {
            // Restore previous levels
            for effect in engine.effectsChain {
                if let previousLevel = preBoostLevels[effect.id] {
                    switch effect.type {
                    case .distortion, .overdrive, .fuzz:
                        engine.updateEffectParameter(effect, key: "level", value: previousLevel)
                    default:
                        break
                    }
                }
            }
            preBoostLevels.removeAll()
            isBoostActive = false
        } else {
            // Save current levels and boost
            preBoostLevels.removeAll()
            for effect in engine.effectsChain where effect.isEnabled {
                switch effect.type {
                case .distortion, .overdrive, .fuzz:
                    let currentLevel = effect.parameters["level"] ?? 50
                    preBoostLevels[effect.id] = currentLevel
                    // Boost by 20%
                    let boostedLevel = min(100, currentLevel * 1.2)
                    engine.updateEffectParameter(effect, key: "level", value: boostedLevel)
                default:
                    break
                }
            }
            isBoostActive = true
        }
    }
}
