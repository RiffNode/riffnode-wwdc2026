import Accelerate
import AVFoundation
import SwiftUI

// MARK: - Chord Detector
// Real-time pitch detection and chord recognition using autocorrelation
// Educational feature showing AI/ML concepts in audio analysis

@Observable
@MainActor
final class ChordDetector {

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

    /// Analyze audio samples — offloads heavy autocorrelation to background thread.
    func analyze(samples: [Float]) {
        guard samples.count >= 2048 else { return }
        let sr = sampleRate
        let minF = minFrequency
        let maxF = maxFrequency
        // Heavy autocorrelation runs on a background thread; results posted back on MainActor
        Task.detached(priority: .userInitiated) { [weak self] in
            let pitch = ChordDetector.computePitchBackground(
                samples: samples, sampleRate: sr, minFrequency: minF, maxFrequency: maxF)
            await self?.applyPitchResult(pitch, samples: samples)
        }
    }

    /// Apply the pitch result computed on a background thread.
    /// All @Observable property mutations stay on MainActor.
    func applyPitchResult(_ pitch: Float, samples: [Float]) {
        guard pitch > minFrequency && pitch < maxFrequency else {
            confidence = 0
            return
        }

        detectedPitch = pitch
        confidence = calculateConfidence(samples: samples, pitch: pitch)

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

    /// Vectorized autocorrelation using vDSP_dotpr — ~10× faster than scalar loops.
    /// Returns the fundamental frequency in Hz, or 0 if no pitch found.
    nonisolated static func computePitchBackground(
        samples: [Float],
        sampleRate: Float,
        minFrequency: Float = 60,
        maxFrequency: Float = 1400
    ) -> Float {
        let count = samples.count
        guard count >= 2048 else { return 0 }

        let minLag = Int(sampleRate / maxFrequency)
        let maxLag = Int(sampleRate / minFrequency)
        guard minLag > 0, maxLag > minLag, maxLag < count else { return 0 }

        let size = maxLag - minLag
        var autocorrelation = [Float](repeating: 0, count: size)

        // vDSP_dotpr computes the dot product of two vectors in one SIMD call.
        // autocorrelation[lag] = Σ samples[i] * samples[i + lag]
        // This replaces the O(n²) scalar double-loop with vectorized single-pass calls.
        samples.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            for lag in minLag..<maxLag {
                let n = vDSP_Length(count - lag)
                vDSP_dotpr(base, 1, base + lag, 1, &autocorrelation[lag - minLag], n)
            }
        }

        // Find peak lag (vectorized max search)
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(autocorrelation, 1, &maxVal, &maxIdx, vDSP_Length(size))

        let lag = Int(maxIdx) + minLag
        return lag > 0 ? sampleRate / Float(lag) : 0
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

    // MARK: - Confidence Calculation

    private func calculateConfidence(samples: [Float], pitch: Float) -> Float {
        // Simple confidence based on signal energy and periodicity
        var energy: Float = 0
        vDSP_measqv(samples, 1, &energy, vDSP_Length(samples.count))

        // Normalize to 0-1 range (threshold based on typical guitar levels)
        let normalizedEnergy = min(1.0, energy / 0.01)

        return normalizedEnergy
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

        for (chordName, chordNotes) in chordPatterns {
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

// MARK: - Chord Detector View

struct ChordDetectorView: View {
    let detector: ChordDetector

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .foregroundStyle(.yellow)
                    Text("CHORD DETECTION")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }

                Spacer()

                // Confidence meter
                HStack(spacing: 4) {
                    Text("AI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    ConfidenceMeter(confidence: detector.confidence)
                }
            }

            // Main display
            HStack(spacing: 24) {
                // Note display
                VStack(spacing: 4) {
                    Text(detector.detectedNote)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(detector.isInTune ? .green : .white)

                    Text(detector.fullNoteName)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 100)

                // Tuning indicator
                TuningIndicator(cents: detector.centsDeviation)

                // Chord display
                VStack(spacing: 4) {
                    Text(detector.detectedChord)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.yellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    // Active notes
                    HStack(spacing: 4) {
                        ForEach(detector.activeNotes, id: \.self) { note in
                            Text(note)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Frequency display
            HStack {
                Text(String(format: "%.1f Hz", detector.detectedPitch))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                // Tuning status
                HStack(spacing: 4) {
                    Circle()
                        .fill(detector.isInTune ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(detector.isInTune ? "In Tune" : tuningDirection)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .glassEffect(.regular.tint(.yellow.opacity(0.1)), in: RoundedRectangle(cornerRadius: 12))
    }

    private var tuningDirection: String {
        if detector.centsDeviation > 10 {
            return "Sharp (\(Int(detector.centsDeviation))¢)"
        } else if detector.centsDeviation < -10 {
            return "Flat (\(Int(detector.centsDeviation))¢)"
        }
        return "—"
    }
}

// MARK: - Confidence Meter

struct ConfidenceMeter: View {
    let confidence: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Rectangle()
                    .fill(i < Int(confidence * 5) ? Color.green : Color.white.opacity(0.2))
                    .frame(width: 4, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
    }
}

// MARK: - Tuning Indicator

struct TuningIndicator: View {
    let cents: Float

    var body: some View {
        VStack(spacing: 4) {
            // Visual tuner
            GeometryReader { geometry in
                let width = geometry.size.width
                let center = width / 2
                let offset = CGFloat(cents / 50) * (width / 2 - 10)

                ZStack {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)

                    // Center marker
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: 2, height: 16)
                        .position(x: center, y: geometry.size.height / 2)

                    // Current pitch indicator
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 12, height: 12)
                        .position(x: center + offset, y: geometry.size.height / 2)
                        .shadow(color: indicatorColor.opacity(0.5), radius: 4)
                }
            }
            .frame(width: 80, height: 20)

            // Labels
            HStack {
                Text("♭")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("♯")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80)
        }
    }

    private var indicatorColor: Color {
        let absCents = abs(cents)
        if absCents < 10 {
            return .green
        } else if absCents < 25 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Compact Chord Badge (for top bar)
// Liquid Glass UI Design - iOS 26+

struct CompactChordBadge: View {
    let detector: ChordDetector

    var body: some View {
        HStack(spacing: 12) {
            // Chord icon
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.purple)

            // Detected chord
            VStack(alignment: .leading, spacing: 2) {
                Text("Detected Chord")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(detector.detectedChord.isEmpty ? "—" : detector.detectedChord)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(detector.detectedChord.isEmpty ? .secondary : .primary)
            }

            Spacer()

            // Confidence indicator
            if !detector.detectedChord.isEmpty {
                Text(String(format: "%.0f%%", detector.confidence * 100))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.purple)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var previewDetector = ChordDetector()
    VStack(spacing: 20) {
        ChordDetectorView(detector: previewDetector)
        CompactChordBadge(detector: previewDetector)
    }
    .padding()
    .background(Color.black)
}
