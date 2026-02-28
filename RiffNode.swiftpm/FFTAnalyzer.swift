import Accelerate
import AVFoundation
import SwiftUI

// MARK: - FFT Analyzer
// Real-time Fast Fourier Transform for frequency spectrum analysis
// Uses Apple's Accelerate framework (vDSP) for high-performance DSP

@Observable
@MainActor
final class FFTAnalyzer {

    // MARK: - Configuration

    /// FFT size (must be power of 2)
    private let fftSize: Int = 2048

    /// Number of frequency bins to display
    let binCount: Int = 64

    /// Sample rate (will be set from audio engine)
    var sampleRate: Double = 44100

    // MARK: - Output Data

    /// Magnitude spectrum (0.0 to 1.0 normalized)
    private(set) var magnitudes: [Float] = []

    /// Frequency labels for each bin
    private(set) var frequencies: [Float] = []

    /// Peak frequency in Hz
    private(set) var peakFrequency: Float = 0

    /// Peak magnitude (0.0 to 1.0)
    private(set) var peakMagnitude: Float = 0

    /// Dominant frequency band description
    private(set) var dominantBand: String = "—"

    /// Cached band energies — updated once per analyze() call, not per SwiftUI render
    private(set) var cachedBandEnergies: [String: Float] = [:]

    // MARK: - FFT Setup (Accelerate/vDSP)

    private var fftSetup: OpaquePointer?
    private var window: [Float] = []
    private var realPart: [Float] = []
    private var imagPart: [Float] = []

    // Pre-allocated intermediate buffers — reused every analyze() call to avoid heap churn
    private var _outReal: [Float] = []
    private var _outImag: [Float] = []
    private var _magRaw: [Float] = []
    private var _magDB: [Float] = []

    /// Flag indicating if FFT setup was successful
    private var isSetupValid: Bool = false

    // MARK: - Initialization

    init() {
        setupFFT()
        magnitudes = Array(repeating: 0, count: binCount)
        frequencies = calculateFrequencyLabels()
    }

    // MARK: - Setup

    private func setupFFT() {
        // Create DFT setup for forward transform
        fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        )

        // Validate setup succeeded
        guard fftSetup != nil else {
            print("⚠️ FFTAnalyzer: Failed to create DFT setup")
            isSetupValid = false
            return
        }

        // Create Hanning window to reduce spectral leakage
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        // Allocate buffers (once — reused every analyze() call)
        realPart = [Float](repeating: 0, count: fftSize)
        imagPart = [Float](repeating: 0, count: fftSize)
        _outReal = [Float](repeating: 0, count: fftSize)
        _outImag = [Float](repeating: 0, count: fftSize)
        _magRaw  = [Float](repeating: 0, count: fftSize / 2)
        _magDB   = [Float](repeating: 0, count: fftSize / 2)

