import Foundation
import Observation
#if os(iOS) && !targetEnvironment(macCatalyst)
import MediaPlayer
#endif

// MARK: - System Music Service
// Play along with Apple Music or Spotify.
//
// RiffNode's audio session mixes with other apps, so a song playing in Music, Spotify or any
// other app keeps playing while your guitar runs through RiffNode's pedals. On iPad, Apple
// Music can also be controlled from inside RiffNode (play / pause / skip, now playing),
// including songs downloaded for offline listening. Spotify has no offline control API,
// so it is played from its own app.

@Observable
@MainActor
final class SystemMusicService {

    /// Apple Music remote control is available (iPad; not on Mac).
    let canControlAppleMusic: Bool
    private(set) var isAuthorized = false
    private(set) var isDenied = false
    private(set) var title: String?
    private(set) var artist: String?
    private(set) var isPlaying = false

    init() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        canControlAppleMusic = true
        let status = MPMediaLibrary.authorizationStatus()
        isAuthorized = status == .authorized
        isDenied = status == .denied || status == .restricted
        #else
        canControlAppleMusic = false
        #endif
    }

    func requestAccess() async {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let status = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
        }
        isAuthorized = status == .authorized
        isDenied = status == .denied || status == .restricted
        refresh()
        #endif
    }

    /// Reads what Apple Music is playing.
    func refresh() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard isAuthorized else { return }
        let player = MPMusicPlayerController.systemMusicPlayer
        title = player.nowPlayingItem?.title
        artist = player.nowPlayingItem?.artist
        isPlaying = player.playbackState == .playing
        #endif
    }

    func togglePlayback() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard isAuthorized else { return }
        let player = MPMusicPlayerController.systemMusicPlayer
        if player.playbackState == .playing {
            player.pause()
        } else {
            // Nothing queued yet: start the library on shuffle so the button always does something
            if player.nowPlayingItem == nil {
                player.setQueue(with: .songs())
                player.shuffleMode = .songs
            }
            player.play()
        }
        refresh()
        #endif
    }

    func skipToNext() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard isAuthorized else { return }
        MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
        refresh()
        #endif
    }

    func skipToPrevious() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard isAuthorized else { return }
        MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
        refresh()
        #endif
    }

    // MARK: - Opening the apps

    static let appleMusicURL = URL(string: "music://")!
    static let spotifyURL = URL(string: "spotify://")!
}
