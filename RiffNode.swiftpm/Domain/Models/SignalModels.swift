import Foundation

// MARK: - Signal Analysis Models

/// A short recording of the signal at one point in the chain (Signal Lab).
struct SignalCapture: Sendable {
    /// The latest raw samples (mono).
    var samples: [Float] = []
    /// RMS of each 512-sample block – about 11 ms each, a few seconds in all.
    var envelope: [Float] = []
    /// Engine sample time of the last sample, used to line the two sides up.
    var endSampleTime: Int64 = 0
    var sampleRate: Double = 48_000
}

/// One EQ move the Tone balance card suggests: a band of the 10-band EQ and how far to push it.
struct ToneSuggestion: Equatable, Sendable {
    let band: Int
    let gain: Float
    let label: String
}
