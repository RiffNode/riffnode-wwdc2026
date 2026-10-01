import SwiftUI

// MARK: - Analyze View
// "What am I playing?" – a tuner, the chord you're holding, and where your sound sits
// in the frequency range, with a plain-language takeaway that leads into the EQ.

struct AnalyzeView: View {
    let fftAnalyzer: FFTAnalyzer
    let chordDetector: ChordDetector
    @Bindable var engine: AudioEngineManager
    /// Jumps to the Parametric EQ so the insight turns into an action.
    var onOpenEQ: () -> Void = {}

    /// The region shown as "where your sound sits". Held steady with hysteresis so the map,
    /// legend and advice don't flicker between neighbouring regions every frame.
    @State private var stableRegion: FrequencyRegion?
    @State private var candidate: (region: FrequencyRegion, since: Date)?

    private var isHearingSound: Bool { engine.inputLevel > 0.01 }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Analyze")
                            .font(.title2.bold())
                        Text("See what you're playing, note by note and frequency by frequency.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            TunerCard(detector: chordDetector, isHearingSound: isHearingSound)
                            ChordCard(detector: chordDetector, isHearingSound: isHearingSound)
                        }
                        VStack(spacing: Spacing.md) {
                            TunerCard(detector: chordDetector, isHearingSound: isHearingSound)
                            ChordCard(detector: chordDetector, isHearingSound: isHearingSound)
                        }
                    }

                    FrequencyMapCard(analyzer: fftAnalyzer, isHearingSound: isHearingSound, dominant: stableRegion)

                    InsightCard(
                        region: stableRegion,
                        canPlayDemo: engine.canPlayDemoRiff && !engine.isDemoRiffPlaying,
                        onPlayDemo: { engine.startDemoRiff() },
                        onOpenEQ: onOpenEQ
                    )
                }
                .padding(Spacing.lg)
            }
        }
        .onChange(of: fftAnalyzer.logMagnitudes) { _, _ in updateStableRegion() }
        .onChange(of: isHearingSound) { _, hearing in
            if !hearing { stableRegion = nil; candidate = nil }
        }
    }

    /// Switch only when another region is clearly louder (+0.03) for at least 0.6 s.
    private func updateStableRegion() {
        guard isHearingSound, let loudest = FrequencyRegion.dominant(in: fftAnalyzer) else { return }
        guard let current = stableRegion else {
            stableRegion = loudest
            return
        }
        guard loudest != current,
              loudest.level(in: fftAnalyzer) > current.level(in: fftAnalyzer) + 0.03 else {
            candidate = nil
            return
        }
        if let candidate, candidate.region == loudest {
            if Date().timeIntervalSince(candidate.since) > 0.6 {
                stableRegion = loudest
                self.candidate = nil
            }
        } else {
            candidate = (loudest, Date())
        }
    }
}

// MARK: - Card Chrome

private struct AnalyzeCard<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = .riffPrimary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.06)), in: RoundedRectangle(cornerRadius: CornerRadius.xl))
    }
}

// MARK: - Tuner

private struct TunerCard: View {
    let detector: ChordDetector
    let isHearingSound: Bool

    private var hasNote: Bool { isHearingSound && detector.detectedNote != "—" }
    private var cents: Double { Double(max(-50, min(50, detector.centsDeviation))) }
    private var status: (text: String, color: Color) {
        guard hasNote else { return ("Play a single note", .secondary) }
        if detector.isInTune { return ("In tune", .green) }
        return cents < 0 ? ("Flat – tune up", .orange) : ("Sharp – tune down", .orange)
    }

    var body: some View {
        AnalyzeCard(title: "Tuner", icon: "tuningfork", tint: status.color) {
            VStack(spacing: 10) {
                TunerGauge(cents: hasNote ? cents : 0, isActive: hasNote, color: status.color)
                    .frame(height: 96)
                    .overlay(alignment: .bottom) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(hasNote ? detector.detectedNote : "–")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                            if hasNote {
                                Text("\(detector.detectedOctave)")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .offset(y: 18)
                    }

                HStack {
                    Text(status.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status.color)
                    Spacer()
                    if hasNote {
                        Text(String(format: "%.1f Hz · %+.0f¢", detector.detectedPitch, cents))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 18)
            }
            .animation(.snappy, value: detector.detectedNote)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasNote ? "Tuner: \(detector.detectedNote), \(status.text)" : "Tuner: no note")
    }
}

/// A half-circle cents gauge: the green wedge is "in tune" (±5 cents).
private struct TunerGauge: View {
    let cents: Double
    let isActive: Bool
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height)
            let radius = min(size.width / 2, size.height) - 6

