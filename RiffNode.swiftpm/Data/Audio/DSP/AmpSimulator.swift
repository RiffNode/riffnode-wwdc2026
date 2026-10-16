import Accelerate
import Foundation
import Synchronization

// MARK: - Amp Simulator
// The amplifier and speaker cabinet at the end of the chain – what turns a pedal's raw,
// fizzy output into a guitar tone. Four stages, in the order a real amp has them:
//
//  1. Preamp – tube-style gain stage: asymmetric soft clipping, more gain per voicing
//  2. Tone stack – bass shelf, mid peak/scoop, treble shelf (the knobs on the panel)
//  3. Power amp – gentle saturation driven by the master volume
//  4. Cabinet – the speaker's response: no deep lows, a low resonance "thump", a presence
//     peak around 2–3 kHz and a steep roll-off above ~5 kHz, which removes the fizz
//
// Runs on the audio thread: no allocation, no locks. Settings cross threads through atomics;
// filter coefficients are recomputed on the audio thread only when a setting changes.

/// One biquad section (RBJ cookbook), transposed direct form II, up to two channels.
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1 = (Float(0), Float(0))
    var z2 = (Float(0), Float(0))

    mutating func process(_ x: Float, channel: Int) -> Float {
        if channel == 0 {
            let y = b0 * x + z1.0
            z1.0 = b1 * x - a1 * y + z2.0
            z2.0 = b2 * x - a2 * y
            return y
        } else {
            let y = b0 * x + z1.1
            z1.1 = b1 * x - a1 * y + z2.1
            z2.1 = b2 * x - a2 * y
            return y
        }
    }

    enum Kind { case lowPass, highPass, peak, lowShelf, highShelf }

    /// Sets the coefficients, keeping the filter's memory (no clicks on knob turns).
    mutating func set(_ kind: Kind, frequency: Float, q: Float = 0.707, gainDB: Float = 0, sampleRate: Float) {
        let c = Self.coefficients(kind, frequency: frequency, q: q, gainDB: gainDB, sampleRate: sampleRate)
        (b0, b1, b2, a1, a2) = c
    }

    static func coefficients(_ kind: Kind, frequency: Float, q: Float, gainDB: Float, sampleRate: Float)
        -> (Float, Float, Float, Float, Float) {
        let f = min(max(frequency, 10), sampleRate * 0.45)
        let w = 2 * Float.pi * f / sampleRate
        let cosw = cos(w), sinw = sin(w)
        let alpha = sinw / (2 * q)
        let a = pow(10, gainDB / 40)
        var b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float
        switch kind {
        case .lowPass:
            b0 = (1 - cosw) / 2; b1 = 1 - cosw; b2 = (1 - cosw) / 2
            a0 = 1 + alpha; a1 = -2 * cosw; a2 = 1 - alpha
        case .highPass:
            b0 = (1 + cosw) / 2; b1 = -(1 + cosw); b2 = (1 + cosw) / 2
            a0 = 1 + alpha; a1 = -2 * cosw; a2 = 1 - alpha
        case .peak:
            b0 = 1 + alpha * a; b1 = -2 * cosw; b2 = 1 - alpha * a
            a0 = 1 + alpha / a; a1 = -2 * cosw; a2 = 1 - alpha / a
        case .lowShelf:
            let s = 2 * a.squareRoot() * alpha
            b0 = a * ((a + 1) - (a - 1) * cosw + s)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosw)
            b2 = a * ((a + 1) - (a - 1) * cosw - s)
            a0 = (a + 1) + (a - 1) * cosw + s
            a1 = -2 * ((a - 1) + (a + 1) * cosw)
            a2 = (a + 1) + (a - 1) * cosw - s
        case .highShelf:
            let s = 2 * a.squareRoot() * alpha
            b0 = a * ((a + 1) + (a - 1) * cosw + s)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosw)
            b2 = a * ((a + 1) + (a - 1) * cosw - s)
            a0 = (a + 1) - (a - 1) * cosw + s
            a1 = 2 * ((a - 1) - (a + 1) * cosw)
            a2 = (a + 1) - (a - 1) * cosw - s
        }
        return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }

    /// |H(f)| in dB, for drawing the response curve.
    static func magnitudeDB(_ c: (Float, Float, Float, Float, Float), at frequency: Float, sampleRate: Float) -> Float {
        let w = 2 * Double.pi * Double(frequency) / Double(sampleRate)
        let (b0, b1, b2, a1, a2) = (Double(c.0), Double(c.1), Double(c.2), Double(c.3), Double(c.4))
        let cos1 = cos(w), sin1 = sin(w), cos2 = cos(2 * w), sin2 = sin(2 * w)
        let numRe = b0 + b1 * cos1 + b2 * cos2, numIm = -(b1 * sin1 + b2 * sin2)
        let denRe = 1 + a1 * cos1 + a2 * cos2, denIm = -(a1 * sin1 + a2 * sin2)
        let num = numRe * numRe + numIm * numIm, den = denRe * denRe + denIm * denIm
        return Float(10 * log10(max(num / max(den, 1e-20), 1e-20)))
    }
}

