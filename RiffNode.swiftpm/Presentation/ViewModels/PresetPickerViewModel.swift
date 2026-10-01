import SwiftUI
import Observation

// MARK: - Preset Picker View Model

/// Handles preset selection and filtering logic
@Observable
@MainActor
final class PresetPickerViewModel {

    // MARK: - State

    var selectedCategory: EffectPreset.PresetCategory?
    var selectedPreset: EffectPreset?

    // MARK: - Dependencies

    private let presetService: PresetProviding
    private let effectsManager: EffectsChainManaging

    // MARK: - Initialization

    init(presetService: PresetProviding, effectsManager: EffectsChainManaging) {
        self.presetService = presetService
        self.effectsManager = effectsManager
    }

    // MARK: - Computed Properties

    var filteredPresets: [EffectPreset] {
        if let category = selectedCategory {
            return presetService.presets(for: category)
        }
        return presetService.presets
    }

    var categories: [EffectPreset.PresetCategory] {
        EffectPreset.PresetCategory.allCases
    }

    // MARK: - Actions

    func selectCategory(_ category: EffectPreset.PresetCategory?) {
        withAnimation {
            selectedCategory = category
        }
    }

    func selectPreset(_ preset: EffectPreset) {
        selectedPreset = preset
        effectsManager.applyPreset(preset)
    }

    func isPresetSelected(_ preset: EffectPreset) -> Bool {
        selectedPreset?.id == preset.id
    }
}
