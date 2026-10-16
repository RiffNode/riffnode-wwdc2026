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
        case .direct:
            break
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

final class AmpProcessor: @unchecked Sendable {

    // Settings packed into atomics: knobs as Float bits, model and cabinet as indices
    private let gainBits = Atomic<UInt32>(Float(0.35).bitPattern)
    private let bassBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private let midBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private let trebleBits = Atomic<UInt32>(Float(0.55).bitPattern)
    private let masterBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private let modelIndex = Atomic<Int>(0)
    private let cabinetIndex = Atomic<Int>(2)
    private let generation = Atomic<Int>(1)

    /// Called on the main thread.
    func apply(_ s: AmpSettings) {
        gainBits.store(s.gain.bitPattern, ordering: .relaxed)
        bassBits.store(s.bass.bitPattern, ordering: .relaxed)
        midBits.store(s.mid.bitPattern, ordering: .relaxed)
        trebleBits.store(s.treble.bitPattern, ordering: .relaxed)
        masterBits.store(s.master.bitPattern, ordering: .relaxed)
        modelIndex.store(AmpModel.allCases.firstIndex(of: s.model) ?? 0, ordering: .relaxed)
        cabinetIndex.store(CabinetType.allCases.firstIndex(of: s.cabinet) ?? 0, ordering: .relaxed)
        generation.add(1, ordering: .releasing)
    }

    // Render state – touched only on the audio thread
    private static let maxStages = 9
    private var filters = [Biquad](repeating: Biquad(), count: maxStages)
    private var stageCount = 0
    private var seenGeneration = 0
    private var sampleRate: Float = 48_000
    private var preGain: Float = 1
    private var postGain: Float = 1
    private var masterDrive: Float = 1
    private var inputHighPass: (Float, Float) = (0, 0)
    private var tightCoefficient: Float = 0

    func prepare(sampleRate: Float) {
        self.sampleRate = sampleRate
        filters = [Biquad](repeating: Biquad(), count: Self.maxStages)
        inputHighPass = (0, 0)
        seenGeneration = 0
    }

    private func refreshIfNeeded() {
        let current = generation.load(ordering: .acquiring)
        guard current != seenGeneration else { return }
        seenGeneration = current

        let settings = AmpSettings(
            isEnabled: true,
            model: AmpModel.allCases[modelIndex.load(ordering: .relaxed)],
            cabinet: CabinetType.allCases[cabinetIndex.load(ordering: .relaxed)],
            gain: Float(bitPattern: gainBits.load(ordering: .relaxed)),
            bass: Float(bitPattern: bassBits.load(ordering: .relaxed)),
            mid: Float(bitPattern: midBits.load(ordering: .relaxed)),
            treble: Float(bitPattern: trebleBits.load(ordering: .relaxed)),
            master: Float(bitPattern: masterBits.load(ordering: .relaxed)))

        let stages = AmpDesign.stages(for: settings)
        stageCount = min(stages.count, Self.maxStages)
        for i in 0..<stageCount {
            let s = stages[i]
            filters[i].set(s.kind, frequency: s.frequency, q: s.q, gainDB: s.gainDB, sampleRate: sampleRate)
        }
        preGain = pow(10, AmpDesign.preampGainDB(model: settings.model, gain: settings.gain) / 20)
        // High-gain amps cut lows before the tubes so palm mutes stay tight
        let tightHz: Float = settings.model == .lead ? 160 : (settings.model == .crunch ? 100 : 40)
        tightCoefficient = exp(-2 * Float.pi * tightHz / sampleRate)
        masterDrive = 0.6 + settings.master * 2.4
        // Keep loudness roughly steady across gain settings
        postGain = (0.25 + settings.master * 0.5) / max(0.6, min(1.6, 0.9 + settings.gain * 0.4))
    }

    func process(_ data: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        if channel == 0 { refreshIfNeeded() }
        var low = channel == 0 ? inputHighPass.0 : inputHighPass.1
        for i in 0..<frames {
            let x = data[i]
            low = (1 - tightCoefficient) * x + tightCoefficient * low
            // Preamp: asymmetric tube-style soft clip (the negative half saturates later)
            let driven = (x - low) * preGain
            let pre = driven >= 0 ? tanh(driven) : tanh(driven * 0.8) / 0.8
            // Tone stack + cabinet
            var y = pre
            for s in 0..<stageCount { y = filters[s].process(y, channel: channel) }
            // Power amp: soft saturation as the master goes up
            y = tanh(y * masterDrive) / masterDrive * 1.6
            data[i] = y * postGain
        }
        if channel == 0 { inputHighPass.0 = low } else { inputHighPass.1 = low }
    }
}