// MARK: - Amp Design

/// The filter recipe for a given setting – shared by the audio path and the response plot.
enum AmpDesign {

    struct Stage {
        let kind: Biquad.Kind
        let frequency: Float
        let q: Float
        let gainDB: Float
    }

    /// Preamp gain range in dB for each voicing.
    static func preampGainDB(model: AmpModel, gain: Float) -> Float {
        switch model {
        case .clean: 0 + gain * 18
        case .crunch: 10 + gain * 26
        case .lead: 20 + gain * 30
        }
    }

    /// Tone stack + voicing + cabinet, in signal order after the preamp.
    static func stages(for s: AmpSettings) -> [Stage] {
        var stages: [Stage] = []
        // Tone stack: ±12 dB, centred on each voicing's character
        let midCentre: Float = s.model == .clean ? 500 : (s.model == .crunch ? 800 : 650)
        let midBias: Float = s.model == .clean ? -3 : (s.model == .crunch ? 2 : -2)   // clean scoop, British push
        stages.append(Stage(kind: .lowShelf, frequency: 120, q: 0.7, gainDB: (s.bass - 0.5) * 24))
        stages.append(Stage(kind: .peak, frequency: midCentre, q: 0.8, gainDB: (s.mid - 0.5) * 20 + midBias))
        stages.append(Stage(kind: .highShelf, frequency: 3_200, q: 0.7, gainDB: (s.treble - 0.5) * 24))

        switch s.cabinet {
        case .direct, .impulse:
            break   // no speaker model (an IR, when loaded, is convolved separately)
        case .oneByTwelve:
            stages.append(Stage(kind: .highPass, frequency: 95, q: 0.7, gainDB: 0))
            stages.append(Stage(kind: .peak, frequency: 140, q: 1.2, gainDB: 2))
            stages.append(Stage(kind: .peak, frequency: 2_200, q: 1.4, gainDB: 3))
            stages.append(Stage(kind: .lowPass, frequency: 6_000, q: 0.8, gainDB: 0))
            stages.append(Stage(kind: .lowPass, frequency: 7_500, q: 0.6, gainDB: 0))
        case .twoByTwelve:
            stages.append(Stage(kind: .highPass, frequency: 80, q: 0.8, gainDB: 0))
            stages.append(Stage(kind: .peak, frequency: 120, q: 1.2, gainDB: 3))
            stages.append(Stage(kind: .peak, frequency: 2_500, q: 1.5, gainDB: 3.5))
            stages.append(Stage(kind: .lowPass, frequency: 5_200, q: 0.8, gainDB: 0))
            stages.append(Stage(kind: .lowPass, frequency: 6_500, q: 0.6, gainDB: 0))
        case .fourByTwelve:
            stages.append(Stage(kind: .highPass, frequency: 70, q: 0.9, gainDB: 0))
            stages.append(Stage(kind: .peak, frequency: 105, q: 1.4, gainDB: 5))
            stages.append(Stage(kind: .peak, frequency: 400, q: 1.0, gainDB: -3))
            stages.append(Stage(kind: .peak, frequency: 2_800, q: 1.6, gainDB: 4))
            stages.append(Stage(kind: .lowPass, frequency: 4_600, q: 0.8, gainDB: 0))
            stages.append(Stage(kind: .lowPass, frequency: 5_800, q: 0.6, gainDB: 0))
        }
        return stages
    }

