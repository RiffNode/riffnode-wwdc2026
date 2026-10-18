import SwiftUI
import UniformTypeIdentifiers

// MARK: - Amp Head (end of the chain)
// A real pedalboard ends in an amplifier. This tile is it: tap to dial in the amp.

struct AmpHeadTile: View {
    let settings: AmpSettings
    let isSelected: Bool
    let onTap: () -> Void

    private var look: AmpLook { settings.model.voice.look }
    private var ink: Color { Color(hex: look.ink) }

    var body: some View {
        VStack(spacing: 5) {
            // Control panel: pilot light, the amp's own name, a row of knobs
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(settings.isEnabled ? Color.red : Color(white: 0.3))
                        .frame(width: 7, height: 7)
                        .shadow(color: settings.isEnabled ? .red.opacity(0.8) : .clear, radius: 4)
                    Text(settings.model.rawValue)
                        .font(.system(size: 10, weight: .heavy, design: look.style == .tweed ? .serif : .rounded))
                        .italic(look.style == .blackPanel || look.style == .tweed)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle().fill(knobColor).frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
                    }
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: look.panel)))
            .padding(.horizontal, 7)
            .padding(.top, 7)

            // Speaker grille, in the amp's own cloth
            AmpGrille(look: look)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .bottom) {
                    Text(settings.cabinet.rawValue)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .shadow(color: .black, radius: 1)
                        .padding(.bottom, 4)
                }
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(piping, lineWidth: look.style == .goldPanel ? 1.5 : 0.5))
                .padding(.horizontal, 7)
                .padding(.bottom, 7)
        }
        .frame(width: 104, height: 132)
        .background(tolex)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.riffPrimary : .black.opacity(0.5), lineWidth: isSelected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        .opacity(settings.isEnabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amp, \(settings.model.rawValue), \(settings.cabinet.rawValue) cabinet")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the amp's controls")
    }

    private var knobColor: Color {
        switch look.style {
        case .blackPanel, .modern: Color(white: 0.85)          // chrome / silver
        case .tweed: Color(red: 0.25, green: 0.15, blue: 0.08)   // brown pointers
        case .copperPanel: Color(red: 0.95, green: 0.9, blue: 0.8)
        case .goldPanel: Color(red: 0.12, green: 0.1, blue: 0.08)
        }
    }

    private var piping: Color { look.style == .goldPanel ? .white.opacity(0.85) : .black.opacity(0.4) }

    /// The covering: plain tolex, or diagonal-striped tweed.
    @ViewBuilder private var tolex: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        if look.style == .tweed {
            shape.fill(Color(hex: look.tolex))
                .overlay(
                    Canvas { context, size in
                        var path = Path()
                        var x: CGFloat = -size.height
                        while x < size.width {
                            path.move(to: CGPoint(x: x, y: size.height))
                            path.addLine(to: CGPoint(x: x + size.height, y: 0))
                            x += 4
                        }
                        context.stroke(path, with: .color(.black.opacity(0.12)), lineWidth: 1)
                    }
                    .clipShape(shape)
                )
        } else {
            shape.fill(LinearGradient(colors: [Color(hex: look.tolex).mix(with: .white, by: 0.08), Color(hex: look.tolex)],
                                      startPoint: .top, endPoint: .bottom))
        }
    }
}

/// Speaker cloth: sparkly silver, a woven check, vertical slats or a fine mesh.
private struct AmpGrille: View {
    let look: AmpLook

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: look.grille)))
            var path = Path()
            switch look.style {
            case .blackPanel:
                // Silver cloth with a fine diagonal sparkle
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    x += 3
                }
                context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 0.6)
            case .goldPanel, .tweed:
                // Woven check
                var v: CGFloat = 0
                while v < max(size.width, size.height) {
                    path.move(to: CGPoint(x: v, y: 0)); path.addLine(to: CGPoint(x: v, y: size.height))
                    path.move(to: CGPoint(x: 0, y: v)); path.addLine(to: CGPoint(x: size.width, y: v))
                    v += 3
                }
                context.stroke(path, with: .color(.white.opacity(look.style == .tweed ? 0.12 : 0.08)), lineWidth: 1)
            case .copperPanel:
                // Vertical slats
                var x: CGFloat = 2
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                    x += 4
                }
                context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 1.5)
            case .modern:
                // Fine metal mesh
                var y: CGFloat = 1
                while y < size.height {
                    var x: CGFloat = (Int(y) / 3) % 2 == 0 ? 1 : 2.5
                    while x < size.width {
                        path.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                        x += 3
                    }
                    y += 3
                }
                context.fill(path, with: .color(.white.opacity(0.12)))
            }
        }
    }
}

