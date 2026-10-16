import Foundation
import Observation

// MARK: - Play Along View Model
// The rules behind the Play Along card: which mode is showing, what playing or switching
// modes does, the groove's key and tempo, and importing songs. The view only draws.

@Observable
@MainActor
final class PlayAlongViewModel {

    enum Mode: String, CaseIterable, Identifiable {
        case groove = "Groove", song = "Song", musicApp = "Music app"
        var id: String { rawValue }
    }

    let player: any BackingTrackManaging
    let music: any MusicAppControlling

    var mode: Mode = .groove {
        didSet { if mode != oldValue { modeDidChange() } }
    }
    private(set) var isLoading = false
    /// Name shown while an imported file is still loading.
    private(set) var pendingTrackName: String?

    init(player: any BackingTrackManaging, music: any MusicAppControlling) {
        self.player = player
        self.music = music
    }

    // MARK: - Groove

    var isGroovePlaying: Bool { player.isBuiltInJamTrack && player.isBackingTrackPlaying }

    var keyName: String { JamTrackSynthesizer.keyName(transpose: player.grooveTranspose) }
    var chords: [String] { JamTrackSynthesizer.chords(transpose: player.grooveTranspose) }
    var scale: String { JamTrackSynthesizer.scale(transpose: player.grooveTranspose) }
    var keys: [(name: String, transpose: Int)] { JamTrackSynthesizer.keys }

    /// The bar (0–3) the groove is on, so the matching chord lights up.
    var currentBar: Int? {
        guard isGroovePlaying else { return nil }
        let barSeconds = 240 / player.grooveTempo
        return Int(player.backingTrackCurrentTime / barSeconds) % 4
    }

    func toggleGroove() {
        if isGroovePlaying {
            player.stopBackingTrack()
        } else if (try? player.loadBuiltInJamTrack(tempo: nil, transpose: nil)) != nil {
            player.playBackingTrack()
        }
    }

    func setKey(transpose: Int) { restartGroove(tempo: nil, transpose: transpose) }

    func stepTempo(by step: Double) {
        let range = JamTrackSynthesizer.tempoRange
        restartGroove(tempo: min(max(player.grooveTempo + step, range.lowerBound), range.upperBound), transpose: nil)
    }

    /// Applies a new key or tempo; keeps playing if it was playing.
    private func restartGroove(tempo: Double?, transpose: Int?) {
        let wasPlaying = isGroovePlaying
        guard player.isReady, (try? player.loadBuiltInJamTrack(tempo: tempo, transpose: transpose)) != nil else { return }
        if wasPlaying { player.playBackingTrack() }
    }

    // MARK: - Song

    /// The imported song's name, if one is loaded (or loading).
    var songName: String? {
        (player.isBuiltInJamTrack ? nil : player.backingTrackName) ?? pendingTrackName
    }

    func toggleSong() {
        player.isBackingTrackPlaying ? player.stopBackingTrack() : player.playBackingTrack()
    }

    func importSong(from url: URL) {
        isLoading = true
        pendingTrackName = url.deletingPathExtension().lastPathComponent
        Task {
            let accessing = url.startAccessingSecurityScopedResource()
            try? await player.loadBackingTrack(url: url)
            if accessing { url.stopAccessingSecurityScopedResource() }
            isLoading = false
            pendingTrackName = nil
        }
    }

    // MARK: - Modes

    /// One thing at a time: leaving a mode stops what it was playing.
    private func modeDidChange() {
        switch mode {
        case .groove where !player.isBuiltInJamTrack, .song where player.isBuiltInJamTrack, .musicApp:
            player.stopBackingTrack()
        default:
            break
        }
    }
}
