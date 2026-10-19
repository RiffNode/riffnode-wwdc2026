import SwiftUI

// MARK: - Signal Lab
// Draws a pedal's input against its output, live, so you can see what it physically does:
// distortion flattening the peaks, a compressor squeezing the volume, a flanger's comb of
// notches. Measurements under the plot put numbers on the change.

struct SignalLabView: View {
    @Bindable var effect: EffectNode
    let engine: any SignalLabEngine

    @State private var model = SignalLabModel()
    @State private var probeID = UUID()
    @State private var lens: SignalLens

    init(effect: EffectNode, engine: any SignalLabEngine) {
        self.effect = effect
        self.engine = engine
        _lens = State(initialValue: effect.type.primaryLens)
    }

    private var color: Color { effect.type.color }

    var body: some View {
        GlassCard(tint: color.opacity(0.12), cornerRadius: CornerRadius.xl) {
            VStack(alignment: .leading, spacing: 12) {
                header
                plot
                legend
                if !model.isSilent && effect.isEnabled && engine.isRunning {
                    findings
                }
                explanation
            }
        }
        .task(id: effect.type) {
            engine.probe(effect, owner: probeID)
            model.clear()
            while !Task.isCancelled {
                model.update(from: engine.probeAnalysis())
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
        .onDisappear { engine.stopProbe(owner: probeID) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Signal Lab", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Text("What \(effect.type.rawValue) does to your signal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("View", selection: $lens) {
                ForEach(SignalLens.allCases) { lens in
                    Label(lens.rawValue, systemImage: lens.icon).tag(lens)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleOnly)
            .fixedSize()
        }
    }

    // MARK: - Plot

    private var plot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(.black.opacity(0.78))

            SignalPlot(lens: lens, model: model, color: color,
                       summary: statusMessage?.text ?? findingList.map(\.spoken).joined(separator: ". "))
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .opacity(model.isSilent ? 0.25 : 1)

            if let message = statusMessage {
                VStack(spacing: 8) {
                    Image(systemName: message.icon)
                        .font(.title2)
                    Text(message.text)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.center)
                    if message.offersDemo {
                        Button("Play the demo riff") { engine.toggleDemoRiff() }
                            .buttonStyle(.glassProminent)
                            .tint(color)
                            .disabled(!engine.canPlayDemoRiff)
                    }
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding()
            }
        }
        .frame(height: 190)
        .overlay(alignment: .bottomLeading) {
            Text(lens.caption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .padding(8)
        }
        .animation(.easeInOut(duration: 0.25), value: model.isSilent)
    }

    private struct StatusMessage {
        let icon: String
        let text: String
        var offersDemo = false
    }

    private var statusMessage: StatusMessage? {
        if !engine.isRunning {
            return StatusMessage(icon: "play.circle", text: "Start the engine to see the signal")
        }
        if model.isSilent {
            return StatusMessage(icon: "guitars", text: "Play a note – or let the demo riff play for you", offersDemo: !engine.isDemoRiffPlaying)
        }
        return nil
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Into the pedal", color: .white.opacity(0.55))
            legendItem("Out of the pedal", color: color)
            Spacer()
            if !effect.isEnabled {
                Label("Pedal is off – the lines match", systemImage: "power")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                Button("Turn on") { engine.toggleEffect(effect) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.glass)
            }
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 16, height: 4)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Findings

    private struct Finding: Identifiable {
        let id: String
        let before: String
        let after: String
        let hint: String

        var spoken: String { "\(id), \(before) before, \(after) after" }
    }

    private var findings: some View {
        HStack(spacing: 8) {
            ForEach(findingList) { finding in
                VStack(alignment: .leading, spacing: 3) {
                    Text(finding.id)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    HStack(spacing: 4) {
                        Text(finding.before).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(color)
                        Text(finding.after).fontWeight(.semibold)
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .monospacedDigit()
                    Text(finding.hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: CornerRadius.md))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(finding.id)
                .accessibilityValue("\(finding.before) before the pedal, \(finding.after) after")
                .accessibilityHint(finding.hint)
            }
        }
        .contentTransition(.numericText())
    }

    private var findingList: [Finding] {
        let m = model.measurements
        func db(_ x: Float) -> String { "\(Int(x.rounded())) dB" }
        func hz(_ x: Float) -> String {
            x >= 1000 ? String(format: "%.1f kHz", x / 1000) : "\(Int(x.rounded())) Hz"
        }
        let peakiness = Finding(id: "Peakiness", before: db(m.crestBefore), after: db(m.crestAfter), hint: "Peak vs. average – clipping lowers it")
        let brightness = Finding(id: "Brightness", before: hz(m.brightnessBefore), after: hz(m.brightnessAfter), hint: "Centre of the spectrum – higher is brighter")
        let range = Finding(id: "Loud–soft range", before: db(m.swingBefore), after: db(m.swingAfter), hint: "How far the volume moves")
        let gaps = Finding(id: "Quiet gaps", before: db(m.floorBefore), after: db(m.floorAfter), hint: "Between notes – echoes fill them")
        let level = Finding(id: "Level", before: db(m.levelBefore), after: db(m.levelAfter), hint: "Average loudness")

        switch effect.type {
        case .overdrive, .distortion, .fuzz: return [peakiness, brightness, level]
        case .compressor: return [range, peakiness, level]
        case .equalizer: return [brightness, level]
        case .chorus, .phaser, .flanger: return [brightness, level]
        case .tremolo: return [range, level]
        case .delay, .reverb: return [gaps, range]
        }
    }

    // MARK: - Explanation

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(effect.type.physicsHeadline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(effect.type.physicsExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Signal Plot

private struct SignalPlot: View {
    let lens: SignalLens
    let model: SignalLabModel
    let color: Color
    /// What the measurements say, read by VoiceOver with the chart.
    let summary: String

    var body: some View {
        Canvas { context, size in
            drawGrid(in: &context, size: size)
            switch lens {
            case .wave:
                let scale = max(0.02, (model.waveBefore + model.waveAfter).map(abs).max() ?? 0) * 1.1
                stroke(model.waveBefore.map { 0.5 - CGFloat($0 / scale) / 2 }, in: &context, size: size,
                       color: .white.opacity(0.5), width: 1.5)
                stroke(model.waveAfter.map { 0.5 - CGFloat($0 / scale) / 2 }, in: &context, size: size,
                       color: color, width: 2.5)
            case .volume:
                let toY: (Float) -> CGFloat = { v in
                    let db = 20 * log10(max(v, 1e-6))
                    return 1 - CGFloat(min(1, max(0, (db + 60) / 60)))
                }
                fill(model.envelopeBefore.map(toY), in: &context, size: size, color: .white.opacity(0.14))
                stroke(model.envelopeBefore.map(toY), in: &context, size: size, color: .white.opacity(0.5), width: 1.5)
                stroke(model.envelopeAfter.map(toY), in: &context, size: size, color: color, width: 2.5)
            case .frequencies:
                fill(model.spectrumBefore.map { 1 - CGFloat($0) }, in: &context, size: size, color: .white.opacity(0.16))
                stroke(model.spectrumBefore.map { 1 - CGFloat($0) }, in: &context, size: size, color: .white.opacity(0.5), width: 1.5)
                stroke(model.spectrumAfter.map { 1 - CGFloat($0) }, in: &context, size: size, color: color, width: 2.5)
            }
        }
        .overlay(alignment: .topTrailing) { axisLabels }
        .audioGraph(chart)
    }

    // MARK: - Chart for VoiceOver

    private var chart: AudioGraphChart {
        func series(_ name: String, _ values: [Float], x: (Int) -> Double, y: (Float) -> Double) -> AudioGraphChart.Series {
            let stride = max(1, values.count / 64)
            let points = Swift.stride(from: 0, to: values.count, by: stride).map { (x: x($0), y: y(values[$0])) }
            return .init(name: name, points: points)
        }
        let title = "Signal Lab, \(lens.rawValue.lowercased())"
        switch lens {
        case .wave:
            let ms = { (i: Int) in Double(i) / Double(max(1, SignalLabModel.waveLength - 1)) * 11 }
            return AudioGraphChart(
                title: title, summary: summary,
                x: .init(title: "Time", range: 0...11) { String(format: "%.1f ms", $0) },
                y: .init(title: "Amplitude", range: -1...1) { String(format: "%.2f", $0) },
                series: [series("Into the pedal", model.waveBefore, x: ms, y: Double.init),
                         series("Out of the pedal", model.waveAfter, x: ms, y: Double.init)])
        case .volume:
            let count = max(model.envelopeBefore.count, model.envelopeAfter.count, 2)
            let seconds = { (i: Int) in Double(i) / Double(count - 1) * 3 - 3 }
            let db = { (v: Float) in Double(max(-60, 20 * log10(max(v, 1e-6)))) }
            return AudioGraphChart(
                title: title, summary: summary,
                x: .init(title: "Time", range: -3...0) { String(format: "%.1f s", $0) },
                y: .decibels(-60...0),
                series: [series("Into the pedal", model.envelopeBefore, x: seconds, y: db),
                         series("Out of the pedal", model.envelopeAfter, x: seconds, y: db)])
        case .frequencies:
            let range = SignalLabModel.spectrumRange
            let hz = { (i: Int) in
                Double(range.lowerBound) * pow(Double(range.upperBound / range.lowerBound),
                                               Double(i) / Double(SignalLabModel.spectrumBands - 1))
            }
            return AudioGraphChart(
                title: title, summary: summary,
                x: .frequency(Double(range.lowerBound)...Double(range.upperBound)),
                y: .init(title: "Energy", range: 0...1) { "\(Int(($0 * 100).rounded())) percent" },
                series: [series("Into the pedal", model.spectrumBefore, x: hz, y: Double.init),
                         series("Out of the pedal", model.spectrumAfter, x: hz, y: Double.init)])
        }
    }

    @ViewBuilder
    private var axisLabels: some View {
        let labels: [String] = switch lens {
        case .wave: ["+", "0", "−"]
        case .volume: ["0 dB", "−30", "−60"]
        case .frequencies: ["100 Hz · 1 kHz · 10 kHz"]
        }
        if lens == .frequencies {
            Text(labels[0])
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        } else {
            VStack(alignment: .trailing) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                    if label != labels.last { Spacer() }
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var grid = Path()
        for fraction in [0.25, 0.5, 0.75] {
            grid.move(to: CGPoint(x: 0, y: size.height * fraction))
            grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
        }
        if lens == .frequencies {
            // Decade lines at 100 Hz, 1 kHz and 10 kHz on the log axis
            let lo = log2(Double(SignalLabModel.spectrumRange.lowerBound))
            let hi = log2(Double(SignalLabModel.spectrumRange.upperBound))
            for f in [100.0, 1000, 10_000] {
                let x = size.width * (log2(f) - lo) / (hi - lo)
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)
    }

    /// `points` are y positions in 0…1 (top to bottom), spread evenly across the width.
    private func path(_ points: [CGFloat], size: CGSize) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let step = size.width / CGFloat(points.count - 1)
        for (i, y) in points.enumerated() {
            let point = CGPoint(x: CGFloat(i) * step, y: y * size.height)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }

    private func stroke(_ points: [CGFloat], in context: inout GraphicsContext, size: CGSize, color: Color, width: CGFloat) {
        context.stroke(path(points, size: size), with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func fill(_ points: [CGFloat], in context: inout GraphicsContext, size: CGSize, color: Color) {
        var area = path(points, size: size)
        guard !area.isEmpty else { return }
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()
        context.fill(area, with: .color(color))
    }
}
