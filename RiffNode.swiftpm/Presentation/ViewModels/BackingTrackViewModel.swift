import SwiftUI
import Observation

// MARK: - Backing Track View Model

/// Handles backing track playback logic
@Observable
@MainActor
final class BackingTrackViewModel {

    // MARK: - State

    var loadedTrackName: String?
    var isLoading = false
    var reelRotation: Double = 0

    // MARK: - Dependencies

    private let backingTrackManager: BackingTrackManaging

    // MARK: - Initialization

    init(backingTrackManager: BackingTrackManaging) {
        self.backingTrackManager = backingTrackManager
    }

    // MARK: - Computed Properties

    var isPlaying: Bool {
        backingTrackManager.isBackingTrackPlaying
    }

    var hasTrack: Bool {
        loadedTrackName != nil
    }

    var volume: Float {
        get { backingTrackManager.backingTrackVolume }
        set { backingTrackManager.setBackingTrackVolume(newValue) }
    }

    // MARK: - Actions

    func loadTrack(url: URL) async {
        isLoading = true
        loadedTrackName = url.lastPathComponent

        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try await backingTrackManager.loadBackingTrack(url: url)
        } catch {
            loadedTrackName = nil
            print("Failed to load backing track: \(error)")
        }

        isLoading = false
    }

    func play() {
        backingTrackManager.playBackingTrack()
        startReelAnimation()
    }

    func stop() {
        backingTrackManager.stopBackingTrack()
        stopReelAnimation()
    }

    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }

    // MARK: - Reel Animation

    private var reelAnimationTask: Task<Void, Never>?

    func startReelAnimation() {
        stopReelAnimation()
        reelAnimationTask = Task {
            await runReelAnimationLoop()
        }
    }

    private func runReelAnimationLoop() async {
        while !Task.isCancelled && isPlaying {
            withAnimation(.linear(duration: 0.03)) {
                reelRotation += 2
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    func stopReelAnimation() {
        reelAnimationTask?.cancel()
        reelAnimationTask = nil
    }
}
