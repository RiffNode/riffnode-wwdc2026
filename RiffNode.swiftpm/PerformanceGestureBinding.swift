import SwiftUI
import Observation

// MARK: - Notification Names

extension Notification.Name {
    static let enterPerformanceMode = Notification.Name("enterPerformanceMode")
    static let exitPerformanceMode = Notification.Name("exitPerformanceMode")
}

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
    private(set) var lastTriggeredGesture: VisionGestureController.Gesture?
    private(set) var lastTriggeredAction: PerformanceGestureAction?

    // Momentary boost state
    private(set) var isBoostActive = false
    private var preBoostLevels: [UUID: Float] = [:]

    // All effects bypass state
    private(set) var allBypassed = false
    private var preBypassStates: [UUID: Bool] = [:]

    // Current preset index for preset navigation
    var currentPresetIndex: Int = 0

    // MARK: - Gesture Bindings

    /// Map gestures to actions
    var gestureBindings: [VisionGestureController.Gesture: PerformanceGestureAction] = [
        .headNodDown: .toggleFirstEffect,
        .headNodUp: .previousPreset,
        .headTiltLeft: .bypassAll,
        .headTiltRight: .toggleSecondEffect,
        .mouthOpen: .wahControl,
        .eyebrowRaise: .momentaryBoost
    ]

    // MARK: - Activate/Deactivate

    func activate() {
        isActive = true
        print("PerformanceModeController: Activated")
    }

    func deactivate() {
        isActive = false
        // Reset states
        wahPosition = 0
        lastTriggeredGesture = nil
        lastTriggeredAction = nil
        isBoostActive = false
        allBypassed = false
        print("PerformanceModeController: Deactivated")
    }

    // MARK: - Handle Gestures

    /// Handle a detected gesture and execute the bound action
    func handleGesture(_ gesture: VisionGestureController.Gesture, engine: AudioEngineManager, presets: [EffectPreset] = []) {
        guard isActive else { return }

        lastTriggeredGesture = gesture

        guard let action = gestureBindings[gesture] else { return }
        lastTriggeredAction = action

        executeAction(action, engine: engine, presets: presets)
    }

    /// Execute a specific action
    private func executeAction(_ action: PerformanceGestureAction, engine: AudioEngineManager, presets: [EffectPreset]) {
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
    func updateWahPosition(_ value: Float, engine: AudioEngineManager) {
        guard isActive else { return }

        wahPosition = value

        // Apply wah effect via expression control
        engine.setExpressionValue(value, for: .equalizer)
    }

    // MARK: - Bypass All

    private func toggleBypassAll(engine: AudioEngineManager) {
        if allBypassed {
            // Restore previous states
            for effect in engine.effectsChain {
                if let wasEnabled = preBypassStates[effect.id] {
                    if wasEnabled != effect.isEnabled {
                        engine.toggleEffect(effect)
                    }
                }
            }
            preBypassStates.removeAll()
            allBypassed = false
        } else {
            // Save current states and bypass all
            preBypassStates.removeAll()
            for effect in engine.effectsChain {
                preBypassStates[effect.id] = effect.isEnabled
                if effect.isEnabled {
                    engine.toggleEffect(effect)
                }
            }
            allBypassed = true
        }
    }

    private func enableAllEffects(engine: AudioEngineManager) {
        for effect in engine.effectsChain {
            if !effect.isEnabled {
                engine.toggleEffect(effect)
            }
        }
        allBypassed = false
    }

    // MARK: - Momentary Boost

    private func toggleMomentaryBoost(engine: AudioEngineManager) {
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

// MARK: - Gesture Binding Row View

struct GestureBindingRow: View {
    let gesture: VisionGestureController.Gesture
    @Binding var action: PerformanceGestureAction

    var body: some View {
        HStack(spacing: 12) {
            // Gesture icon
            Image(systemName: gesture.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.purple)
                .frame(width: 24)

            // Gesture name
            Text(gesture.rawValue)
                .font(.subheadline)
                .frame(width: 80, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Action picker
            Menu {
                ForEach(PerformanceGestureAction.allCases) { actionOption in
                    Button {
                        action = actionOption
                    } label: {
                        Label(actionOption.rawValue, systemImage: actionOption.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: action.icon)
                        .font(.system(size: 12))
                    Text(action.rawValue)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        GestureBindingRow(
            gesture: .headNodDown,
            action: .constant(.toggleFirstEffect)
        )

        GestureBindingRow(
            gesture: .mouthOpen,
            action: .constant(.wahControl)
        )
    }
    .padding()
}
