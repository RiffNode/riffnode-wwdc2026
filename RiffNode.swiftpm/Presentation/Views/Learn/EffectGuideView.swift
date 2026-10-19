import SwiftUI

// MARK: - Learn
// Four chapters, each one picked from a big visual card: build a real pedalboard, browse
// the classic pedals, the effect families, and the science of sound. Every chapter is
// something to play with first and read second.

struct EffectGuideView: View {

    // MARK: - Dependencies

    private let guideService: EffectGuideServiceProtocol
    var engine: (any LearnEngine)?

    // MARK: - State

    @State private var selectedCategoryIndex: Int = 0
    @State private var expandedEffectId: UUID? = nil
    /// Remembers the chapter you were reading.
    @AppStorage("learn.chapter") private var selectedSection: LearnSection = .board
    @State private var addedEffectId: UUID? = nil

    enum LearnSection: String, CaseIterable, Identifiable {
        case board = "Build a Board"
        case library = "Pedal Library"
        case effects = "Effect Types"
        case science = "Sound Science"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .board: "Cable, tuner, power, order"
            case .library: "20 classic pedals to hear"
            case .effects: "What each family does"
            case .science: "Waves, harmonics, pitch"
            }
        }

        var icon: String {
            switch self {
            case .board: "rectangle.3.group"
            case .library: "square.grid.3x3.fill"
            case .effects: "slider.horizontal.3"
            case .science: "waveform"
            }
        }

        var tint: Color {
            switch self {
            case .board: .orange
            case .library: .green
            case .effects: .purple
            case .science: .cyan
            }
        }
    }

    // MARK: - Initialization

    init(guideService: any EffectGuideServiceProtocol, engine: (any LearnEngine)? = nil) {
        self.guideService = guideService
        self.engine = engine
    }

    // MARK: - Computed Properties

    private var categories: [any EffectCategoryProviding] {
        guideService.categories
    }

    private var selectedCategory: (any EffectCategoryProviding)? {
        guard selectedCategoryIndex < categories.count else { return nil }
        return categories[selectedCategoryIndex]
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Content based on selected section
            ScrollView {
                chapterCards
                    .padding(.horizontal)
                    .padding(.top)

                switch selectedSection {
                case .board:
                    BoardGuideView(chain: engine?.effectsChain ?? [])
                        .padding()

                case .library:
                    PedalLibraryView(engine: engine)
                        .padding()

                case .science:
                    GlassSoundScienceView()
                        .padding(.top)

                case .effects:
                    VStack(spacing: 16) {
                        // Category picker - native segmented style
                        if categories.count > 0 {
                            Picker("Category", selection: $selectedCategoryIndex) {
                                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                                    Text(category.name)
                                        .tag(index)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                        }

                        if let category = selectedCategory {
                            // Category description - minimal
                            Text(category.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 8)

                            // Effects list - cleaner design
                            LazyVStack(spacing: 12) {
                                // Pedals you can play in RiffNode come first; the rest are for reading
                                ForEach(Array(category.effects.sorted { (a: any EffectInfoProviding, b: any EffectInfoProviding) in
                                    (a as? EffectInfoModel)?.effectType != nil && (b as? EffectInfoModel)?.effectType == nil
                                }.enumerated()), id: \.offset) { index, effect in
                                    if let effectModel = effect as? EffectInfoModel {
                                        GlassEffectCardView(
                                            effect: effectModel,
                                            isExpanded: expandedEffectId == effectModel.id,
                                            justAdded: addedEffectId == effectModel.id,
                                            engine: engine
                                        ) {
                                            withAnimation(.spring(duration: 0.3)) {
                                                expandedEffectId = expandedEffectId == effectModel.id ? nil : effectModel.id
                                            }
                                        } onTryEffect: { type in
                                            if let eng = engine {
                                                eng.addEffect(type)
                                                addedEffectId = effectModel.id
                                                Task { @MainActor in
                                                    try? await Task.sleep(for: .milliseconds(1500))
                                                    addedEffectId = nil
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: selectedSection)
        .animation(.smooth(duration: 0.25), value: selectedCategoryIndex)
        // Leaving Learn hands the player's own pedalboard back
        .onDisappear { engine?.stopAudition() }
        .onChange(of: selectedSection) { _, _ in engine?.stopAudition() }
    }

    /// The four chapters as big cards; the chosen one is lit.
    private var chapterCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            ForEach(LearnSection.allCases) { section in
                let isOn = selectedSection == section
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.icon)
                            .font(.title2)
                            .foregroundStyle(isOn ? .white : section.tint)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 12).fill(isOn ? section.tint : section.tint.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.rawValue).font(.headline)
                            Text(section.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .glassEffect(isOn ? .regular.tint(section.tint.opacity(0.25)).interactive() : .regular.interactive(),
                                 in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isOn ? section.tint.opacity(0.7) : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()

        EffectGuideView(guideService: AppDependencies.live().effectGuide)
    }
}
