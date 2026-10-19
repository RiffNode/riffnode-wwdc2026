import SwiftUI

// MARK: - Signal Chain

struct GlassSignalChainView: View {
    let engine: any PedalboardEngine
    @Binding var selectedEffect: EffectNode?
    @Binding var isAmpSelected: Bool
    @Binding var isInputSelected: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            signalChainContent
        }
        .scrollBounceBehavior(.basedOnSize)
        // Dark pedalboard surface
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.13), Color(white: 0.09)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [Color(white: 0.28), Color(white: 0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        // Trailing fade — tells the user there's more content to scroll to
        .overlay(alignment: .trailing) {
            if engine.effectsChain.count > 4 {
                LinearGradient(
                    colors: [Color(white: 0.09).opacity(0), Color(white: 0.09)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 48)
                .clipShape(
                    .rect(
                        bottomTrailingRadius: 18,
                        topTrailingRadius: 18
                    )
                )
                .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }

    private var signalChainContent: some View {
        HStack(spacing: 0) {
            PedalboardJack(label: "GUITAR", isInput: true)
                .overlay {
                    if isInputSelected {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white, lineWidth: 2).padding(-4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(duration: 0.25)) {
                        selectedEffect = nil
                        isAmpSelected = false
                        isInputSelected = true
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows the cable, buffer, volume pedal and noise gate")
            PedalboardCable()

            ForEach(Array(engine.effectsChain.enumerated()), id: \.element.id) { index, effect in
                pedalWithDragDrop(effect: effect, index: index)
                PedalboardCable()
            }

            // The amp the board plugs into
            AmpHeadTile(settings: engine.ampSettings, isSelected: isAmpSelected) {
                withAnimation(.spring(duration: 0.25)) {
                    selectedEffect = nil
                    isInputSelected = false
                    isAmpSelected = true
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 12)
    }

    private func pedalWithDragDrop(effect: EffectNode, index: Int) -> some View {
        let isCurrentlySelected = selectedEffect?.id == effect.id

        return GlassEffectPedal(
            effect: effect,
            isSelected: isCurrentlySelected,
            onTap: { handleTap(effect: effect) },
            onDoubleTap: { engine.toggleEffect(effect) },
            onDelete: { handleDelete(effect: effect, index: index) }
        )
        .draggable(effect.id.uuidString) {
            dragPreview(for: effect)
        }
        .dropDestination(for: String.self) { items, _ in
            return handleDrop(items: items, targetIndex: index)
        }
        // Right-click on Mac, long-press on iPad: the things you'd do to a pedal
        .contextMenu {
            Button(effect.isEnabled ? "Switch Off" : "Switch On",
                   systemImage: effect.isEnabled ? "power.circle" : "power.circle.fill") { engine.toggleEffect(effect) }
            let models = PedalModel.models(for: effect.type)
            if models.count > 1 {
                Menu("Pedal", systemImage: "square.stack") {
                    ForEach(models) { model in
                        Button {
                            engine.setPedalModel(effect, modelID: model.id)
                        } label: {
                            if model.id == effect.modelID { Label(model.name, systemImage: "checkmark") } else { Text(model.name) }
                        }
                    }
                }
            }
            Divider()
            Button("Remove from Board", systemImage: "trash", role: .destructive) { handleDelete(effect: effect, index: index) }
        }
    }

    private func handleTap(effect: EffectNode) {
        withAnimation(.spring(duration: 0.25)) {
            if selectedEffect?.id == effect.id {
                selectedEffect = nil
            } else {
                selectedEffect = effect
            }
        }
    }

    private func handleDelete(effect: EffectNode, index: Int) {
        withAnimation(.spring(duration: 0.3)) {
            if selectedEffect?.id == effect.id {
                selectedEffect = nil
            }
            engine.removeEffect(at: index)
        }
    }

    private func dragPreview(for effect: EffectNode) -> some View {
        GlassEffectPedal(
            effect: effect,
            isSelected: false,
            onTap: {},
            onDoubleTap: {},
            onDelete: {}
        )
        .opacity(0.7)
        .scaleEffect(0.9)
    }

    private func handleDrop(items: [String], targetIndex: Int) -> Bool {
        guard let droppedId = items.first else { return false }
        guard let sourceIndex = engine.effectsChain.firstIndex(where: { $0.id.uuidString == droppedId }) else { return false }
        guard sourceIndex != targetIndex else { return false }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        withAnimation(.spring(duration: 0.3)) {
            engine.moveEffect(from: IndexSet(integer: sourceIndex), to: destination)
        }
        return true
    }
}

struct PedalboardJack: View {
    let label: String
    let isInput: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Jack housing – dark metal cylinder
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 42, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(white: 0.28), lineWidth: 1)
                    )

                // Jack hole – dark circle with rim
                Circle()
                    .fill(Color(white: 0.04))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(Color(white: 0.3), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }

            // Label
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(isInput ? Color.green : Color(white: 0.55))
        }
    }
}

struct PedalboardCable: View {
    var body: some View {
        VStack(spacing: 0) {
            // Cable line – slightly curved look via a thin rounded rect
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.18), Color(white: 0.22)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 28, height: 3)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
    }
}
