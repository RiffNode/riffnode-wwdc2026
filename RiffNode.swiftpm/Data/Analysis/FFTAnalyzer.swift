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
