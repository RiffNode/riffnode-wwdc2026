import Foundation

// MARK: - Demo Riff Synthesizer
// Renders a short, original guitar part in the style of Japanese indie rock: a bright, clean
// arpeggio where open B and E strings ring on through every chord, over the IV–V–iii–vi
// "royal road" progression (王道進行) beloved in J-pop, with a quick melodic run to close.
// Karplus–Strong plucked-string synthesis renders it on device (no bundled audio, works
// offline), and it enters the effects chain exactly where a real guitar would.
//
// Four bars – Cmaj7 · D6/9 · Bm11 · Em9 at 150 BPM – over the same chords and tempo as the
// built-in groove, so the two lock together.

enum DemoRiffSynthesizer {

    static let tempo: Double = 150

    /// Chord voicings, low string to high (MIDI). The top two notes are the open B (59)
    /// and high E (64) strings where they fit – the ringing shimmer of the style.
    private static let voicings: [[Int]] = [
        [48, 55, 59, 64],   // Cmaj7  x-3-5-4-0-0
        [50, 57, 59, 64],   // D6/9   x-5-7-4-0-0
        [47, 54, 57, 64],   // Bm11   x-2-4-2-0-0 (A on the G string)
        [40, 47, 55, 59, 66],   // Em9 – full open E shape with F♯ on top
    ]

    /// Eighth-note picking order, as indices into the voicing: bass, then up and down the
    /// upper strings so the top notes ring together.
    private static let pattern = [0, 2, 3, 1, 3, 2, 3, 1]

    /// The last half of the final bar becomes a quick run up the E minor scale (16ths).
    private static let run = [66, 67, 71, 74, 76, 74, 71, 74]

    /// Renders one four-bar loop as mono samples, normalised to a guitar-like level.
    static func render(sampleRate: Double) -> [Float] {
        let eighth = 60 / tempo / 2
        let barFrames = Int(8 * eighth * sampleRate)
        var output = [Float](repeating: 0, count: barFrames * voicings.count)
        var random = SeededRandom(seed: 0x594F_5255)  // same riff every time

        for (bar, voicing) in voicings.enumerated() {
            let isLastBar = bar == voicings.count - 1
            for (step, index) in pattern.enumerated() {
                if isLastBar && step >= 4 { break }   // the run takes over
                let note = voicing[min(index, voicing.count - 1)]
                let start = bar * barFrames + Int(Double(step) * eighth * sampleRate)
                let isBass = index == 0
                // Notes are left to ring for a bar and a half: the arpeggio blooms into a chord
                pluck(into: &output, note: note, start: start,
                      frames: Int(eighth * (isBass ? 8 : 6) * sampleRate),
                      brightness: isBass ? 0.5 : 0.75, gain: step == 0 ? 1.1 : (step.isMultiple(of: 2) ? 0.9 : 0.75),
                      muted: false, sampleRate: sampleRate, random: &random)
            }
            if isLastBar {
                let sixteenth = eighth / 2
                for (step, note) in run.enumerated() {
                    let start = bar * barFrames + Int((4 * eighth + Double(step) * sixteenth) * sampleRate)
                    pluck(into: &output, note: note, start: start,
                          frames: Int(sixteenth * (step == run.count - 1 ? 4 : 2) * sampleRate),
                          brightness: 0.7, gain: 0.95, muted: false, sampleRate: sampleRate, random: &random)
                }
            }
        }

        // Body: take off rumble below ~90 Hz and fizz above ~8 kHz, like a clean guitar through a DI
        highPass(&output, cutoff: 90, sampleRate: sampleRate)
        lowPass(&output, cutoff: 8_000, sampleRate: sampleRate)

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

        let decay: Float = muted ? 0.93 : 0.9985
        let releaseFrames = Int((muted ? 0.012 : 0.06) * sampleRate)
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