            func point(_ c: Double, _ r: CGFloat) -> CGPoint {
                let angle = Angle.degrees(180 + (c + 50) / 100 * 180).radians
                return CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            }

            // In-tune zone
            var zone = Path()
            zone.addArc(center: center, radius: radius,
                        startAngle: .degrees(180 + 45 / 100 * 180), endAngle: .degrees(180 + 55 / 100 * 180), clockwise: false)
            context.stroke(zone, with: .color(.green.opacity(0.35)), style: StrokeStyle(lineWidth: 10, lineCap: .round))

            // Ticks every 10 cents
            for tick in stride(from: -50.0, through: 50, by: 10) {
                var path = Path()
                path.move(to: point(tick, radius - (tick == 0 ? 14 : 8)))
                path.addLine(to: point(tick, radius))
                context.stroke(path, with: .color(.secondary.opacity(tick == 0 ? 0.8 : 0.4)), lineWidth: tick == 0 ? 2 : 1)
            }

            // Needle
            var needle = Path()
            needle.move(to: point(cents, 0))
            needle.addLine(to: point(cents, radius - 2))
            context.stroke(needle, with: .color(isActive ? color : .secondary.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cents)
    }
}

// MARK: - Chord

private struct ChordCard: View {
    let detector: ChordDetector
    let isHearingSound: Bool

    private var hasChord: Bool { isHearingSound && detector.detectedChord != "—" && !detector.detectedChord.isEmpty }

    var body: some View {
        AnalyzeCard(title: "Chord", icon: "pianokeys", tint: .purple) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hasChord ? detector.detectedChord : "Strum a chord")
                        .font(.system(size: hasChord ? 30 : 20, weight: .bold, design: .rounded))
                        .foregroundStyle(hasChord ? .primary : .secondary)
                        .contentTransition(.opacity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(hasChord ? "Notes I can hear" : "RiffNode names the chord from the notes it hears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if hasChord {
                        HStack(spacing: 6) {
                            ForEach(detector.activeNotes.prefix(6), id: \.self) { note in
                                Text(note)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .glassEffect(.regular.tint(.purple.opacity(0.15)), in: Capsule())
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                Gauge(value: hasChord ? Double(detector.confidence) : 0) {
                    Text("Sure")
                } currentValueLabel: {
                    Text(hasChord ? "\(Int(detector.confidence * 100))%" : "–")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.purple)
                .accessibilityLabel("Confidence")
            }
            .frame(minHeight: 96)
            .animation(.smooth, value: hasChord)
        }
    }
}

// MARK: - Frequency Regions

/// The parts of the spectrum guitarists actually talk about.
enum FrequencyRegion: CaseIterable {
    case bass, body, mids, bite, air

    var name: String {
        switch self {
        case .bass: "Bass"
        case .body: "Body"
        case .mids: "Mids"
        case .bite: "Bite"
        case .air: "Air"
        }
    }

    var range: ClosedRange<Float> {
        switch self {
        case .bass: 40...150
        case .body: 150...500
        case .mids: 500...2_000
        case .bite: 2_000...6_000
        case .air: 6_000...16_000
        }
    }

    var feel: String {
        switch self {
        case .bass: "Thump"
        case .body: "Warmth"
        case .mids: "Punch"
        case .bite: "Pick attack"
        case .air: "Sparkle"
        }
    }

    var color: Color {
        switch self {
        case .bass: .red
        case .body: .orange
        case .mids: .green
        case .bite: .cyan
        case .air: .purple
        }
    }

    var insight: (title: String, detail: String) {
        switch self {
        case .bass:
            ("Your sound is bass-heavy",
             "Great for heavy rhythm, but it can turn muddy. A small cut around 200 Hz tightens it up.")
        case .body:
            ("Your sound is warm and full",
             "That's the body of the guitar. If it feels boomy, a gentle cut around 300 Hz cleans it up.")
        case .mids:
            ("Your sound sits in the mids",
             "That's where a guitar cuts through a band – classic rock lives here. Boost 1 kHz to push it forward.")
        case .bite:
            ("Lots of bite and pick attack",
             "Distortion adds a lot up here. If it starts to sound harsh, try a cut around 4 kHz.")
        case .air:
            ("Bright and sparkly",
             "Perfect for clean tones – reverb and chorus shine here. Roll off above 8 kHz if it gets fizzy.")
        }
    }

