import Foundation

// MARK: - Thread-Safe Result Types
// Sendable types for cross-isolation transfer in Swift 6 strict concurrency

/// FFT analysis result for cross-isolation transfer
struct FFTResult: Sendable {
    let magnitudes: [Float]
    let frequencies: [Float]
    let peakFrequency: Float
    let peakMagnitude: Float
    let dominantBand: String
    let bandEnergies: [String: Float]
}

/// Chord detection result for cross-isolation transfer
struct ChordResult: Sendable {
    let detectedPitch: Float
    let detectedNote: String
    let detectedOctave: Int
    let fullNoteName: String
    let detectedChord: String
    let confidence: Float
    let centsDeviation: Float
    let isInTune: Bool
    let activeNotes: [String]
}

/// Audio data packet for thread-safe transfer
struct AudioData: Sendable {
    let samples: [Float]
    let waveform: [Float]
    let rms: Float
}
