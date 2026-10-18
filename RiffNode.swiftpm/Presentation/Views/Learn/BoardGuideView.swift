import SwiftUI

// MARK: - Build a Board
// A walk around a real pedalboard. The board is drawn at the top with numbered spots;
// tap one (or step through with Next) and the card below explains it with something to
// play with – learning by poking, not by reading a wall of text.

struct BoardGuideView: View {
    /// The player's own pedals, for the power budget.
    let chain: [EffectNode]

    @State private var selected: BoardGuideStop.ID = .cable

    private var stop: BoardGuideStop { BoardGuideStop.all.first { $0.id == selected } ?? BoardGuideStop.all[0] }
    private var index: Int { BoardGuideStop.all.firstIndex { $0.id == selected } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            BoardDiagram(selected: $selected)
                .frame(height: 230)

            // Step chips: where you are, and where you can jump
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(BoardGuideStop.all.enumerated()), id: \.element.id) { i, item in
                        Button {
                            withAnimation(.smooth(duration: 0.25)) { selected = item.id }
                        } label: {
                            HStack(spacing: 6) {
                                Text("\(i + 1)")
                                    .font(.caption.weight(.heavy).monospacedDigit())
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(item.id == selected ? Color.orange : Color.primary.opacity(0.12)))
                                    .foregroundStyle(item.id == selected ? .white : .primary)
                                Text(item.title).font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(item.id == selected ? .regular.tint(.orange.opacity(0.25)) : .regular, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            stopCard
                .id(stop.id)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var stopCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: stop.icon)
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.orange.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Step \(index + 1) of \(BoardGuideStop.all.count)").font(.caption).foregroundStyle(.secondary)
                    Text(stop.title).font(.title3.bold())
                }
                Spacer()
            }

            Text(stop.headline)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(stop.points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                        Text(point).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Something to play with
            switch stop.id {
            case .cable: CableExplorer()
            case .power: PowerExplorer(chain: chain)
            case .order: OrderStrip()
            default: EmptyView()
            }

            Label(stop.tryIt, systemImage: "hand.tap")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack {
                Button("Back", systemImage: "chevron.left") { step(-1) }
                    .disabled(index == 0)
                Spacer()
                Button(index == BoardGuideStop.all.count - 1 ? "Done" : "Next", systemImage: "chevron.right") { step(1) }
                    .disabled(index == BoardGuideStop.all.count - 1)
            }
            .buttonStyle(.glass)
        }
        .padding(Spacing.lg)
        .highContrastOutline(cornerRadius: CornerRadius.xl)   // drawn into the card, so a glass container can't cover it
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CornerRadius.xl))
    }

    private func step(_ offset: Int) {
        let next = min(max(index + offset, 0), BoardGuideStop.all.count - 1)
        withAnimation(.smooth(duration: 0.25)) { selected = BoardGuideStop.all[next].id }
    }
}

// MARK: - Board Diagram

/// A small real board – guitar, tuner, buffer, three pedals, the power brick and the amp –
/// with a numbered spot on each part. Tap a spot to learn about it.
private struct BoardDiagram: View {
    @Binding var selected: BoardGuideStop.ID

    private let pedals: [EffectNode] = [
        EffectNode(type: .compressor, isEnabled: true, modelID: "dino-comp"),
        EffectNode(type: .overdrive, isEnabled: true, modelID: "tube-steamer"),
        EffectNode(type: .delay, isEnabled: true, modelID: "carbon-paper"),
    ]

    var body: some View {
        GeometryReader { geo in
            let scale = min(0.8, geo.size.height / 200)
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                // Rails
                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in Rectangle().fill(.white.opacity(0.04)).frame(height: 30) }
                }
                .padding(.vertical, 18)

