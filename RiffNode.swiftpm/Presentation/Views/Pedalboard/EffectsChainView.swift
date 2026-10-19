import SwiftUI

// MARK: - Effects Chain View (Glass Pedalboard)
// Liquid Glass UI Design - iOS 26+

struct EffectsChainView: View {
    let engine: any PedalboardEngine
    /// Undo / redo for the board (absent in previews).
    var history: BoardHistory? = nil
    /// Opens Stage Mode (absent: no Stage Mode button).
    var onEnterStageMode: (() -> Void)? = nil
    /// Selection is kept by ID and resolved against the live chain: presets and the AI
    /// replace every node, and editing a stale node would change nothing you can hear.
    @State private var selectedEffectID: UUID?
    /// The amp at the end of the chain is selected instead of a pedal; it (or the guitar
    /// panel) stays open between launches, like the last tool you used.
    @AppStorage("board.ampSelected") private var isAmpSelected = false
    /// The guitar input (pickup, cable, gate) is selected.
    @AppStorage("board.inputSelected") private var isInputSelected = false
    @State private var width: CGFloat = 800

    private var selectedEffect: EffectNode? {
        engine.effectsChain.first { $0.id == selectedEffectID }
    }

    private var selection: Binding<EffectNode?> {
        Binding(
            get: { isAmpSelected || isInputSelected ? nil : selectedEffect },
            set: {
                selectedEffectID = $0?.id
                if $0 != nil { isAmpSelected = false; isInputSelected = false }
            }
        )
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 16) {
            // Header – plain row, no glass on the title; buttons are capsule glass
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "cable.connector.horizontal")
                        .foregroundStyle(.orange)
                    Text("Pedalboard")
                        .font(.title3.bold())
                }

                Spacer()

                if let history {
                    GlassEffectContainer(spacing: 4) {
                        HStack(spacing: 4) {
                            Button("Undo", systemImage: "arrow.uturn.backward") { history.undo() }
                                .disabled(!history.canUndo)
                                .help("Undo (⌘Z)")
                            Button("Redo", systemImage: "arrow.uturn.forward") { history.redo() }
                                .disabled(!history.canRedo)
                                .help("Redo (⇧⌘Z)")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                    }
                }

                // Add effect menu
                Menu {
                    ForEach(EffectCategory.allCases) { category in
                        Menu(category.rawValue) {
                            ForEach(EffectType.effectTypes(for: category)) { type in
                                Button {
                                    withAnimation(.spring(duration: 0.3)) {
                                        engine.addEffect(type)
                                    }
                                } label: {
                                    Label(type.rawValue, systemImage: type.icon)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Pedal")
                    }
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)

                // Stage Mode button
                if let onEnterStageMode {
                    Button(action: onEnterStageMode) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.expand.vertical")
                            Text("Stage Mode")
                        }
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .glassEffect(.regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            if engine.effectsChain.isEmpty {
                ContentUnavailableView {
                    Label("Your pedalboard is empty", systemImage: "cable.connector.horizontal")
                } description: {
                    Text("Add a pedal, pick a preset, or ask the Tone Assistant for a sound.")
                }
                .padding(.vertical, Spacing.xl)
            } else {
                // Signal chain visualization
                GlassSignalChainView(
                    engine: engine,
                    selectedEffect: selection,
                    isAmpSelected: $isAmpSelected,
                    isInputSelected: $isInputSelected
                )

                Text("Guitar → pedals → amp, like a real board · Tap to tweak · Double-tap to switch on or off · Drag to reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                PedalOrderAdviceView(engine: engine)

                if isInputSelected {
                    InputStagePanelView(engine: engine, isWide: width > 980)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else if isAmpSelected {
                    AmpPanelView(engine: engine, isWide: width > 980)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else if let effect = selectedEffect {
                // The selected pedal: its knobs, and what it does to the signal
                    let layout = width > 980
                        ? AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.md))
                        : AnyLayout(VStackLayout(spacing: Spacing.md))
                    layout {
                        GlassPedalControlsView(effect: effect, engine: engine, isCompact: width > 980)
                            .frame(maxWidth: width > 980 ? 320 : .infinity)
                        SignalLabView(effect: effect, engine: engine)
                    }
                    .id(effect.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
        .padding()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
        .animation(.spring(duration: 0.3), value: selectedEffectID)
        .animation(.spring(duration: 0.3), value: isAmpSelected)
        .animation(.spring(duration: 0.3), value: isInputSelected)
        .onAppear(perform: ensureSelection)
        .onChange(of: engine.effectsChain.map(\.id)) { _, _ in ensureSelection() }
    }

    /// Keep a pedal selected so its knobs are always on screen – prefer one that's switched on.
    private func ensureSelection() {
        guard selectedEffect == nil, !isAmpSelected, !isInputSelected else { return }
        selectedEffectID = (engine.effectsChain.first(where: \.isEnabled) ?? engine.effectsChain.first)?.id
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()
        EffectsChainView(engine: AppDependencies.live().engine)
            .frame(height: 500)
            .padding()
    }
}
