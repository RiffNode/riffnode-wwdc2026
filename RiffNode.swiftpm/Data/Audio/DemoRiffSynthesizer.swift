import Foundation

// MARK: - Demo Riff Synthesizer
// Renders a short, original power-chord riff with Karplus–Strong plucked-string synthesis.
// It lets anyone hear the pedalboard without a guitar or audio interface:
// the riff is generated on device (no bundled audio, works offline) and is
// fed into the effects chain exactly where a real guitar would be.

enum DemoRiffSynthesizer {

    /// One power chord hit, positioned on an eighth-note grid.
    private struct Hit {
        let slot: Int        // eighth-note index from the start of the loop
        let root: Int        // MIDI note number of the root
        let length: Int      // in eighth notes
        let palmMuted: Bool
    }

    static let tempo: Double = 112

    /// Two bars in E minor that loop seamlessly (E5 · G5 · A5 · C5 · B5 · D5).
    private static let riff: [Hit] = [
        Hit(slot: 0,  root: 40, length: 1, palmMuted: true),
        Hit(slot: 1,  root: 40, length: 1, palmMuted: true),
        Hit(slot: 2,  root: 43, length: 2, palmMuted: false),
        Hit(slot: 4,  root: 40, length: 1, palmMuted: true),
        Hit(slot: 5,  root: 40, length: 1, palmMuted: true),
        Hit(slot: 6,  root: 45, length: 2, palmMuted: false),
        Hit(slot: 8,  root: 40, length: 1, palmMuted: true),
        Hit(slot: 9,  root: 40, length: 1, palmMuted: true),
        Hit(slot: 10, root: 48, length: 1, palmMuted: false),
        Hit(slot: 11, root: 47, length: 1, palmMuted: false),
        Hit(slot: 12, root: 45, length: 4, palmMuted: false),

        Hit(slot: 16, root: 40, length: 1, palmMuted: true),
        Hit(slot: 17, root: 40, length: 1, palmMuted: true),
        Hit(slot: 18, root: 43, length: 2, palmMuted: false),
        Hit(slot: 20, root: 40, length: 1, palmMuted: true),
        Hit(slot: 21, root: 40, length: 1, palmMuted: true),
        Hit(slot: 22, root: 45, length: 2, palmMuted: false),
        Hit(slot: 24, root: 50, length: 2, palmMuted: false),
        Hit(slot: 26, root: 48, length: 2, palmMuted: false),
        Hit(slot: 28, root: 47, length: 4, palmMuted: false),
    ]

    private static let loopLengthInEighths = 32

    /// Renders one loop of the riff as mono samples, normalised to a guitar-like level.
    static func render(sampleRate: Double) -> [Float] {
        let eighth = 60 / tempo / 2
        let totalFrames = Int(Double(loopLengthInEighths) * eighth * sampleRate)
        var output = [Float](repeating: 0, count: totalFrames)
        var random = SeededRandom(seed: 0x5249_4646)  // "RIFF" – same riff every time

        for hit in riff {
            let start = Int(Double(hit.slot) * eighth * sampleRate)
            let frames = Int(Double(hit.length) * eighth * sampleRate)
            // Power chord: root, fifth, octave – strummed a few ms apart
            for (stringIndex, interval) in [0, 7, 12].enumerated() {
                let frequency = 440 * pow(2, Double(hit.root + interval - 69) / 12)
                let strumOffset = Int(Double(stringIndex) * 0.006 * sampleRate)
                pluck(
                    into: &output,
                    frequency: frequency,
                    start: start + strumOffset,
                    frames: frames - strumOffset,
                    palmMuted: hit.palmMuted,
                    sampleRate: sampleRate,
                    random: &random
                )
            }
        }

        let peak = output.reduce(0) { max($0, abs($1)) }
        if peak > 0 {
            let gain = 0.5 / peak
            for i in output.indices { output[i] *= gain }
        }
        return output
    }

    /// Karplus–Strong: a burst of noise circulating through a damped delay line.
    private static func pluck(
        into output: inout [Float],
        frequency: Double,
        start: Int,
        frames: Int,
        palmMuted: Bool,
        sampleRate: Double,
        random: inout SeededRandom
    ) {
        let period = max(2, Int(sampleRate / frequency))
        var delayLine = (0..<period).map { _ in random.nextSignedUnit() }
        let damping: Float = palmMuted ? 0.965 : 0.996
        let releaseFrames = Int(0.01 * sampleRate)
        let end = min(output.count, start + frames)
        guard start < end else { return }

        var index = 0
        for frame in start..<end {
            let current = delayLine[index]
            let next = delayLine[(index + 1) % period]
            delayLine[index] = damping * 0.5 * (current + next)
            index = (index + 1) % period

            // Short fade at the end of each note so hits don't click
            let remaining = end - frame
            let release = remaining < releaseFrames ? Float(remaining) / Float(releaseFrames) : 1
            output[frame] += current * release
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