    /// Average level of a region on the analyzer's log spectrum (0–1).
    @MainActor
    func level(in analyzer: FFTAnalyzer) -> Float {
        let values = zip(analyzer.logFrequencies, analyzer.logMagnitudes)
            .filter { range.contains($0.0) }
            .map(\.1)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    @MainActor
    static func dominant(in analyzer: FFTAnalyzer) -> FrequencyRegion? {
        guard !analyzer.logMagnitudes.isEmpty else { return nil }
        return allCases.max { $0.level(in: analyzer) < $1.level(in: analyzer) }
    }
}

// MARK: - Frequency Map

private struct FrequencyMapCard: View {
    let analyzer: FFTAnalyzer
    let isHearingSound: Bool
    let dominant: FrequencyRegion?

    var body: some View {
        AnalyzeCard(title: "Where your sound sits", icon: "waveform.path.ecg", tint: .cyan) {
            VStack(spacing: 10) {
                Canvas { context, size in
                    func x(_ frequency: Float) -> CGFloat {
                        let logMin = log10(Float(40)), logMax = log10(Float(16_000))
                        return CGFloat((log10(max(frequency, 40)) - logMin) / (logMax - logMin)) * size.width
                    }

                    // Region bands
                    for region in FrequencyRegion.allCases {
                        let rect = CGRect(x: x(region.range.lowerBound), y: 0,
                                          width: x(region.range.upperBound) - x(region.range.lowerBound),
                                          height: size.height)
                        let isDominant = region == dominant
                        context.fill(Path(rect), with: .color(region.color.opacity(isDominant ? 0.16 : 0.05)))
                    }

                    // Spectrum
                    let points = zip(analyzer.logFrequencies, analyzer.logMagnitudes)
                        .filter { $0.0 >= 40 && $0.0 <= 16_000 }
                    guard isHearingSound, points.count > 1 else { return }
                    var path = Path()
                    path.move(to: CGPoint(x: x(points[0].0), y: size.height))
                    for (frequency, magnitude) in points {
                        let level = CGFloat(min(max((magnitude - 0.3) / 0.7, 0), 1))
                        path.addLine(to: CGPoint(x: x(frequency), y: size.height - level * size.height * 0.9))
                    }
                    path.addLine(to: CGPoint(x: x(points[points.count - 1].0), y: size.height))
                    path.closeSubpath()
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [Color.cyan.opacity(0.55), Color.cyan.opacity(0.08)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if !isHearingSound {
                        Text("Play something to see your sound here")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Region legend – what each band means to a guitarist
                HStack(spacing: 6) {
                    ForEach(FrequencyRegion.allCases, id: \.self) { region in
                        VStack(spacing: 2) {
                            Text(region.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(region == dominant ? region.color : .primary)
                            Text(region.feel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(region.color.opacity(region == dominant ? 0.15 : 0), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .animation(.smooth(duration: 0.3), value: dominant)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dominant.map { "Frequency map: most energy in the \($0.name.lowercased())" } ?? "Frequency map: no sound")
    }
}

// MARK: - Insight

private struct InsightCard: View {
    let region: FrequencyRegion?
    let canPlayDemo: Bool
    let onPlayDemo: () -> Void
    let onOpenEQ: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: region == nil ? "ear" : "lightbulb.max.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(region?.color ?? .secondary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint((region?.color ?? .gray).opacity(0.15)), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(region?.insight.title ?? "Waiting for sound")
                    .font(.headline)
                Text(region?.insight.detail ?? "Play your guitar, or start the demo riff, and RiffNode will explain what it hears.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentTransition(.opacity)

            Spacer(minLength: 0)

            if region != nil {
                Button("Shape it in EQ", systemImage: "slider.horizontal.3", action: onOpenEQ)
                    .buttonStyle(.glassProminent)
                    .tint(.riffPrimary)
            } else if canPlayDemo {
                Button("Play demo riff", systemImage: "play.fill", action: onPlayDemo)
                    .buttonStyle(.glass)
            }
        }
        .padding(Spacing.md)
        .glassEffect(.regular.tint((region?.color ?? .gray).opacity(0.08)), in: RoundedRectangle(cornerRadius: CornerRadius.xl))
        .animation(.smooth(duration: 0.3), value: region)
    }
}
