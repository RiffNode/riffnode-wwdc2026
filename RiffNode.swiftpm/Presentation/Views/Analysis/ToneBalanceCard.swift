import SwiftUI

// MARK: - Tone Balance
// Sits at the top of the EQ tab: where your sound sits in the spectrum (the ranges guitarists
// talk about – bass, body, mids, bite, air), what that means, and a one-tap EQ move to act on it.

struct ToneBalanceCard: View {
    let fftAnalyzer: FFTAnalyzer
    @Bindable var engine: AudioEngineManager

    /// The region shown as "where your sound sits". Held steady with hysteresis so the
    /// legend and advice don't flicker between neighbouring regions every frame.
    @State private var stableRegion: FrequencyRegion?
    @State private var candidate: (region: FrequencyRegion, since: Date)?
    @State private var appliedRegion: FrequencyRegion?

    private var isHearingSound: Bool { engine.inputLevel > 0.01 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Image(systemName: stableRegion == nil ? "ear" : "lightbulb.max.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(stableRegion?.color ?? .secondary)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.tint((stableRegion?.color ?? .gray).opacity(0.15)), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(stableRegion?.insight.title ?? "Tone balance")
                        .font(.headline)
                    Text(stableRegion?.insight.detail ?? "Play your guitar, or start the demo riff, and RiffNode will tell you where your sound sits – and how to shape it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentTransition(.opacity)

                Spacer(minLength: 0)

                if let region = stableRegion {
                    Button {
                        engine.applyToneSuggestion(region.suggestion)
                        appliedRegion = region
                    } label: {
                        Label(appliedRegion == region ? "Applied" : region.suggestion.label,
                              systemImage: appliedRegion == region ? "checkmark" : "wand.and.stars")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(region.color)
                    .disabled(appliedRegion == region)
                } else if engine.canPlayDemoRiff && !engine.isDemoRiffPlaying {
                    Button("Play demo riff", systemImage: "play.fill") { engine.startDemoRiff() }
                        .buttonStyle(.glass)
                }
            }

            // The five ranges, with the one your sound sits in lit up
            HStack(spacing: 6) {
                ForEach(FrequencyRegion.allCases, id: \.self) { region in
                    let isDominant = region == stableRegion
                    VStack(spacing: 2) {
                        Text(region.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isDominant ? region.color : .primary)
                        Text(region.feel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(region.rangeLabel)
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(region.color.opacity(isDominant ? 0.18 : 0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(Spacing.md)
        .glassEffect(.regular.tint((stableRegion?.color ?? .gray).opacity(0.08)), in: RoundedRectangle(cornerRadius: CornerRadius.xl))
        .animation(.smooth(duration: 0.3), value: stableRegion)
        .onChange(of: fftAnalyzer.logMagnitudes) { _, _ in updateStableRegion() }
        .onChange(of: isHearingSound) { _, hearing in
            if !hearing { stableRegion = nil; candidate = nil }
        }
        .onChange(of: stableRegion) { _, _ in appliedRegion = nil }
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


// MARK: - Suggestions

/// One EQ move: a band of the 10-band EQ and how far to push it.
struct ToneSuggestion: Equatable {
    let band: Int
    let gain: Float
    let label: String
}

extension FrequencyRegion {
    /// The EQ move the insight recommends (bands: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz).
    var suggestion: ToneSuggestion {
        switch self {
        case .bass: ToneSuggestion(band: 3, gain: -3, label: "Cut 250 Hz")
        case .body: ToneSuggestion(band: 3, gain: -2, label: "Tame 250 Hz")
        case .mids: ToneSuggestion(band: 5, gain: 3, label: "Boost 1 kHz")
        case .bite: ToneSuggestion(band: 7, gain: -3, label: "Cut 4 kHz")
        case .air: ToneSuggestion(band: 8, gain: -3, label: "Roll off 8 kHz")
        }
    }

    var rangeLabel: String {
        func hz(_ f: Float) -> String { f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))" }
        return "\(hz(range.lowerBound))–\(hz(range.upperBound))"
    }
}
