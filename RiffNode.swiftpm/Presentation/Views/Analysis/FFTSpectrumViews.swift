import Accelerate
import AVFoundation
import SwiftUI

// MARK: - Spectrum View (Canvas-based — no Charts framework)

struct FFTSpectrumView: View {
    let analyzer: FFTAnalyzer

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.cyan)
                    Text("SPECTRUM ANALYZER")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f Hz", analyzer.peakFrequency))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                    Text(analyzer.dominantBand)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // Canvas spectrum — single GPU draw call instead of 32 BarMark views
            Canvas { context, size in
                let mags = analyzer.magnitudes
                guard mags.count > 1 else { return }

                let displayCount = mags.count / 2   // every other bin
                let barW = size.width / CGFloat(displayCount)

                for i in 0..<displayCount {
                    let binIdx = i * 2
                    let mag = CGFloat(binIdx < mags.count ? mags[binIdx] : 0)
                    let barH = max(2, mag * size.height)
                    let rect = CGRect(x: CGFloat(i) * barW + 0.5,
                                      y: size.height - barH,
                                      width: max(1, barW - 1),
                                      height: barH)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                                 with: .color(spectrumColor(bin: binIdx, total: mags.count)))
                }
            }
            .frame(height: 150)
            .animation(.none, value: analyzer.magnitudes)

            // Band energy meters
            HStack(spacing: 8) {
                ForEach(["Bass", "Mid", "Highs"], id: \.self) { band in
                    BandEnergyIndicator(band: band,
                                        energy: analyzer.cachedBandEnergies[band] ?? 0)
                }
            }
            .animation(.none, value: analyzer.magnitudes)
        }
        .padding()
        .glassEffect(.regular.tint(.cyan.opacity(0.1)), in: RoundedRectangle(cornerRadius: 12))
    }

    private func spectrumColor(bin: Int, total: Int) -> Color {
        let p = Float(bin) / Float(max(total, 1))
        if p < 0.15 { return .red }
        if p < 0.35 { return .orange }
        if p < 0.60 { return .green }
        if p < 0.80 { return .cyan }
        return .purple
    }
}

// MARK: - Band Energy Indicator

struct BandEnergyIndicator: View {
    let band: String
    let energy: Float

    var body: some View {
        VStack(spacing: 4) {
            // Canvas meter — no GeometryReader, no layout passes
            Canvas { context, size in
                // Track
                context.fill(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height), cornerRadius: 4),
                    with: .color(.white.opacity(0.1))
                )
                // Fill
                let fillH = size.height * CGFloat(energy)
                if fillH > 1 {
                    context.fill(
                        Path(roundedRect: CGRect(x: 0, y: size.height - fillH,
                                                 width: size.width, height: fillH), cornerRadius: 4),
                        with: .color(meterColor)
                    )
                }
            }
            .frame(width: 30, height: 40)

            Text(band)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var meterColor: Color {
        switch band {
        case "Bass":  return .red
        case "Mid":   return .green
        case "Highs": return .cyan
        default:      return .white
        }
    }
}

// MARK: - Educational Spectrum View (Shows Effect Impact)

struct EducationalSpectrumView: View {
    let analyzer: FFTAnalyzer
    let effectName: String
    let effectDescription: String

    var body: some View {
        VStack(spacing: 16) {
            // Effect info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(effectName.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.cyan)

                    Text(effectDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Live spectrum
            FFTSpectrumView(analyzer: analyzer)

            // Educational note about what to observe
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)

                Text(getEducationalNote())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.yellow.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .glassEffect(.regular.tint(.cyan.opacity(0.08)), in: RoundedRectangle(cornerRadius: 16))
    }

    private func getEducationalNote() -> String {
        switch effectName.lowercased() {
        case "distortion", "overdrive", "fuzz":
            return "Watch the high frequencies increase! Distortion adds harmonics (overtones) to your signal."
        case "reverb":
            return "Notice how the sound sustains longer across all frequencies - that's the reverb tail."
        case "delay":
            return "The spectrum pulses as echoes repeat. Each echo is slightly quieter."
        case "chorus":
            return "Slight frequency shifts create that shimmering, doubled sound."
        case "compressor":
            return "Compression evens out the peaks - watch the levels become more consistent."
        case "equalizer", "eq":
            return "Adjust the bands and watch specific frequency ranges boost or cut in real-time."
        default:
            return "Observe how this effect changes the frequency content of your guitar signal."
        }
    }
}

// MARK: - Mini Spectrum Indicator
// Compact always-visible spectrum display to ensure FFT analyzer stays observed
// Placed in left panel so analyzers always have active SwiftUI observers

struct MiniSpectrumIndicator: View {
    let analyzer: FFTAnalyzer

    var body: some View {
        HStack(spacing: 12) {
            // Spectrum icon
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.cyan)

            // Mini spectrum — single Canvas draw call instead of 8 SwiftUI views
            let mags = analyzer.magnitudes
            let barColors: [Color] = [
                .red.opacity(0.8), .red.opacity(0.8),
                .orange.opacity(0.8), .orange.opacity(0.8),
                .green.opacity(0.8), .green.opacity(0.8),
                .cyan.opacity(0.8), .cyan.opacity(0.8)
            ]
            Canvas { context, size in
                let barCount = 8
                let barW = (size.width - CGFloat(barCount - 1) * 3) / CGFloat(barCount)
                for i in 0..<barCount {
                    let binIdx = i * (mags.count / max(barCount, 1))
                    let mag = CGFloat(binIdx < mags.count ? mags[binIdx] : 0)
                    let barH = max(4, 8 + mag * 24)
                    let x = CGFloat(i) * (barW + 3)
                    let rect = CGRect(x: x, y: size.height - barH, width: barW, height: barH)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(barColors[i])
                    )
                }
            }
            .frame(width: 67, height: 32)

            Spacer()

            // Peak frequency indicator
            VStack(alignment: .trailing, spacing: 2) {
                Text("Peak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(formatFrequency(analyzer.peakFrequency))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .animation(.none, value: analyzer.magnitudes)
    }

    private func miniBarColor(_ index: Int) -> Color {
        switch index {
        case 0, 1: return .red.opacity(0.8)
        case 2, 3: return .orange.opacity(0.8)
        case 4, 5: return .green.opacity(0.8)
        default:   return .cyan.opacity(0.8)
        }
    }

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk", freq / 1000)
        }
        return String(format: "%.0f Hz", freq)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var previewAnalyzer = FFTAnalyzer()
    VStack(spacing: 20) {
        FFTSpectrumView(analyzer: previewAnalyzer)
        MiniSpectrumIndicator(analyzer: previewAnalyzer)
    }
    .padding()
    .background(Color.black)
}
