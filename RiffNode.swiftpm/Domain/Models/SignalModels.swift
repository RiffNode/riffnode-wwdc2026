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

/// What the Signal Lab shows for one moment of one pedal: the waveform, the volume and the
/// spectrum on both sides, and the measurements that name the change.
struct SignalAnalysis: Sendable {
    var waveBefore: [Float] = []
    var waveAfter: [Float] = []
    var envelopeBefore: [Float] = []
    var envelopeAfter: [Float] = []
    /// Log-spaced bands over `spectrumRange`, 0…1
    var spectrumBefore: [Float] = []
    var spectrumAfter: [Float] = []
    var measurements = SignalMeasurements()
    /// True when nothing is coming into the pedal.
    var isSilent = true

    static let spectrumBands = 56
    static let spectrumRange: ClosedRange<Float> = 60...12_000
    static let waveLength = 512
}

/// The numbers under the Signal Lab plots.
struct SignalMeasurements: Equatable, Sendable {
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

    /// Part of the way from these readouts to `other` – smoothing so the numbers are legible.
    func blended(toward other: SignalMeasurements, amount t: Float) -> SignalMeasurements {
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        return SignalMeasurements(
            levelBefore: mix(levelBefore, other.levelBefore), levelAfter: mix(levelAfter, other.levelAfter),
            crestBefore: mix(crestBefore, other.crestBefore), crestAfter: mix(crestAfter, other.crestAfter),
            swingBefore: mix(swingBefore, other.swingBefore), swingAfter: mix(swingAfter, other.swingAfter),
            floorBefore: mix(floorBefore, other.floorBefore), floorAfter: mix(floorAfter, other.floorAfter),
            brightnessBefore: mix(brightnessBefore, other.brightnessBefore),
            brightnessAfter: mix(brightnessAfter, other.brightnessAfter))
    }
}

/// One EQ move the Tone balance card suggests: a band of the 10-band EQ and how far to push it.
struct ToneSuggestion: Equatable, Sendable {
    let band: Int
    let gain: Float
    let label: String
}
