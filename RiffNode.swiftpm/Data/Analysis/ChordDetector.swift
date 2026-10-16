import Accelerate
import AVFoundation
import Foundation
import Observation

// MARK: - Chord Detector
// YIN single-note pitch estimation, with a separate recent-note chord hint.
// The chord hint describes successive notes; it is not a polyphonic chord detector.

@Observable
@MainActor
final class ChordDetector: ChordDetecting {

    // MARK: - Output

    /// Detected fundamental frequency in Hz
    private(set) var detectedPitch: Float = 0

    /// Detected musical note (e.g., "E", "A#")
    private(set) var detectedNote: String = "—"

    /// Detected octave (e.g., 2, 3, 4)
    private(set) var detectedOctave: Int = 0

    /// Full note name with octave (e.g., "E2", "A4")
    private(set) var fullNoteName: String = "—"

    /// Detected chord (e.g., "E Major", "Am")
    private(set) var detectedChord: String = "—"

    /// Confidence level (0.0 to 1.0)
    private(set) var confidence: Float = 0

    /// Cents deviation from perfect pitch (-50 to +50)
    private(set) var centsDeviation: Float = 0

    /// Is the note in tune? (within 10 cents)
    private(set) var isInTune: Bool = false

    /// Recently detected notes for chord analysis
    private(set) var activeNotes: [String] = []

    // MARK: - Configuration

    var sampleRate: Float = 44100
    private let minFrequency: Float = 60   // ~B1 (lowest guitar note)
    private let maxFrequency: Float = 1400 // ~F6 (highest typical guitar note)
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var analysisGeneration = 0

    // MARK: - Note Detection History

    private var noteHistory: [(note: String, time: Date)] = []
    private let noteHistoryDuration: TimeInterval = 0.5 // Keep notes for chord detection

    // MARK: - Note Names

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // MARK: - Common Guitar Chords

    private let chordPatterns: [String: Set<String>] = [
        // Major chords
        "C Major": ["C", "E", "G"],
        "D Major": ["D", "F#", "A"],
        "E Major": ["E", "G#", "B"],
        "F Major": ["F", "A", "C"],
        "G Major": ["G", "B", "D"],
        "A Major": ["A", "C#", "E"],
        "B Major": ["B", "D#", "F#"],

        // Minor chords
        "Cm": ["C", "D#", "G"],
        "Dm": ["D", "F", "A"],
        "Em": ["E", "G", "B"],
        "Fm": ["F", "G#", "C"],
        "Gm": ["G", "A#", "D"],
        "Am": ["A", "C", "E"],
        "Bm": ["B", "D", "F#"],

        // 7th chords
        "C7": ["C", "E", "G", "A#"],
        "D7": ["D", "F#", "A", "C"],
        "E7": ["E", "G#", "B", "D"],
        "G7": ["G", "B", "D", "F"],
        "A7": ["A", "C#", "E", "G"],

        // Power chords (common in rock)
        "E5": ["E", "B"],
        "A5": ["A", "E"],
        "D5": ["D", "A"],
        "G5": ["G", "D"],
    ]

    // MARK: - Analyze Audio

