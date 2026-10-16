import Foundation

// MARK: - Effect Physics
// What each pedal physically does to the signal, and which view shows it best.
// Used by the Signal Lab, which draws the pedal's input against its output.

/// A way of looking at a signal.
enum SignalLens: String, CaseIterable, Identifiable, Sendable {
    /// A few milliseconds of the waveform – the shape of each cycle
    case wave = "Wave"
    /// Loudness over the last few seconds
    case volume = "Volume"
    /// How much energy sits at each frequency
    case frequencies = "Frequencies"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .wave: "waveform.path"
        case .volume: "chart.line.uptrend.xyaxis"
        case .frequencies: "chart.bar.xaxis"
        }
    }

    var caption: String {
        switch self {
        case .wave: "11 ms of the waveform"
        case .volume: "Loudness, last 3 seconds"
        case .frequencies: "Energy per frequency, 60 Hz – 12 kHz"
        }
    }
}

extension EffectType {

    /// The view where this pedal's change is easiest to see.
    var primaryLens: SignalLens {
        switch self {
        case .overdrive, .distortion, .fuzz: .wave
        case .compressor, .tremolo, .delay, .reverb: .volume
        case .equalizer, .chorus, .phaser, .flanger: .frequencies
        }
    }

    /// One line: the physical change.
    var physicsHeadline: String {
        switch self {
        case .compressor: "Squeezes loud and quiet closer together"
        case .equalizer: "Boosts or cuts bands of frequencies"
        case .overdrive: "Rounds off the peaks – soft clipping"
        case .distortion: "Cuts the peaks off flat – hard clipping"
        case .fuzz: "Clips so hard the wave turns square"
        case .chorus: "Mixes in a slowly detuned copy"
        case .phaser: "Sweeps notches through the spectrum"
        case .flanger: "A comb of notches that sweeps up and down"
        case .tremolo: "Turns the volume up and down, over and over"
        case .delay: "Plays back what you played, later"
        case .reverb: "Thousands of reflections blur into a tail"
        }
    }

    /// Why it sounds the way it does – the physics, in two sentences.
    var physicsExplanation: String {
        switch self {
        case .compressor:
            "Above the threshold, the level is turned down by the ratio. Loud picks come down, so the range between loud and soft shrinks and notes seem to sustain."
        case .equalizer:
            "An EQ is a set of filters. Each band raises or lowers energy around its frequency – the spectrum changes shape while the rhythm stays the same."
        case .overdrive:
            "Past a point, the circuit can't follow the wave, so the tops bend over smoothly. Rounded peaks add gentle, mostly low harmonics: warm and singing."
        case .distortion:
            "The wave is cut off at a ceiling. A flat-topped wave is close to a square wave, which carries strong odd harmonics (3×, 5×, 7× the note) – the bright buzz."
        case .fuzz:
            "Clipping this hard leaves almost a square wave: the richest set of harmonics, and nearly the same loudness whether you pick soft or hard."
        case .chorus:
            "A copy delayed by 10–30 ms, with the delay slowly wobbling, is mixed back in. The copy's pitch drifts, and where the two disagree some frequencies cancel – the shimmer."
        case .phaser:
            "Filters shift the timing (phase) of each frequency by a different amount. Mixed with the dry signal, some frequencies cancel into notches that sweep up and down."
        case .flanger:
            "A copy delayed by under 10 ms is mixed in, so evenly spaced frequencies cancel – a comb. As the delay moves, the comb sweeps: the jet-plane whoosh."
        case .tremolo:
            "A slow oscillator (an LFO) turns the volume up and down several times a second. The volume line ripples at the rate you set."
        case .delay:
            "The signal is stored and played back after the delay time; feedback sends each echo round again, quieter. The gaps between notes fill with fading copies."
        case .reverb:
            "It simulates sound bouncing off walls: thousands of tiny echoes too dense to hear apart. Notes ring on after you stop, so the quiet gaps fill in."
        }
    }
}
