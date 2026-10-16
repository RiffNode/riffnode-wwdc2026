import Accelerate
import Foundation
import Observation

// MARK: - Signal Lab Model
// Turns the raw before/after captures of one pedal into things you can see and read:
// a few cycles of the waveform, the volume over the last seconds, the spectrum, and a
// handful of measurements (peakiness, loudness swing, brightness) that name the change.

@Observable
@MainActor
final class SignalLabModel {

    struct Measurements: Equatable {
        /// Loudness, dBFS
        var levelBefore: Float = -120
        var levelAfter: Float = -120
        /// Peak-to-RMS ratio in dB. Clipping and compression lower it.
        var crestBefore: Float = 0
        var crestAfter: Float = 0
        /// Loud-to-quiet range of the volume envelope, dB
        var swingBefore: Float = 0
        var swingAfter: Float = 0
        /// The quietest moments (gaps between notes), dBFS. Echoes and reverb raise it.
        var floorBefore: Float = -120
        var floorAfter: Float = -120
        /// Spectral centroid, Hz – "brightness"
        var brightnessBefore: Float = 0
        var brightnessAfter: Float = 0
    }

    private(set) var waveBefore: [Float] = []
    private(set) var waveAfter: [Float] = []
    private(set) var envelopeBefore: [Float] = []
    private(set) var envelopeAfter: [Float] = []
    private(set) var spectrumBefore: [Float] = []
    private(set) var spectrumAfter: [Float] = []
    private(set) var measurements = Measurements()
    /// True when nothing is coming into the pedal.
    private(set) var isSilent = true

    static let spectrumBands = 56
    static let spectrumRange: ClosedRange<Float> = 60...12_000
    static let waveLength = 512

    private let fftSize = SignalProbeStore.sampleCount
    @ObservationIgnored private lazy var dft = try? vDSP.DiscreteFourierTransform(
        count: fftSize, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    @ObservationIgnored private lazy var window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)

    // MARK: - Update

    func update(from snapshot: (before: SignalCapture, after: SignalCapture)) {
        let (before, after) = snapshot
        guard before.samples.count >= fftSize, after.samples.count >= fftSize else {
            isSilent = true
            return
        }

        let beforeRMS = Self.rms(before.samples)
        isSilent = beforeRMS < 0.0005
        guard !isSilent else { return }

        // Line the two captures up in time: the "after" tap may have run one buffer ahead.
        let lag = Int(clamping: after.endSampleTime - before.endSampleTime)
        let alignedAfter = Self.shift(after.samples, by: before.endSampleTime == 0 ? 0 : lag)

        // A rising zero crossing in the input, so the waveform stands still between frames
        let length = Self.waveLength
        let searchEnd = before.samples.count - length - 1
        var start = max(0, searchEnd - length)
        for i in stride(from: searchEnd, to: max(1, searchEnd - length), by: -1)
        where before.samples[i - 1] < 0 && before.samples[i] >= 0 {
            start = i
            break
        }
        waveBefore = Array(before.samples[start..<start + length])
        waveAfter = Array(alignedAfter[start..<start + length])

        envelopeBefore = before.envelope
        envelopeAfter = after.envelope
        spectrumBefore = spectrum(of: before.samples, sampleRate: before.sampleRate)
        spectrumAfter = spectrum(of: after.samples, sampleRate: after.sampleRate)

        var m = Measurements()
        m.levelBefore = Self.dB(beforeRMS)
        m.levelAfter = Self.dB(Self.rms(after.samples))
        m.crestBefore = Self.dB(Self.peak(before.samples)) - m.levelBefore
        m.crestAfter = Self.dB(Self.peak(after.samples)) - m.levelAfter
        (m.swingBefore, m.floorBefore) = Self.dynamics(of: before.envelope)
        (m.swingAfter, m.floorAfter) = Self.dynamics(of: after.envelope)
        m.brightnessBefore = brightness(of: before.samples, sampleRate: before.sampleRate)
        m.brightnessAfter = brightness(of: after.samples, sampleRate: after.sampleRate)
        // Smooth the readouts so they're legible
        measurements = Self.blend(measurements, m, amount: measurements.levelBefore < -100 ? 1 : 0.25)
    }

    func clear() {
        waveBefore = []; waveAfter = []
        envelopeBefore = []; envelopeAfter = []
        spectrumBefore = []; spectrumAfter = []
        measurements = Measurements()
        isSilent = true
    }

    // MARK: - Spectrum

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
        let lo = log2(Self.spectrumRange.lowerBound), hi = log2(Self.spectrumRange.upperBound)
        return (0..<Self.spectrumBands).map { band in
            let f0 = pow(2, lo + (hi - lo) * Float(band) / Float(Self.spectrumBands))
            let f1 = pow(2, lo + (hi - lo) * Float(band + 1) / Float(Self.spectrumBands))
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

    // MARK: - Helpers

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

    private static func blend(_ a: Measurements, _ b: Measurements, amount t: Float) -> Measurements {
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        return Measurements(
            levelBefore: mix(a.levelBefore, b.levelBefore), levelAfter: mix(a.levelAfter, b.levelAfter),
            crestBefore: mix(a.crestBefore, b.crestBefore), crestAfter: mix(a.crestAfter, b.crestAfter),
            swingBefore: mix(a.swingBefore, b.swingBefore), swingAfter: mix(a.swingAfter, b.swingAfter),
            floorBefore: mix(a.floorBefore, b.floorBefore), floorAfter: mix(a.floorAfter, b.floorAfter),
            brightnessBefore: mix(a.brightnessBefore, b.brightnessBefore),
            brightnessAfter: mix(a.brightnessAfter, b.brightnessAfter))
    }
}
