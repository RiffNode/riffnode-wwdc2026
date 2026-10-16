import AVFoundation
import Foundation
#if canImport(MusicUnderstanding)
import MusicUnderstanding
#endif

// MARK: - Song Analyzer
// Finds a song's key, tempo, bars and sections on device with the Music Understanding
// framework (iOS / macOS 27) – so Play Along can say "E minor, 120 BPM: solo in E minor
// pentatonic" and the metronome can lock to the song. Nothing leaves the device.

struct SongAnalyzer: SongAnalyzing {

    var isAvailable: Bool {
        #if canImport(MusicUnderstanding)
        if #available(iOS 27, macOS 27, *) { return true }
        #endif
        return false
    }

    func analyze(url: URL) async throws -> SongAnalysis {
        #if canImport(MusicUnderstanding)
        if #available(iOS 27, macOS 27, *) {
            let session = try await MusicUnderstandingSession(asset: AVURLAsset(url: url))
            let result = try await session.analyze(for: [.key, .rhythm, .structure, .instrumentActivity])

            // The key that covers most of the song
            let keys = result.key?.ranges ?? []
            let main = keys.max { $0.range.duration.seconds < $1.range.duration.seconds }?.value
            let tonic = main.map { Self.noteName($0.tonic.rawValue) }
            let isMinor = main?.mode == .minor
            let instruments = (result.instrumentActivity?.ranges.keys.map(\.rawValue) ?? []).sorted()

            return SongAnalysis(
                key: tonic.map { "\($0) \(isMinor ? "minor" : "major")" },
                isMinor: isMinor,
                tonic: tonic,
                beatsPerMinute: result.rhythm?.beatsPerMinute.map(Double.init),
                bars: result.rhythm?.bars.map(\.seconds) ?? [],
                sections: result.structure?.sections.map(\.start.seconds) ?? [],
                instruments: instruments
            )
        }
        #endif
        throw AudioEngineError.invalidConfiguration
    }

    /// "fSharp" → "F♯", "bFlat" → "B♭", "e" → "E"
    private static func noteName(_ raw: String) -> String {
        guard let first = raw.first else { return raw }
        let accidental = raw.hasSuffix("Sharp") ? "♯" : (raw.hasSuffix("Flat") ? "♭" : "")
        return first.uppercased() + accidental
    }
}