    /// The amp's frequency response (tone stack + cabinet), in dB at each frequency.
    static func response(for settings: AmpSettings, at frequencies: [Float], sampleRate: Float = 48_000) -> [Float] {
        let coefficients = stages(for: settings).map {
            Biquad.coefficients($0.kind, frequency: $0.frequency, q: $0.q, gainDB: $0.gainDB, sampleRate: sampleRate)
        }
        return frequencies.map { f in coefficients.reduce(0) { $0 + Biquad.magnitudeDB($1, at: f, sampleRate: sampleRate) } }
    }
}

// MARK: - Amp Processor (audio thread)

/// Everything the audio thread needs, computed on the main thread and handed over through
/// two pre-allocated banks and an atomic index – the audio thread never allocates or locks.
final class AmpProcessor: @unchecked Sendable {

    static let maxStages = 9
    static let maxIRLength = 2048
    // Bank layout: [stageCount, preGain, tightCoefficient, masterDrive, postGain, useIR, b0 b1 b2 a1 a2 × maxStages]
    private static let header = 6
    private static let bankSize = header + maxStages * 5

    private let banks = UnsafeMutablePointer<Float>.allocate(capacity: 2 * bankSize)
    private let activeBank = Atomic<Int>(0)
    private let generation = Atomic<Int>(0)

    // Impulse response: two banks of taps (stored reversed for convolution), atomic switch
    private let irBanks = UnsafeMutablePointer<Float>.allocate(capacity: 2 * maxIRLength)
    private let irActive = Atomic<Int>(0)
    private let irLength = Atomic<Int>(0)
    private var irWriteBank = 1

    private var sampleRate: Float = 48_000

    init() {
        banks.initialize(repeating: 0, count: 2 * Self.bankSize)
        irBanks.initialize(repeating: 0, count: 2 * Self.maxIRLength)
        history.initialize(repeating: 0, count: 2 * Self.historyLength)
        scratch.initialize(repeating: 0, count: 4096)
        apply(AmpSettings())
    }

    deinit {
        banks.deallocate()
        irBanks.deallocate()
        history.deallocate()
        scratch.deallocate()
    }

    // MARK: Main thread

    /// The engine's sample rate, so coefficients are designed for it.
    func setSampleRate(_ rate: Float) { sampleRate = rate }

    func apply(_ s: AmpSettings) {
        let bank = 1 - activeBank.load(ordering: .acquiring)
        let base = banks + bank * Self.bankSize
        let useIR = s.cabinet == .impulse && irLength.load(ordering: .relaxed) > 0
        var designed = s
        if s.cabinet == .impulse { designed.cabinet = .direct }   // the IR replaces the filter model
        let stages = AmpDesign.stages(for: designed).prefix(Self.maxStages)

        base[0] = Float(stages.count)
        base[1] = pow(10, AmpDesign.preampGainDB(model: s.model, gain: s.gain) / 20)
        // High-gain amps cut lows before the tubes so palm mutes stay tight
        let tightHz: Float = s.model == .lead ? 160 : (s.model == .crunch ? 100 : 40)
        base[2] = exp(-2 * Float.pi * tightHz / sampleRate)
        base[3] = 0.6 + s.master * 2.4
        // Keep loudness roughly steady across gain settings
        base[4] = (0.25 + s.master * 0.5) / max(0.6, min(1.6, 0.9 + s.gain * 0.4))
        base[5] = useIR ? 1 : 0
        for (i, stage) in stages.enumerated() {
            let c = Biquad.coefficients(stage.kind, frequency: stage.frequency, q: stage.q, gainDB: stage.gainDB, sampleRate: sampleRate)
            let o = Self.header + i * 5
            (base[o], base[o + 1], base[o + 2], base[o + 3], base[o + 4]) = c
        }
        activeBank.store(bank, ordering: .releasing)
        generation.add(1, ordering: .releasing)
    }

    /// Scales an impulse response so its loudest frequency (40 Hz – 8 kHz) has unity gain,
    /// so swapping cabinets never makes the amp jump in level or clip. Main thread.
    static func normalizedIR(_ taps: [Float], sampleRate: Float) -> [Float] {
        var peak: Double = 0
        for step in 0..<48 {
            let f = 40 * pow(200.0, Double(step) / 47)   // 40 Hz … 8 kHz
            let w = 2 * Double.pi * f / Double(sampleRate)
            var re = 0.0, im = 0.0
            for (n, h) in taps.enumerated() { re += Double(h) * cos(w * Double(n)); im -= Double(h) * sin(w * Double(n)) }
            peak = max(peak, (re * re + im * im).squareRoot())
        }
        guard peak > 0 else { return taps }
        return taps.map { $0 / Float(peak) }
    }