        // Mark setup as valid
        isSetupValid = true
        print("✅ FFTAnalyzer: Setup complete (fftSize: \(fftSize), binCount: \(binCount))")
    }

    private func calculateFrequencyLabels() -> [Float] {
        var labels: [Float] = []
        let nyquist = Float(sampleRate / 2)
        let binWidth = nyquist / Float(binCount)

        for i in 0..<binCount {
            labels.append(Float(i) * binWidth + binWidth / 2)
        }
        return labels
    }

    // MARK: - Process Audio Buffer

    /// Analyze audio samples and compute frequency spectrum
    /// - Parameter samples: Audio samples (mono, Float)
    func analyze(samples: [Float]) {
        // Defensive: Check all preconditions
        guard isSetupValid else { return }
        guard samples.count >= fftSize else { return }
        guard let setup = fftSetup else { return }
        guard fftSize > 0, window.count == fftSize else { return }

        // Take the most recent fftSize samples with bounds checking
        let startIndex = max(0, samples.count - fftSize)
        let endIndex = min(startIndex + fftSize, samples.count)
        guard endIndex > startIndex else { return }

        var inputSamples = Array(samples[startIndex..<endIndex])

        // Ensure we have exactly fftSize samples
        guard inputSamples.count == fftSize else { return }

        // Apply Hanning window
        vDSP_vmul(inputSamples, 1, window, 1, &inputSamples, 1, vDSP_Length(fftSize))

        // Prepare for DFT — copy input into realPart, zero imagPart (reuse pre-allocated buffers)
        realPart = inputSamples
        vDSP_vclr(&imagPart, 1, vDSP_Length(fftSize))

        // Perform FFT — write into pre-allocated output buffers (no allocation)
        vDSP_DFT_Execute(setup, realPart, imagPart, &_outReal, &_outImag)

        // Calculate magnitudes — write into pre-allocated _magRaw (no allocation)
        let halfSize = fftSize / 2
        _outReal.withUnsafeBufferPointer { realBuf in
            _outImag.withUnsafeBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realBuf.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagBuf.baseAddress!)
                )
                vDSP_zvabs(&splitComplex, 1, &_magRaw, 1, vDSP_Length(halfSize))
            }
        }

        // Convert to dB — write into pre-allocated _magDB (no allocation)
        var reference: Float = 1.0
        vDSP_vdbcon(_magRaw, 1, &reference, &_magDB, 1, vDSP_Length(halfSize), 0)

        // Bin the frequencies for display
        let binnedMagnitudes = binMagnitudes(_magDB, fromSize: halfSize, toSize: binCount)

        // Normalize to 0-1 range (vectorized)
        let normalizedMagnitudes = normalizeMagnitudes(binnedMagnitudes)

        // Find peak using vDSP (vectorized max search)
        var peakVal: Float = 0
        var peakIdx: vDSP_Length = 0
        vDSP_maxvi(_magRaw, 1, &peakVal, &peakIdx, vDSP_Length(halfSize))
        let freqResolution = Float(sampleRate) / Float(fftSize)
        peakFrequency = Float(peakIdx) * freqResolution
        peakMagnitude = normalizedMagnitudes.max() ?? 0
        dominantBand = classifyFrequencyBand(peakFrequency)

        // Update output with vectorized smoothing
        updateMagnitudesWithSmoothing(normalizedMagnitudes)

        // Cache band energies once per analysis cycle (not per render frame)
        cachedBandEnergies = computeBandEnergies()
    }

    // MARK: - Helpers

    private func binMagnitudes(_ input: [Float], fromSize: Int, toSize: Int) -> [Float] {
        var output = [Float](repeating: 0, count: toSize)
        let binSize = fromSize / toSize

        for i in 0..<toSize {
            let start = i * binSize
            let end = min(start + binSize, fromSize)
            var sum: Float = 0
            var count: Float = 0

            for j in start..<end {
                sum += input[j]
                count += 1
            }
            output[i] = count > 0 ? sum / count : 0
        }
        return output
    }

    private func normalizeMagnitudes(_ input: [Float]) -> [Float] {
        // PERF: Vectorized version of map { clamp(x, -80, 0) } then scale to 0-1
        var result = [Float](repeating: 0, count: input.count)
        var minVal: Float = -80
        var maxVal: Float = 0
        // Clip to [-80, 0] dB range
        vDSP_vclip(input, 1, &minVal, &maxVal, &result, 1, vDSP_Length(input.count))
        // Shift up by 80: result = result + 80  (so range becomes [0, 80])
        var addVal: Float = 80
        vDSP_vsadd(result, 1, &addVal, &result, 1, vDSP_Length(input.count))
        // Scale to [0, 1]: result = result / 80
        var scaleVal: Float = 1.0 / 80.0
        vDSP_vsmul(result, 1, &scaleVal, &result, 1, vDSP_Length(input.count))
        return result
    }

    private func updateMagnitudesWithSmoothing(_ newValues: [Float]) {
        if magnitudes.count != newValues.count {
            magnitudes = newValues
            return
        }
        // PERF: vDSP_vsmsma computes: C = A*D + B*E in one vectorized pass
        // magnitudes = magnitudes*(1-smoothing) + newValues*smoothing
        var alpha: Float = 0.4  // 1 - smoothing (0.6)
        var beta:  Float = 0.6  // smoothing
        newValues.withUnsafeBufferPointer { newBuf in
            vDSP_vsmsma(
                magnitudes, 1, &alpha,
                newBuf.baseAddress!, 1, &beta,
                &magnitudes, 1,
                vDSP_Length(magnitudes.count)
            )
        }
    }

    private func classifyFrequencyBand(_ frequency: Float) -> String {
        switch frequency {
        case 0..<60: return "Sub Bass"
        case 60..<250: return "Bass"
        case 250..<500: return "Low Mid"
        case 500..<2000: return "Mid"
        case 2000..<4000: return "High Mid"
        case 4000..<6000: return "Presence"
        case 6000...: return "Brilliance"
        default: return "—"
        }
    }

    // MARK: - Frequency Band Analysis for Educational Display

    /// Returns cached band energies (computed once per analyze() call, not per render)
    func getBandEnergies() -> [String: Float] { cachedBandEnergies }

    private func computeBandEnergies() -> [String: Float] {
        guard magnitudes.count == binCount else { return [:] }

        let nyquist = Float(sampleRate / 2)
        let binWidth = nyquist / Float(binCount)

        var bass: Float = 0, bassCount: Float = 0
        var mid: Float = 0, midCount: Float = 0
        var high: Float = 0, highCount: Float = 0

        for i in 0..<binCount {
            let freq = Float(i) * binWidth
            let mag = magnitudes[i]
            if freq < 250 {
                bass += mag; bassCount += 1
            } else if freq < 4000 {
                mid += mag; midCount += 1
            } else {
                high += mag; highCount += 1
            }
        }

        return [
            "Bass":  bassCount  > 0 ? bass  / bassCount  : 0,
            "Mid":   midCount   > 0 ? mid   / midCount   : 0,
            "Highs": highCount  > 0 ? high  / highCount  : 0
        ]
    }
}

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