                VStack(spacing: 10) {
                    // Right to left, like a real board: guitar → tuner → buffer → pedals → amp
                    HStack(spacing: 0) {
                        ampHead.badge(.amp, selected: $selected)
                        cable
                        ForEach(Array(pedals.reversed().enumerated()), id: \.element.id) { i, effect in
                            StompboxView(effect: effect, isLive: true, scale: scale)
                                .badge(.order, selected: $selected, show: i == 1)
                            if i < pedals.count - 1 {
                                cable.badge(.patch, selected: $selected, show: i == 0, below: true)
                            }
                        }
                        cable
                        bufferBox.badge(.buffer, selected: $selected)
                        cable
                        tunerBox.badge(.tuner, selected: $selected)
                        cable.badge(.cable, selected: $selected)
                        guitarJack
                    }
                    .padding(.horizontal, 18)

                    powerBrick.badge(.power, selected: $selected, leading: true)
                }
                .padding(.vertical, 12)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// A stretch of patch cable between two parts.
    private var cable: some View {
        Capsule().fill(Color.black)
            .overlay(Capsule().fill(.white.opacity(0.12)).frame(height: 1).offset(y: -1))
            .frame(minWidth: 14, maxWidth: .infinity)
            .frame(height: 5)
    }

    private var guitarJack: some View {
        VStack(spacing: 4) {
            Circle().fill(Color.black).frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color(white: 0.7), lineWidth: 3))
            Text("GUITAR").font(.system(size: 9, weight: .heavy)).foregroundStyle(.green)
        }
    }

    private var tunerBox: some View {
        VStack(spacing: 4) {
            Text("E").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.green)
                .frame(width: 40, height: 26).background(RoundedRectangle(cornerRadius: 3).fill(.black))
            Text("TUNER").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white.opacity(0.85))
            Circle().fill(Color(white: 0.8)).frame(width: 16, height: 16)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.28)))
    }

    private var bufferBox: some View {
        VStack(spacing: 3) {
            Text("BUFFER").font(.system(size: 7, weight: .heavy)).foregroundStyle(.black.opacity(0.75))
            Circle().fill(Color.red).frame(width: 5, height: 5)
        }
        .padding(.horizontal, 7).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.85)))
    }

    private var ampHead: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) { ForEach(0..<5, id: \.self) { _ in Circle().fill(.black.opacity(0.8)).frame(width: 7, height: 7) } }
                .padding(6).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xC9A646)))
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x3A3326)).frame(height: 70)
        }
        .padding(7)
        .frame(width: 104)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.08)))
    }

    private var powerBrick: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.green).frame(width: 5, height: 5)
            Text("9V POWER · ISOLATED").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.8)))
    }
}

// MARK: - Numbered Spot

private extension View {
    /// A numbered spot on a part of the board diagram; tap it to open that step.
    func badge(_ id: BoardGuideStop.ID, selected: Binding<BoardGuideStop.ID>, show: Bool = true,
               below: Bool = false, leading: Bool = false) -> some View {
        overlay(alignment: leading ? .leading : (below ? .bottom : .top)) {
            if show {
                let number = (BoardGuideStop.all.firstIndex { $0.id == id } ?? 0) + 1
                let isOn = selected.wrappedValue == id
                Button {
                    withAnimation(.smooth(duration: 0.25)) { selected.wrappedValue = id }
                } label: {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(isOn ? Color.orange : Color.black.opacity(0.75)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                        .shadow(color: isOn ? .orange.opacity(0.8) : .clear, radius: 6)
                        .scaleEffect(isOn ? 1.15 : 1)
                }
                .buttonStyle(.plain)
                .offset(x: leading ? -34 : 0, y: leading ? 0 : (below ? 34 : -34))
                .accessibilityLabel(BoardGuideStop.all.first { $0.id == id }?.title ?? "")
            }
        }
    }
}

// MARK: - Cable Explorer

/// Drag the cable length; the pickup's cutoff moves – with and without a buffer.
private struct CableExplorer: View {
    @State private var feet: Float = 20
    @State private var isBuffered = false

