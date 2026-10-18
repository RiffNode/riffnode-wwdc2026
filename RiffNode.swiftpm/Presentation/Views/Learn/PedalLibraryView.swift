import SwiftUI

// MARK: - Pedal Library
// The twenty classics as a wall of real-looking pedals. Pick one: see what its circuit
// does, hear it on the demo riff (with an A/B to dry), and put it on your board.

struct PedalLibraryView: View {
    let engine: (any LearnEngine)?

    enum Family: String, CaseIterable, Identifiable {
        case all = "All", drive = "Drive", fuzz = "Fuzz", modulation = "Modulation", time = "Time & Dynamics"
        var id: String { rawValue }

        func includes(_ model: PedalModel) -> Bool {
            switch self {
            case .all: true
            case .drive: model.type == .overdrive || model.type == .distortion
            case .fuzz: model.type == .fuzz
            case .modulation: model.type.category == .modulation
            case .time: model.type.category == .timeAmbience || model.type.category == .dynamics
            }
        }
    }

    @State private var family: Family = .all
    @State private var selectedID: String? = "tube-steamer"
    @State private var placedID: String?

    private var models: [PedalModel] { PedalModel.all.filter(family.includes) }
    private var selected: PedalModel? { PedalModel.model(id: selectedID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker("Family", selection: $family) {
                ForEach(Family.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if let selected {
                PedalDetail(model: selected, engine: engine, justPlaced: placedID == selected.id) {
                    place(selected)
                }
                .id(selected.id)
                .transition(.opacity)
            }

            // The wall
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 18)], spacing: 22) {
                ForEach(models) { model in
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { selectedID = model.id }
                    } label: {
                        VStack(spacing: 8) {
                            StompboxView(effect: EffectNode(type: model.type, isEnabled: true, modelID: model.id),
                                         isLive: true, scale: 0.85)
                                .frame(height: 120)
                            VStack(spacing: 1) {
                                Text(model.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(String(model.year)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedID == model.id ? Color.orange.opacity(0.14) : Color.primary.opacity(0.04))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selectedID == model.id ? Color.orange.opacity(0.8) : .clear, lineWidth: 2))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("\(model.name), \(model.type.rawValue), \(String(model.year))")
                }
            }

            Text("Names and designs are RiffNode's own; the originals are named only to describe the sound. All trademarks belong to their owners.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .animation(.smooth(duration: 0.25), value: family)
    }

    /// Puts this classic on the player's board: swaps the pedal of its kind, or adds one.
    private func place(_ model: PedalModel) {
        guard let engine else { return }
        engine.stopAudition()
        if let node = engine.effectsChain.first(where: { model.fits($0.type) && $0.type == model.type })
            ?? engine.effectsChain.first(where: { model.fits($0.type) }) {
            engine.setPedalModel(node, modelID: model.id)
            if !node.isEnabled { engine.toggleEffect(node) }
        } else {
            engine.addEffect(model.type)
            if let node = engine.effectsChain.last(where: { $0.type == model.type }) {
                engine.setPedalModel(node, modelID: model.id)
            }
        }
        placedID = model.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if placedID == model.id { placedID = nil }
        }
    }
}

// MARK: - Pedal Detail

private struct PedalDetail: View {
    let model: PedalModel
    let engine: (any LearnEngine)?
    let justPlaced: Bool
    let onPlace: () -> Void

    private var isAuditioning: Bool { engine?.auditionModelID == model.id }
    private var tint: Color { Color(hex: model.look.body) }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            StompboxView(effect: EffectNode(type: model.type, isEnabled: true, modelID: model.id),
                         isLive: !(engine?.isAuditionBypassed ?? false) || !isAuditioning, scale: 1.35)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.title2.bold())
                    Text("\(model.type.rawValue) · voiced after the \(model.inspiredBy), \(String(model.year))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text(model.about)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // The circuit at a glance
                FlowLayout(spacing: 6) {
                    ForEach(facts, id: \.self) { fact in
                        Text(fact)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }

                HStack(spacing: 10) {
                    if let engine {
                        Button {
                            if isAuditioning { engine.stopAudition() } else { engine.startAudition(model.type, modelID: model.id) }
                        } label: {
                            Label(isAuditioning ? "Stop" : "Hear it", systemImage: isAuditioning ? "stop.fill" : "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.85, green: 0.33, blue: 0.05))   // deep orange: white text stays readable
                        .controlSize(.large)
                        .disabled(!engine.canPlayDemoRiff)

                        if isAuditioning {
                            Picker("Compare", selection: Binding(
                                get: { engine.isAuditionBypassed },
                                set: { engine.setAuditionBypassed($0) }
                            )) {
                                Text("Pedal on").tag(false)
                                Text("Dry").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 180)
                        }

                        Button(justPlaced ? "On your board" : "Use on my board",
                               systemImage: justPlaced ? "checkmark" : "plus") { onPlace() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                }
                if let engine, !engine.canPlayDemoRiff {
                    Text("Start the engine to hear it.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .highContrastOutline(cornerRadius: CornerRadius.xl)   // drawn into the card, so a glass container can't cover it
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CornerRadius.xl))
        .animation(.smooth(duration: 0.2), value: isAuditioning)
    }

    /// Short facts from the voicing: gain, clipping, tone – or the modulation's shape.
    private var facts: [String] {
        var list: [String] = []
        switch model.voicing {
        case .drive(let d):
            list.append("\(Int(d.gainDB.lowerBound))–\(Int(d.gainDB.upperBound)) dB gain")
            let clipping: String = switch d.clipping {
            case .softFeedback: "Soft clipping"
            case .hardToGround: "Hard clipping"
            case .asymmetricFuzz: "Transistor fuzz"
            case .mosfet: "MOSFET clipping"
            case .germanium: "Germanium diodes"
            case .cascaded: "Two clipping stages"
            case .asymmetricSoft: "Asymmetric diodes"
            }
            list.append(clipping)
            if d.preHighPassHz >= 100 { list.append("Bass cut below \(Int(d.preHighPassHz)) Hz") }
            if d.cleanBlend > 0 { list.append("Clean blend") }
            let tone: String = switch d.tone {
            case .lowPass: "Treble tone control"
            case .midScoop: "Mid-scoop tone"
            case .fixed: "No tone knob"
            }
            list.append(tone)
        case .modulation(let m):
            switch model.type {
            case .phaser: list += ["\(m.stages) all-pass stages", m.stageSpread > 1 ? "Uneven stages" : "Even sweep"]
            case .chorus, .flanger: list += [String(format: "%.1f–%.0f ms delay", m.baseDelayMs, m.baseDelayMs + m.sweepMs), "Bucket-brigade"]
            case .tremolo: list.append(m.shape > 0 ? "Sine-to-square wave" : "Sine wave")
            default: break
            }
        case .echo(let e):
            list.append(e.darkenHz > 0 ? "Analog: repeats darken" : "Digital: exact repeats")
            if e.wowMs > 0 { list.append("Wow & flutter") }
        case .standard:
            break
        }
        list.append("≈ \(model.typicalCurrentMA) mA")
        return list
    }
}
