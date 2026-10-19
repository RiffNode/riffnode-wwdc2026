import Accelerate
import Foundation

// MARK: - Signal Analyzer
// Turns the raw before/after captures of one pedal into a SignalAnalysis: a few cycles of
// the waveform lined up in time, the volume over the last seconds, the spectrum, and the
// measurements (level, peakiness, loudness swing, quiet floor, brightness).

final class SignalAnalyzer {
    private let fftSize = SignalProbeStore.sampleCount
    private lazy var dft = try? vDSP.DiscreteFourierTransform(
        count: fftSize, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    private lazy var window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)

    func analyze(_ snapshot: (before: SignalCapture, after: SignalCapture)) -> SignalAnalysis {
        let (before, after) = snapshot
        var result = SignalAnalysis()
        guard before.samples.count >= fftSize, after.samples.count >= fftSize else { return result }

        let beforeRMS = Self.rms(before.samples)
        result.isSilent = beforeRMS < 0.0005
        guard !result.isSilent else { return result }

        // Line the two captures up in time: the "after" tap may have run one buffer ahead.
        let lag = Int(clamping: after.endSampleTime - before.endSampleTime)
        let alignedAfter = Self.shift(after.samples, by: before.endSampleTime == 0 ? 0 : lag)

        // A rising zero crossing in the input, so the waveform stands still between frames
        let length = SignalAnalysis.waveLength
        let searchEnd = before.samples.count - length - 1
        var start = max(0, searchEnd - length)
        for i in stride(from: searchEnd, to: max(1, searchEnd - length), by: -1)
        where before.samples[i - 1] < 0 && before.samples[i] >= 0 {
            start = i
            break
        }
        result.waveBefore = Array(before.samples[start..<start + length])
        result.waveAfter = Array(alignedAfter[start..<start + length])

        result.envelopeBefore = before.envelope
        result.envelopeAfter = after.envelope
        result.spectrumBefore = spectrum(of: before.samples, sampleRate: before.sampleRate)
        result.spectrumAfter = spectrum(of: after.samples, sampleRate: after.sampleRate)

        var m = SignalMeasurements()
        m.levelBefore = Self.dB(beforeRMS)
        m.levelAfter = Self.dB(Self.rms(after.samples))
        m.crestBefore = Self.dB(Self.peak(before.samples)) - m.levelBefore
        m.crestAfter = Self.dB(Self.peak(after.samples)) - m.levelAfter
        (m.swingBefore, m.floorBefore) = Self.dynamics(of: before.envelope)
        (m.swingAfter, m.floorAfter) = Self.dynamics(of: after.envelope)
        m.brightnessBefore = brightness(of: before.samples, sampleRate: before.sampleRate)
        m.brightnessAfter = brightness(of: after.samples, sampleRate: after.sampleRate)
        result.measurements = m
        return result
    }

    // MARK: Spectrum

    private func magnitudes(of samples: [Float]) -> [Float]? {
        guard let dft else { return nil }
        let windowed = vDSP.multiply(Array(samples.suffix(fftSize)), window)
        var real = [Float](repeating: 0, count: fftSize)
        var imaginary = [Float](repeating: 0, count: fftSize)
        dft.transform(inputReal: windowed, inputImaginary: [Float](repeating: 0, count: fftSize),
                      outputReal: &real, outputImaginary: &imaginary)
        let half = fftSize / 2
        var mags = [Float](repeating: 0, count: half)
        for i in 0..<half {
            let re = real[i], im = imaginary[i]
            mags[i] = (re * re + im * im).squareRoot() * 4 / Float(fftSize)
        }
        return mags
    }

    /// Log-spaced bands, 0…1 over a 72 dB range.
    private func spectrum(of samples: [Float], sampleRate: Double) -> [Float] {
        guard let mags = magnitudes(of: samples) else { return [] }
        let binWidth = Float(sampleRate) / Float(fftSize)
        let bands = SignalAnalysis.spectrumBands, range = SignalAnalysis.spectrumRange
        let lo = log2(range.lowerBound), hi = log2(range.upperBound)
        return (0..<bands).map { band in
            let f0 = pow(2, lo + (hi - lo) * Float(band) / Float(bands))
            let f1 = pow(2, lo + (hi - lo) * Float(band + 1) / Float(bands))
            let i0 = max(1, Int(f0 / binWidth)), i1 = min(mags.count - 1, max(i0, Int(f1 / binWidth)))
            let peak = mags[i0...i1].max() ?? 0
            return min(1, max(0, (Self.dB(peak) + 84) / 72))
        }
    }

    private func brightness(of samples: [Float], sampleRate: Double) -> Float {
        guard let mags = magnitudes(of: samples) else { return 0 }
        let binWidth = Float(sampleRate) / Float(fftSize)
        var weighted: Float = 0, total: Float = 0
        for (i, m) in mags.enumerated() where i > 0 {
            let power = m * m
            weighted += Float(i) * binWidth * power
            total += power
        }
        return total > 0 ? weighted / total : 0
    }

    // MARK: Helpers

    private static func rms(_ x: [Float]) -> Float { vDSP.rootMeanSquare(x) }
    private static func peak(_ x: [Float]) -> Float { vDSP.maximumMagnitude(x) }
    private static func dB(_ x: Float) -> Float { 20 * log10(max(x, 1e-6)) }

    /// Shifts samples left by `lag` (keeping the count), padding the end with the last value.
    private static func shift(_ x: [Float], by lag: Int) -> [Float] {
        guard lag > 0, lag < x.count / 2 else { return x }
        return Array(x.dropFirst(lag)) + Array(repeating: x.last ?? 0, count: lag)
    }

    /// Loudness swing (loud minus quiet, ignoring silence) and the quiet floor, both in dB.
    private static func dynamics(of envelope: [Float]) -> (swing: Float, floor: Float) {
        let levels = envelope.map(dB).sorted()
        guard levels.count > 20 else { return (0, -120) }
        let loud = levels[Int(Float(levels.count) * 0.95)]
        let quiet = levels[Int(Float(levels.count) * 0.15)]
        let audibleQuiet = max(quiet, loud - 60)
        return (loud - audibleQuiet, quiet)
    }
}
