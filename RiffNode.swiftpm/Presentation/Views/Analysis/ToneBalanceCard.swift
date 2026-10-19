import SwiftUI

// MARK: - Tone Balance
// Sits at the top of the EQ tab: where your sound sits in the spectrum (the ranges guitarists
// talk about – bass, body, mids, bite, air), what that means, and a one-tap EQ move to act on it.

struct ToneBalanceCard: View {
    @State private var viewModel: ToneBalanceViewModel

    init(fftAnalyzer: any SpectrumProviding, engine: any ToneBalanceEngine) {
        _viewModel = State(initialValue: ToneBalanceViewModel(engine: engine, analyzer: fftAnalyzer))
    }

    private var region: FrequencyRegion? { viewModel.region }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Image(systemName: region == nil ? "ear" : "lightbulb.max.fill")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(region?.color ?? .secondary)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.tint((region?.color ?? .gray).opacity(0.15)), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(region?.insight.title ?? "Tone balance")
                        .font(.headline)
                    Text(region?.insight.detail ?? "Play your guitar, or start the demo riff, and RiffNode will tell you where your sound sits – and how to shape it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentTransition(.opacity)

                Spacer(minLength: 0)

                if let region {
                    let applied = viewModel.appliedRegion == region
                    Button(action: viewModel.applySuggestion) {
                        Label(applied ? "Applied" : region.suggestion.label,
                              systemImage: applied ? "checkmark" : "wand.and.stars")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(region.color)
                    .disabled(applied)
                } else if viewModel.canOfferDemo {
                    Button("Play demo riff", systemImage: "play.fill", action: viewModel.playDemo)
                        .buttonStyle(.glass)
                }
            }

            // The five ranges, with the one your sound sits in lit up
            HStack(spacing: 6) {
                ForEach(FrequencyRegion.allCases, id: \.self) { range in
                    let isDominant = range == region
                    VStack(spacing: 2) {
                        Text(range.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isDominant ? range.color : .primary)
                        Text(range.feel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(range.rangeLabel)
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(range.color.opacity(isDominant ? 0.18 : 0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(Spacing.md)
        .glassEffect(.regular.tint((region?.color ?? .gray).opacity(0.08)), in: RoundedRectangle(cornerRadius: CornerRadius.xl))
        .animation(.smooth(duration: 0.3), value: region)
        .onChange(of: viewModel.analyzer.logMagnitudes) { _, _ in viewModel.spectrumDidUpdate() }
        .onChange(of: viewModel.isHearingSound) { _, _ in viewModel.spectrumDidUpdate() }
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
    func level(in analyzer: any SpectrumProviding) -> Float {
        let values = zip(analyzer.logFrequencies, analyzer.logMagnitudes)
            .filter { range.contains($0.0) }
            .map(\.1)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    @MainActor
    static func dominant(in analyzer: any SpectrumProviding) -> FrequencyRegion? {
        guard !analyzer.logMagnitudes.isEmpty else { return nil }
        return allCases.max { $0.level(in: analyzer) < $1.level(in: analyzer) }
    }
}

// MARK: - Suggestions

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