    private var settings: InputSettings {
        var s = InputSettings()
        s.cableFeet = feet
        s.isBuffered = isBuffered
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(Int(feet)) ft of cable").font(.headline.monospacedDigit())
                Spacer()
                Toggle("Buffer", isOn: $isBuffered).toggleStyle(.switch).fixedSize()
            }
            Slider(value: $feet, in: 3...60, step: 1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f kHz", settings.pickupResonanceHz / 1000))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
                Text("highs start to roll off").foregroundStyle(.secondary)
            }
            // The audible range, with the part you lose shaded
            GeometryReader { geo in
                let cut = CGFloat(log10(Double(settings.pickupResonanceHz) / 20) / log10(1_000))   // 20 Hz … 20 kHz
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [.blue, .green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    Rectangle().fill(.black.opacity(0.55))
                        .frame(width: geo.size.width * (1 - min(max(cut, 0), 1)))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            HStack { Text("20 Hz"); Spacer(); Text("20 kHz") }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .animation(.snappy, value: feet)
        .animation(.snappy, value: isBuffered)
    }
}

// MARK: - Power Explorer

/// The board's current budget, and what a ground loop does.
private struct PowerExplorer: View {
    let chain: [EffectNode]
    @State private var isolated = true

    private var models: [PedalModel] { chain.compactMap(\.model) }
    private var total: Int { models.reduce(0) { $0 + $1.typicalCurrentMA } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your board").font(.headline)
            ForEach(models) { model in
                HStack {
                    Text(model.name).font(.subheadline)
                    if model.isDigital {
                        Text("DIGITAL").font(.caption2.weight(.heavy)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue.opacity(0.2)))
                    }
                    Spacer()
                    Text("≈ \(model.typicalCurrentMA) mA").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text("Total").font(.headline)
                Spacer()
                Text("≈ \(total) mA at 9 V").font(.headline.monospacedDigit())
            }

            Picker("Power", selection: $isolated) {
                Text("Isolated outputs").tag(true)
                Text("Daisy chain").tag(false)
            }
            .pickerStyle(.segmented)

            // The output, with or without a ground loop's hum riding on it
            Canvas { context, size in
                var path = Path()
                for x in stride(from: 0, through: size.width, by: 1) {
                    let t = Double(x / size.width)
                    var y = sin(t * 2 * .pi * 3) * 0.5
                    if !isolated { y += sin(t * 2 * .pi * 40) * 0.12 + sin(t * 2 * .pi * 80) * 0.06 }
                    let point = CGPoint(x: x, y: size.height / 2 - CGFloat(y) * size.height * 0.8)
                    if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(isolated ? .green : .orange), lineWidth: 2)
            }
            .frame(height: 60)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.85)))

            Text(isolated
                 ? "Each pedal has its own winding and ground: a clean note."
                 : "One shared ground: the loop picks up mains hum (50/60 Hz and its harmonics) – worst with digital pedals on the chain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Typical figures – always check the label on your pedal.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .animation(.smooth(duration: 0.25), value: isolated)
    }
}

// MARK: - Order Strip

/// The usual order, as a strip of families.
private struct OrderStrip: View {
    private let steps: [(String, String, Color)] = [
        ("Tuner", "tuningfork", .gray),
        ("Dynamics · Wah", "c.circle.fill", .riffDynamics),
        ("Drive", "flame.fill", .riffGain),
        ("Modulation", "waveform.path", .riffModulation),
        ("Delay", "repeat", .riffAmbience),
        ("Reverb", "sparkles", .riffAmbience),
        ("Amp", "hifispeaker.fill", .orange),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    VStack(spacing: 4) {
                        Image(systemName: step.1).foregroundStyle(step.2)
                        Text(step.0).font(.caption.weight(.semibold)).lineLimit(1).fixedSize()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(step.2.opacity(0.15)))
                    if i < steps.count - 1 { Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
