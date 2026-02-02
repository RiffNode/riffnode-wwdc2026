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

    // MARK: - FFT Setup (Accelerate/vDSP)

    private var fftSetup: OpaquePointer?
    private var window: [Float] = []
    private var realPart: [Float] = []
    private var imagPart: [Float] = []

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

        // Allocate buffers
        realPart = [Float](repeating: 0, count: fftSize)
        imagPart = [Float](repeating: 0, count: fftSize)

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

        // Prepare for DFT (real input, imaginary = 0)
        realPart = inputSamples
        imagPart = [Float](repeating: 0, count: fftSize)

        // Output buffers
        var outReal = [Float](repeating: 0, count: fftSize)
        var outImag = [Float](repeating: 0, count: fftSize)

        // Perform FFT
        vDSP_DFT_Execute(setup, realPart, imagPart, &outReal, &outImag)

        // Calculate magnitudes (only first half - Nyquist)
        let halfSize = fftSize / 2
        var magnitudesRaw = [Float](repeating: 0, count: halfSize)

        // magnitude = sqrt(real^2 + imag^2)
        for i in 0..<halfSize {
            let real = outReal[i]
            let imag = outImag[i]
            magnitudesRaw[i] = sqrt(real * real + imag * imag)
        }

        // Convert to decibels and normalize
        var magnitudesDB = [Float](repeating: 0, count: halfSize)
        var reference: Float = 1.0
        vDSP_vdbcon(magnitudesRaw, 1, &reference, &magnitudesDB, 1, vDSP_Length(halfSize), 0)

        // Bin the frequencies for display
        let binnedMagnitudes = binMagnitudes(magnitudesDB, fromSize: halfSize, toSize: binCount)

        // Normalize to 0-1 range
        let normalizedMagnitudes = normalizeMagnitudes(binnedMagnitudes)

        // Find peak
        if let maxIndex = magnitudesRaw.indices.max(by: { magnitudesRaw[$0] < magnitudesRaw[$1] }) {
            let freqResolution = Float(sampleRate) / Float(fftSize)
            peakFrequency = Float(maxIndex) * freqResolution
            peakMagnitude = normalizedMagnitudes.max() ?? 0
            dominantBand = classifyFrequencyBand(peakFrequency)
        }

        // Update output with smoothing
        updateMagnitudesWithSmoothing(normalizedMagnitudes)
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
        // Map from dB scale (-80 to 0) to 0-1
        let minDB: Float = -80
        let maxDB: Float = 0

        return input.map { db in
            let clamped = max(minDB, min(maxDB, db))
            return (clamped - minDB) / (maxDB - minDB)
        }
    }

    private func updateMagnitudesWithSmoothing(_ newValues: [Float]) {
        let smoothing: Float = 0.3 // Lower = smoother

        if magnitudes.count != newValues.count {
            magnitudes = newValues
        } else {
            for i in 0..<magnitudes.count {
                magnitudes[i] = magnitudes[i] * (1 - smoothing) + newValues[i] * smoothing
            }
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

    /// Get energy in specific frequency bands (for showing effect impact)
    func getBandEnergies() -> [String: Float] {
        guard magnitudes.count == binCount else { return [:] }

        let nyquist = Float(sampleRate / 2)
        let binWidth = nyquist / Float(binCount)

        var bands: [String: Float] = [:]

        // Calculate average energy in each band
        var subBass: Float = 0, subBassCount: Float = 0
        var bass: Float = 0, bassCount: Float = 0
        var lowMid: Float = 0, lowMidCount: Float = 0
        var mid: Float = 0, midCount: Float = 0
        var highMid: Float = 0, highMidCount: Float = 0
        var high: Float = 0, highCount: Float = 0

        for i in 0..<binCount {
            let freq = Float(i) * binWidth
            let mag = magnitudes[i]

            if freq < 60 {
                subBass += mag; subBassCount += 1
            } else if freq < 250 {
                bass += mag; bassCount += 1
            } else if freq < 500 {
                lowMid += mag; lowMidCount += 1
            } else if freq < 2000 {
                mid += mag; midCount += 1
            } else if freq < 6000 {
                highMid += mag; highMidCount += 1
            } else {
                high += mag; highCount += 1
            }
        }

        bands["Sub Bass"] = subBassCount > 0 ? subBass / subBassCount : 0
        bands["Bass"] = bassCount > 0 ? bass / bassCount : 0
        bands["Low Mid"] = lowMidCount > 0 ? lowMid / lowMidCount : 0
        bands["Mid"] = midCount > 0 ? mid / midCount : 0
        bands["High Mid"] = highMidCount > 0 ? highMid / highMidCount : 0
        bands["Highs"] = highCount > 0 ? high / highCount : 0

        return bands
    }
}

// MARK: - Spectrum View with Swift Charts

import Charts

struct FFTSpectrumView: View {
    let analyzer: FFTAnalyzer
    @State private var showLabels = true

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

                // Peak info
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f Hz", analyzer.peakFrequency))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                    Text(analyzer.dominantBand)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // Spectrum Chart
            Chart {
                ForEach(Array(analyzer.magnitudes.enumerated()), id: \.offset) { index, magnitude in
                    BarMark(
                        x: .value("Bin", index),
                        y: .value("Magnitude", magnitude)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [barColor(for: index), barColor(for: index).opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 8)) { value in
                    if let index = value.as(Int.self), index < analyzer.frequencies.count {
                        AxisValueLabel {
                            Text(formatFrequency(analyzer.frequencies[index]))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                }
            }
            .chartYScale(domain: 0...1)
            .frame(height: 150)

            // Band energies
            HStack(spacing: 8) {
                ForEach(["Bass", "Mid", "Highs"], id: \.self) { band in
                    let energy = analyzer.getBandEnergies()[band] ?? 0
                    BandEnergyIndicator(band: band, energy: energy)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func barColor(for index: Int) -> Color {
        let position = Float(index) / Float(analyzer.binCount)
        if position < 0.15 {
            return .red // Sub bass / Bass
        } else if position < 0.35 {
            return .orange // Low mid
        } else if position < 0.6 {
            return .green // Mid
        } else if position < 0.8 {
            return .cyan // High mid
        } else {
            return .purple // Highs
        }
    }

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.0fk", freq / 1000)
        }
        return String(format: "%.0f", freq)
    }
}

// MARK: - Band Energy Indicator

struct BandEnergyIndicator: View {
    let band: String
    let energy: Float

    var body: some View {
        VStack(spacing: 4) {
            // Level meter
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(meterColor)
                        .frame(height: geometry.size.height * CGFloat(energy))
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
        case "Bass": return .red
        case "Mid": return .green
        case "Highs": return .cyan
        default: return .white
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
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.3))
        )
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

            // Mini spectrum bars
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { index in
                    let binIndex = index * (analyzer.binCount / 16)
                    let magnitude = binIndex < analyzer.magnitudes.count ?
                        analyzer.magnitudes[binIndex] : 0

                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(for: index))
                        .frame(width: 4, height: 8 + CGFloat(magnitude) * 24)
                }
            }
            .frame(height: 32)

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
    }

    private func barColor(for index: Int) -> Color {
        let position = Float(index) / 16.0
        if position < 0.25 { return .red.opacity(0.8) }
        if position < 0.5 { return .orange.opacity(0.8) }
        if position < 0.75 { return .green.opacity(0.8) }
        return .cyan.opacity(0.8)
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