    /// Installs an impulse response (already at the engine's sample rate, normalised).
    func loadIR(_ taps: [Float]) {
        let count = min(taps.count, Self.maxIRLength)
        let base = irBanks + irWriteBank * Self.maxIRLength
        // Stored reversed so a forward correlation computes the convolution
        for i in 0..<count { base[i] = taps[count - 1 - i] }
        irLength.store(count, ordering: .relaxed)
        irActive.store(irWriteBank, ordering: .releasing)
        irWriteBank = 1 - irWriteBank
    }

    // MARK: Audio thread

    private var filters = [Biquad](repeating: Biquad(), count: maxStages)
    private var stageCount = 0
    private var seenGeneration = -1
    private var preGain: Float = 1, tightCoefficient: Float = 0, masterDrive: Float = 1, postGain: Float = 1
    private var useIR = false
    private var inputHighPass: (Float, Float) = (0, 0)

    /// Per-channel input history for the convolution: the last (maxIRLength − 1) samples, then the block.
    private static let historyLength = maxIRLength - 1 + 4096
    private let history = UnsafeMutablePointer<Float>.allocate(capacity: 2 * historyLength)
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 4096)

    func prepare(sampleRate: Float) {
        self.sampleRate = sampleRate
        inputHighPass = (0, 0)
        history.update(repeating: 0, count: 2 * Self.historyLength)
        seenGeneration = -1
    }

    private func refreshIfNeeded() {
        let current = generation.load(ordering: .acquiring)
        guard current != seenGeneration else { return }
        seenGeneration = current
        let base = banks + activeBank.load(ordering: .acquiring) * Self.bankSize
        stageCount = min(Int(base[0]), Self.maxStages)
        preGain = base[1]; tightCoefficient = base[2]; masterDrive = base[3]; postGain = base[4]
        useIR = base[5] > 0.5
        for i in 0..<stageCount {
            let o = Self.header + i * 5
            // Coefficients change; the filter's memory stays, so knob turns don't click
            filters[i].b0 = base[o]; filters[i].b1 = base[o + 1]; filters[i].b2 = base[o + 2]
            filters[i].a1 = base[o + 3]; filters[i].a2 = base[o + 4]
        }
    }

    func process(_ data: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        if channel == 0 { refreshIfNeeded() }
        let frames = min(frames, 4096)
        var low = channel == 0 ? inputHighPass.0 : inputHighPass.1
        for i in 0..<frames {
            let x = data[i]
            low = (1 - tightCoefficient) * x + tightCoefficient * low
            // Preamp: asymmetric tube-style soft clip (the negative half saturates later)
            let driven = (x - low) * preGain
            let pre = driven >= 0 ? tanh(driven) : tanh(driven * 0.8) / 0.8
            // Tone stack (+ cabinet model when no IR)
            var y = pre
            for s in 0..<stageCount { y = filters[s].process(y, channel: channel) }
            // Power amp: soft saturation as the master goes up
            y = tanh(y * masterDrive) / masterDrive * 1.6
            data[i] = y * postGain
        }
        if channel == 0 { inputHighPass.0 = low } else { inputHighPass.1 = low }

        if useIR { convolve(data, frames: frames, channel: channel) }
    }

    /// Direct-form FIR with the loaded impulse response (a real speaker + microphone).
    private func convolve(_ data: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        let taps = irLength.load(ordering: .relaxed)
        guard taps > 0 else { return }
        let ir = irBanks + irActive.load(ordering: .acquiring) * Self.maxIRLength
        let h = history + channel * Self.historyLength
        let keep = Self.maxIRLength - 1
        // history = [last keep samples][this block]
        (h + keep).update(from: data, count: frames)
        // y[n] = Σ x[n + keep − (taps−1) + k] · ir_reversed[k] – vectorised by Accelerate
        let start = h + keep - (taps - 1)
        vDSP_conv(start, 1, ir, 1, scratch, 1, vDSP_Length(frames), vDSP_Length(taps))
        data.update(from: scratch, count: frames)
        // Slide: the newest `keep` samples become the history for the next block
        h.update(from: h + frames, count: keep)
    }
}
