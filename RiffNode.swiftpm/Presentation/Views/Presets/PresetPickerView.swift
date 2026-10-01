import SwiftUI

// MARK: - Preset Picker View

struct PresetPickerView: View {
    @Bindable var engine: AudioEngineManager
    let presetService: PresetProviding
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: EffectPreset.PresetCategory?
    @State private var selectedPreset: EffectPreset?

    private var filteredPresets: [EffectPreset] {
        if let category = selectedCategory {
            return presetService.presets(for: category)
        }
        return presetService.presets
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                VStack(spacing: 0) {
                    GlassPresetCategoryBar(selectedCategory: $selectedCategory)

                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(filteredPresets) { preset in
                                GlassPresetCard(
                                    preset: preset,
                                    isSelected: selectedPreset?.id == preset.id
                                ) {
                                    selectedPreset = preset
                                    engine.applyPreset(preset)
                                    dismiss()
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Effect Presets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 500)
        #endif
    }
}

// MARK: - Glass Preset Category Bar

struct GlassPresetCategoryBar: View {
    @Binding var selectedCategory: EffectPreset.PresetCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 8) {
                    Button("All") {
                        withAnimation { selectedCategory = nil }
                    }
                    .buttonStyle(GlassPillStyle(isSelected: selectedCategory == nil, tint: .accentColor))

                    ForEach(EffectPreset.PresetCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) {
                            withAnimation { selectedCategory = category }
                        }
                        .buttonStyle(GlassPillStyle(isSelected: selectedCategory == category, tint: category.color))
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Glass Preset Card

struct GlassPresetCard: View {
    let preset: EffectPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(preset.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(preset.category.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(preset.category.color)
                        .glassEffect(.regular.tint(preset.category.color.opacity(0.2)), in: Capsule())
                }

                Text(preset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Effect chain preview
                HStack(spacing: 4) {
                    ForEach(Array(preset.effects.enumerated()), id: \.offset) { _, effect in
                        Text(effect.type.abbreviation)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(effect.type.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .glassEffect(.regular.tint(effect.type.color.opacity(0.25)), in: Capsule())
                    }
                }
            }
            .glassCard(
                tint: isSelected ? preset.category.color : nil,
                cornerRadius: 16,
                padding: 16
            )
        }
        .buttonStyle(.plain)
    }
}