// MARK: - Amp Panel

/// The amp's controls and its frequency response, side by side on wide screens.
struct AmpPanelView: View {
    let engine: any AmpControlling
    var isWide: Bool

    /// One file importer for both kinds of file (SwiftUI honours one per view).
    private enum ImportKind { case impulseResponse, neuralCapture }
    @State private var importKind: ImportKind?
    @State private var irError: String?
    @State private var namError: String?
    @State private var isLoadingNAM = false

    private var settings: AmpSettings { engine.ampSettings }

    var body: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.md))
            : AnyLayout(VStackLayout(spacing: Spacing.md))
        layout {
            controls
                .frame(maxWidth: isWide ? 420 : .infinity)
            AmpResponseCard(engine: engine)
        }
    }

    private var controls: some View {
        GlassCard(tint: Color(red: 0.55, green: 0.48, blue: 0.33).opacity(0.18), cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Amp & Cabinet", systemImage: "hifispeaker.fill")
                        .font(.headline)
                    Spacer()
                    Toggle("Amp", isOn: binding(\.isEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(.orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Amp").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Amp", selection: Binding(
                        get: { engine.ampSettings.model },
                        set: { model in
                            // A neural capture needs a file first
                            if model == .captured && engine.neuralModelName == nil {
                                importKind = .neuralCapture
                            } else {
                                // Each classic amp comes with the cabinet it's usually played through
                                var next = engine.ampSettings
                                next.model = model
                                if next.cabinet != .impulse && model != .captured { next.cabinet = model.voice.defaultCabinet }
                                engine.ampSettings = next
                            }
                        }
                    )) {
                        ForEach(AmpModel.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text(settings.model.summary).font(.caption).foregroundStyle(.secondary)
                    if settings.model != .captured {
                        Text("Voiced after the \(settings.model.inspiredBy). \(settings.model.about)")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Button(engine.neuralModelName == nil ? "Load a NAM capture…" : "Change capture…", systemImage: "brain") {
                            importKind = .neuralCapture
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        if isLoadingNAM {
                            ProgressView().controlSize(.small)
                        } else if let name = engine.neuralModelName {
                            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text("Neural Amp Modeler – a real amp, learned by a neural network")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    if let namError {
                        Text(namError).font(.caption).foregroundStyle(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cabinet").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Cabinet", selection: Binding(
                        get: { engine.ampSettings.cabinet },
                        set: { cabinet in
                            // An IR needs a file first
                            if cabinet == .impulse && engine.cabinetIRName == nil {
                                importKind = .impulseResponse
                            } else {
                                engine.ampSettings.cabinet = cabinet
                            }
                        }
                    )) {
                        ForEach(CabinetType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.cabinet.summary).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button(engine.cabinetIRName == nil ? "Load an IR…" : "Change IR…", systemImage: "waveform.badge.plus") {
                            importKind = .impulseResponse
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        if let name = engine.cabinetIRName {
                            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text("A .wav impulse response of a real speaker cabinet")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    if let irError {
                        Text(irError).font(.caption).foregroundStyle(.orange)
                    }
                }

                // Five knobs, 0–10 like a real amp panel
                HStack(spacing: 8) {
                    knob("GAIN", \.gain)
                    knob("BASS", \.bass)
                    knob("MID", \.mid)
                    knob("TREBLE", \.treble)
                    knob("MASTER", \.master)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!settings.isEnabled)
            .opacity(settings.isEnabled ? 1 : 0.6)
        }
        .fileImporter(
            isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
            allowedContentTypes: importKind == .neuralCapture ? [.json, .data] : [.wav, .aiff, .audio]
        ) { result in
            let kind = importKind
            guard case .success(let url) = result else { return }
            Task {
                if kind == .neuralCapture {
                    isLoadingNAM = true
                    do {
                        try await engine.loadNeuralModel(from: url)
                        namError = nil
                    } catch {
                        namError = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that capture."
                    }
                    isLoadingNAM = false
                } else {
                    do {
                        try await engine.loadCabinetIR(from: url)
                        irError = nil
                    } catch {
                        irError = "Couldn't read that impulse response."
                    }
                }
            }
        }
    }

    private func knob(_ label: String, _ key: WritableKeyPath<AmpSettings, Float>) -> some View {
        GlassKnob(
            value: Binding(get: { engine.ampSettings[keyPath: key] * 10 },
                           set: { engine.ampSettings[keyPath: key] = $0 / 10 }),
            range: 0...10,
            tint: .orange,
            label: label,
            format: "%.1f"
        )
        .scaleEffect(0.82)
    }

    private func binding<T>(_ key: WritableKeyPath<AmpSettings, T>) -> Binding<T> {
        Binding(get: { engine.ampSettings[keyPath: key] }, set: { engine.ampSettings[keyPath: key] = $0 })
    }
}

// MARK: - Amp Response

/// The amp's tone stack and speaker drawn as a frequency response – the speaker's roll-off
/// above ~5 kHz is what turns raw, fizzy distortion into a guitar tone.
struct AmpResponseCard: View {
    let engine: any AmpControlling

    private static let frequencies: [Float] = (0..<120).map { 40 * pow(Float(16_000) / 40, Float($0) / 119) }

    var body: some View {
        let response = engine.ampSettings.isEnabled
            ? engine.ampResponse(at: Self.frequencies)
            : [Float](repeating: 0, count: Self.frequencies.count)

        GlassCard(tint: Color.orange.opacity(0.08), cornerRadius: CornerRadius.xl) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("What the amp does", systemImage: "waveform.path.ecg")
                        .font(.headline)
                    Text("Tone stack + speaker, how much each frequency is boosted or cut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Canvas { context, size in
                    let range: Float = 24   // ±24 dB
                    func y(_ db: Float) -> CGFloat {
                        CGFloat(0.5 - max(-range, min(range, db)) / (2 * range)) * size.height
                    }
                    func x(_ f: Float) -> CGFloat {
                        CGFloat(log2(f / 40) / log2(16_000 / 40)) * size.width
                    }
                    // Grid: 0 dB line and decades
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y(0))); grid.addLine(to: CGPoint(x: size.width, y: y(0)))
                    for f: Float in [100, 1000, 10_000] {
                        grid.move(to: CGPoint(x: x(f), y: 0)); grid.addLine(to: CGPoint(x: x(f), y: size.height))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 1)
                    // The fizz zone a speaker removes
                    let fizz = CGRect(x: x(5_000), y: 0, width: size.width - x(5_000), height: size.height)
                    context.fill(Path(fizz), with: .color(.red.opacity(0.08)))

                    var curve = Path()
                    for (i, f) in Self.frequencies.enumerated() {
                        let point = CGPoint(x: x(f), y: y(response[i]))
                        i == 0 ? curve.move(to: point) : curve.addLine(to: point)
                    }
                    var fill = curve
                    fill.addLine(to: CGPoint(x: size.width, y: y(0)))
                    fill.addLine(to: CGPoint(x: 0, y: y(0)))
                    fill.closeSubpath()
                    context.fill(fill, with: .color(.orange.opacity(0.18)))
                    context.stroke(curve, with: .color(.orange), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                }
                .frame(height: 170)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: CornerRadius.md))
                .overlay(alignment: .bottom) {
                    HStack {
                        Text("40 Hz"); Spacer(); Text("100"); Spacer(); Text("1 kHz"); Spacer(); Text("fizz zone · 10 kHz")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(8)
                }
                .accessibilityElement()
                .accessibilityLabel("Amp frequency response")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Why every pedalboard needs an amp")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Distortion creates harmonics far above the note. A guitar speaker can't reproduce much above 5 kHz, so it smooths that fizz away – try Cabinet: Direct to hear a pedal without it. The preamp's tubes also clip more on one half of the wave, which adds warmth.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Pedal Order Advice

/// Real pedalboards follow a convention – dynamics, drive, modulation, time. This explains
/// what each misplacement does to the sound, and fixes the order in one tap.
struct PedalOrderAdviceView: View {
    let engine: any EffectsChainManaging

    var body: some View {
        let issues = PedalOrderAdvisor.issues(for: engine.effectsChain.map(\.type))
        Group {
            if issues.isEmpty {
                Label("Standard pedalboard order: dynamics → drive → modulation → time → amp", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Unusual pedal order", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Use standard order", systemImage: "wand.and.stars") {
                            withAnimation(.spring(duration: 0.35)) {
                                engine.effectsChain = PedalOrderAdvisor.standardOrder(engine.effectsChain) { $0.type }
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title).font(.caption.weight(.semibold))
                            Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Keep it if you like the sound – plenty of great tones break the rules.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(Spacing.md)
                .glassEffect(.regular.tint(Color.orange.opacity(0.1)), in: RoundedRectangle(cornerRadius: CornerRadius.lg))
            }
        }
        .padding(.horizontal)
        .animation(.smooth(duration: 0.25), value: issues)
    }
}
