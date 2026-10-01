import Foundation

// MARK: - Jam Track Synthesizer
// A built-in backing groove – drums and bass over Em · C · G · D at 112 BPM – rendered on
// device, so there is always something to play along with, even offline with no music files.
// It shares the demo riff's key and tempo, so the two lock together.

enum JamTrackSynthesizer {

    static let tempo: Double = 112
    static let progression = ["Em", "C", "G", "D"]
    static let title = "RiffNode Groove"
    static var subtitle: String { progression.joined(separator: " · ") + " · \(Int(tempo)) BPM" }

    /// MIDI roots for the bass, one chord per bar (E2, C2, G2, D2).
    private static let bassRoots = [40, 36, 43, 38]

    /// Renders one four-bar loop as mono samples.
    static func render(sampleRate: Double) -> [Float] {
        let eighth = 60 / tempo / 2
        let barFrames = Int(8 * eighth * sampleRate)
        var output = [Float](repeating: 0, count: barFrames * bassRoots.count)
        var noise = NoiseSource(seed: 0x4A41_4D21)  // "JAM!"

        for (bar, root) in bassRoots.enumerated() {
            for step in 0..<8 {
                let start = bar * barFrames + Int(Double(step) * eighth * sampleRate)

                // Drums: kick on 1 and 3 (plus a push into 3), snare on 2 and 4, hats on every eighth
                if [0, 3, 4].contains(step) {
                    kick(into: &output, at: start, sampleRate: sampleRate, gain: step == 3 ? 0.6 : 0.95)
                }
                if step == 2 || step == 6 {
                    snare(into: &output, at: start, sampleRate: sampleRate, noise: &noise)
                }
                hiHat(into: &output, at: start, sampleRate: sampleRate, noise: &noise,
                      gain: step.isMultiple(of: 2) ? 0.16 : 0.09)

                // Bass: driving eighth notes on the chord root, octave jump on the last eighth
                let note = step == 7 ? root + 12 : root
                bass(into: &output, at: start, frames: Int(eighth * sampleRate * 0.9),
                     frequency: 440 * pow(2, Double(note - 69) / 12), sampleRate: sampleRate)
            }
        }

        let peak = output.reduce(0) { max($0, abs($1)) }
        if peak > 0 {
            let gain = 0.55 / peak
            for index in output.indices { output[index] *= gain }
        }
        return output
    }

    // MARK: - Voices

    /// Sine with a falling pitch: the classic synthesized kick drum.
    private static func kick(into output: inout [Float], at start: Int, sampleRate: Double, gain: Float) {
        let length = Int(0.28 * sampleRate)
        var phase = 0.0
        for i in 0..<length where start + i < output.count {
            let t = Double(i) / sampleRate
            let frequency = 50 + 90 * exp(-t * 30)
            phase += 2 * .pi * frequency / sampleRate
            output[start + i] += Float(sin(phase) * exp(-t * 9)) * gain
        }
    }

    /// A noise burst plus a short tone for the drum body.
    private static func snare(into output: inout [Float], at start: Int, sampleRate: Double, noise: inout NoiseSource) {
        let length = Int(0.18 * sampleRate)
        for i in 0..<length where start + i < output.count {
            let t = Double(i) / sampleRate
            let body = sin(2 * .pi * 185 * t) * exp(-t * 30)
            let rattle = Double(noise.next()) * exp(-t * 18)
            output[start + i] += Float(body * 0.35 + rattle * 0.45)
        }
    }

    /// High-passed noise with a very short decay.
    private static func hiHat(into output: inout [Float], at start: Int, sampleRate: Double,
                              noise: inout NoiseSource, gain: Float) {
        let length = Int(0.05 * sampleRate)
        var previous: Float = 0
        for i in 0..<length where start + i < output.count {
            let sample = noise.next()
            let highPassed = sample - previous  // first difference keeps only the fizz
            previous = sample
            let envelope = Float(exp(-Double(i) / sampleRate * 70))
            output[start + i] += highPassed * envelope * gain
        }
    }

    /// A round, plucked bass: fundamental plus a little second harmonic.
    private static func bass(into output: inout [Float], at start: Int, frames: Int,
                             frequency: Double, sampleRate: Double) {
        let release = Int(0.01 * sampleRate)
        for i in 0..<frames where start + i < output.count {
            let t = Double(i) / sampleRate
            let tone = sin(2 * .pi * frequency * t) + 0.35 * sin(4 * .pi * frequency * t)
            var envelope = exp(-t * 4)
            let remaining = frames - i
            if remaining < release { envelope *= Double(remaining) / Double(release) }
            output[start + i] += Float(tone * envelope * 0.55)
        }
    }
}

/// Deterministic white noise so the groove sounds identical every time.
private struct NoiseSource {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
    }
}
