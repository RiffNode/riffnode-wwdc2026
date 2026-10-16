import Foundation

// MARK: - Demo Riff Synthesizer
// Renders a short, original funk "cutting" guitar part – the bright, 16th-note chord stabs of
// J-pop and city pop – with Karplus–Strong plucked-string synthesis. It lets anyone hear the
// pedalboard without a guitar or audio interface: the riff is generated on device (no bundled
// audio, works offline) and is fed into the effects chain exactly where a real guitar would be.
//
// Four bars – Em9 · Cmaj7 · Gmaj7 · Dadd9 – over the same chords and tempo as the built-in
// groove (Em · C · G · D, 112 BPM), so the two lock together.

enum DemoRiffSynthesizer {

    static let tempo: Double = 112

    /// What happens on one 16th note.
    private enum Stroke {
        case down, up       // a chord stab, strummed low→high or high→low
        case ghost          // a muted "chk" – fretting hand resting on the strings
        case note(Int)      // a single note (MIDI)
        case rest

        var isUp: Bool { if case .up = self { true } else { false } }
    }

    /// Chord voicings in the middle of the neck, low string to high (MIDI).
    private static let voicings: [[Int]] = [
        [52, 55, 62, 66],   // Em9   x-7-5-7-7-x
        [48, 55, 59, 64],   // Cmaj7 x-3-5-4-5-x
        [55, 62, 66, 71],   // Gmaj7 x-x-5-7-7-7
        [50, 57, 64, 66],   // Dadd9 x-5-7-9-7-x
    ]

    /// One bar of cutting: stabs on the accents, ghost strums in between.
    ///                         1    e      &      a     2      e     &      a
    private static let groove: [Stroke] = [.down, .ghost, .up, .down, .ghost, .up, .ghost, .up,
    ///                         3    e      &      a     4      e     &      a
                                           .down, .ghost, .ghost, .up, .ghost, .up, .down, .rest]

    /// The last bar ends on a little E minor pentatonic run instead.
    private static let fill: [Stroke] = [.down, .ghost, .up, .down, .ghost, .up, .ghost, .rest,
                                         .note(62), .note(64), .note(67), .note(64),
                                         .note(69), .rest, .note(71), .rest]

    /// Renders one four-bar loop as mono samples, normalised to a guitar-like level.
    static func render(sampleRate: Double) -> [Float] {
        let sixteenth = 60 / tempo / 4
        let barFrames = Int(16 * sixteenth * sampleRate)
        var output = [Float](repeating: 0, count: barFrames * voicings.count)
        var random = SeededRandom(seed: 0x4355_5421)  // "CUT!" – same riff every time

        for (bar, voicing) in voicings.enumerated() {
            let strokes = bar == voicings.count - 1 ? fill : groove
            for (step, stroke) in strokes.enumerated() {
                let start = bar * barFrames + Int(Double(step) * sixteenth * sampleRate)
                let stab = Int(sixteenth * 1.6 * sampleRate)   // staccato, but rings past its 16th
                switch stroke {
                case .down, .up:
                    let strings = stroke.isUp ? Array(voicing.reversed()) : voicing
                    for (index, note) in strings.enumerated() {
                        pluck(into: &output, note: note, start: start + index * Int(0.007 * sampleRate),
                              frames: stab, brightness: stroke.isUp ? 0.55 : 0.7,
                              gain: stroke.isUp ? 0.7 : 1, muted: false, sampleRate: sampleRate, random: &random)
                    }
                case .ghost:
                    for (index, note) in voicing.enumerated() {
                        pluck(into: &output, note: note, start: start + index * Int(0.004 * sampleRate),
                              frames: Int(0.045 * sampleRate), brightness: 0.9,
                              gain: 0.35, muted: true, sampleRate: sampleRate, random: &random)
                    }
                case .note(let note):
                    pluck(into: &output, note: note, start: start, frames: Int(sixteenth * 1.8 * sampleRate),
                          brightness: 0.6, gain: 1.1, muted: false, sampleRate: sampleRate, random: &random)
                case .rest:
                    break
                }
            }
        }

        // Body: take off rumble below ~90 Hz and fizz above ~7 kHz, like a guitar through a DI
        highPass(&output, cutoff: 90, sampleRate: sampleRate)
        lowPass(&output, cutoff: 7_000, sampleRate: sampleRate)

        let peak = output.reduce(0) { max($0, abs($1)) }
        if peak > 0 {
            let gain = 0.5 / peak
            for i in output.indices { output[i] *= gain }
        }
        return output
    }

    // MARK: - Karplus–Strong

    /// A burst of filtered noise circulating through a tuned, damped delay line.
    /// The fractional part of the period is handled by a first-order all-pass, so notes are
    /// in tune (plain Karplus–Strong rounds the period and drifts flat by up to ~30 cents).
    private static func pluck(
        into output: inout [Float], note: Int, start: Int, frames: Int,
        brightness: Float, gain: Float, muted: Bool, sampleRate: Double, random: inout SeededRandom
    ) {
        let frequency = 440 * pow(2, Double(note - 69) / 12)
        // The averaging loss filter adds half a sample of delay
        let exactPeriod = sampleRate / frequency - 0.5
        let period = max(2, Int(exactPeriod))
        let fraction = Float(exactPeriod - Double(period))
        let allpass = (1 - fraction) / (1 + fraction)

        // Pick: noise smoothed by a one-pole low-pass – a softer pick sounds rounder
        var delayLine = [Float](repeating: 0, count: period)
        var smoothed: Float = 0
        for i in 0..<period {
            smoothed += brightness * (random.nextSignedUnit() - smoothed)
            delayLine[i] = smoothed
        }
        let mean = delayLine.reduce(0, +) / Float(period)
        for i in 0..<period { delayLine[i] -= mean }

        let decay: Float = muted ? 0.93 : 0.997
        let releaseFrames = Int((muted ? 0.012 : 0.03) * sampleRate)
        let end = min(output.count, start + frames)
        guard start >= 0, start < end else { return }

        var index = 0
        var allpassIn: Float = 0, allpassOut: Float = 0
        for frame in start..<end {
            let current = delayLine[index]
            let next = delayLine[(index + 1) % period]
            let averaged = decay * 0.5 * (current + next)
            let tuned = allpass * averaged + allpassIn - allpass * allpassOut
            allpassIn = averaged
            allpassOut = tuned
            delayLine[index] = tuned
            index = (index + 1) % period

            // The fretting hand lifts at the end of the note: a quick fade, no click
            let remaining = end - frame
            let release = remaining < releaseFrames ? Float(remaining) / Float(releaseFrames) : 1
            output[frame] += current * release * gain
        }
    }

    // MARK: - Filters

    private static func highPass(_ x: inout [Float], cutoff: Double, sampleRate: Double) {
        let r = Float(exp(-2 * Double.pi * cutoff / sampleRate))
        var previousIn: Float = 0, previousOut: Float = 0
        for i in x.indices {
            let out = r * (previousOut + x[i] - previousIn)
            previousIn = x[i]
            previousOut = out
            x[i] = out
        }
    }

    private static func lowPass(_ x: inout [Float], cutoff: Double, sampleRate: Double) {
        let a = Float(1 - exp(-2 * Double.pi * cutoff / sampleRate))
        var state: Float = 0
        for i in x.indices {
            state += a * (x[i] - state)
            x[i] = state
        }
    }
}

// MARK: - Seeded Random

/// Small deterministic generator so the demo riff sounds identical on every run.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextSignedUnit() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
    }
}