    /// Keep one analysis in flight; reset/source changes invalidate older results.
    func analyze(samples: [Float]) {
        guard samples.count >= 2048, analysisTask == nil else { return }
        let sr = sampleRate
        let minF = minFrequency
        let maxF = maxFrequency
        let generation = analysisGeneration
        analysisTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.computePitchEstimate(
                samples: samples, sampleRate: sr, minFrequency: minF, maxFrequency: maxF)
            }.value
            guard let self, generation == self.analysisGeneration else { return }
            self.analysisTask = nil
            guard sr == self.sampleRate else { return }
            self.applyPitchResult(result.frequency, confidence: result.confidence)
        }
    }

    /// Apply the pitch result computed on a background thread.
    /// All @Observable property mutations stay on MainActor.
    func applyPitchResult(_ pitch: Float, samples: [Float]) {
        let result = Self.computePitchEstimate(samples: samples, sampleRate: sampleRate)
        applyPitchResult(pitch, confidence: result.confidence)
    }

    private func applyPitchResult(_ pitch: Float, confidence periodicity: Float) {
        guard pitch.isFinite, pitch >= minFrequency, pitch <= maxFrequency, periodicity >= 0.8 else {
            clearDetection()
            return
        }

        detectedPitch = pitch
        confidence = periodicity

        let (note, octave, cents) = frequencyToNote(pitch)
        detectedNote = note
        detectedOctave = octave
        centsDeviation = cents
        fullNoteName = "\(note)\(octave)"
        isInTune = abs(cents) < 10

        updateNoteHistory(note: note)
        detectChord()
    }

    // MARK: - Background Pitch Detection (nonisolated — safe to call from any thread)

    struct PitchEstimate: Sendable {
        let frequency: Float
        let confidence: Float
    }

    /// Returns zero for silence or a signal without a reliable periodic minimum.
    nonisolated static func computePitchBackground(
        samples: [Float],
        sampleRate: Float,
        minFrequency: Float = 60,
        maxFrequency: Float = 1400
    ) -> Float {
        computePitchEstimate(samples: samples, sampleRate: sampleRate,
                             minFrequency: minFrequency, maxFrequency: maxFrequency).frequency
    }

    /// YIN cumulative mean normalized difference, followed by parabolic interpolation.
    nonisolated static func computePitchEstimate(
        samples: [Float], sampleRate: Float,
        minFrequency: Float = 60, maxFrequency: Float = 1400
    ) -> PitchEstimate {
        let none = PitchEstimate(frequency: 0, confidence: 0)
        guard samples.count >= 2048, sampleRate.isFinite, sampleRate > 0,
              minFrequency > 0, maxFrequency > minFrequency,
              samples.allSatisfy(\.isFinite) else { return none }
        let minLag = max(2, Int(ceil(sampleRate / maxFrequency)))
        let maxLag = min(samples.count / 2 - 1, Int(sampleRate / minFrequency))
        guard maxLag > minLag else { return none }
        let mean = vDSP.mean(samples)
        let centered = samples.map { $0 - mean }
        guard vDSP.rootMeanSquare(centered) >= 0.001 else { return none }
        let window = samples.count / 2
        var squares = [Float](repeating: 0, count: centered.count + 1)
        for i in centered.indices { squares[i + 1] = squares[i] + centered[i] * centered[i] }
        var normalized = [Float](repeating: 1, count: maxLag + 1)
        var cumulative: Float = 0
        centered.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for lag in 1...maxLag {
                var dot: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &dot, vDSP_Length(window))
                let difference = max(0, squares[window] + squares[window + lag] - squares[lag] - 2 * dot)
                cumulative += difference
                normalized[lag] = cumulative > 0 ? difference * Float(lag) / cumulative : 1
            }
        }
        var lag = minLag
        while lag < maxLag {
            if normalized[lag] < 0.15 {
                while lag < maxLag && normalized[lag + 1] < normalized[lag] { lag += 1 }
                let certainty = max(0, min(1, 1 - normalized[lag]))
                var refined = Float(lag)
                if lag > 1, lag < maxLag {
                    let left = normalized[lag - 1], middle = normalized[lag], right = normalized[lag + 1]
                    let denominator = left - 2 * middle + right
                    if abs(denominator) > 1e-9 {
                        refined += max(-1, min(1, 0.5 * (left - right) / denominator))
                    }
                }
                let frequency = sampleRate / refined
                guard frequency >= minFrequency, frequency <= maxFrequency else { return none }
                return PitchEstimate(frequency: frequency, confidence: certainty)
            }
            lag += 1
        }
        return none
    }

    // MARK: - Frequency to Note Conversion

    private func frequencyToNote(_ frequency: Float) -> (note: String, octave: Int, cents: Float) {
        // A4 = 440 Hz is our reference
        let a4Frequency: Float = 440.0
        let a4NoteNumber: Float = 69 // MIDI note number for A4

        // Calculate semitones from A4
        let semitones = 12 * log2(frequency / a4Frequency)
        let noteNumber = a4NoteNumber + semitones

        // Round to nearest note
        let roundedNoteNumber = Int(round(noteNumber))
        let noteIndex = ((roundedNoteNumber % 12) + 12) % 12
        let octave = (roundedNoteNumber / 12) - 1

        // Calculate cents deviation
        let exactNoteNumber = a4NoteNumber + semitones
        let cents = (exactNoteNumber - Float(roundedNoteNumber)) * 100

        return (noteNames[noteIndex], octave, cents)
    }

    // MARK: - Note History Management

    private func updateNoteHistory(note: String) {
        let now = Date()

        // Add new note
        noteHistory.append((note: note, time: now))

        // Remove old notes
        noteHistory = noteHistory.filter { now.timeIntervalSince($0.time) < noteHistoryDuration }

        // Get unique active notes
        let uniqueNotes = Set(noteHistory.map { $0.note })
        activeNotes = Array(uniqueNotes).sorted()
    }

    // MARK: - Chord Detection

    private func detectChord() {
        guard activeNotes.count >= 2 else {
            detectedChord = activeNotes.first.map { "\($0) note" } ?? "—"
            return
        }

        let activeSet = Set(activeNotes)

        // Find best matching chord
        var bestMatch: (name: String, score: Int) = ("", 0)

        for chordName in chordPatterns.keys.sorted() {
            let chordNotes = chordPatterns[chordName]!
            let matchingNotes = activeSet.intersection(chordNotes)
            let score = matchingNotes.count

            // Require at least 2 matching notes and better than current best
            if score >= 2 && score > bestMatch.score {
                bestMatch = (chordName, score)
            }
        }

        if bestMatch.score >= 2 {
            detectedChord = bestMatch.name
        } else {
            // Show the notes if no chord pattern matches
            detectedChord = activeNotes.joined(separator: "-")
        }
    }

    // MARK: - Reset

    func reset() {
        analysisGeneration += 1
        analysisTask?.cancel()
        analysisTask = nil
        clearDetection()
    }

    private func clearDetection() {
        detectedPitch = 0
        detectedNote = "—"
        detectedOctave = 0
        fullNoteName = "—"
        detectedChord = "—"
        confidence = 0
        centsDeviation = 0
        isInTune = false
        activeNotes = []
        noteHistory = []
    }
}
