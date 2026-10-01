import SwiftUI
import UniformTypeIdentifiers

// MARK: - Jam Track Card
// Play along with your own song. Compact when empty (one row), a small player when loaded:
// play / pause, scrubbing, volume, and whether the song goes through your pedals.

struct BackingTrackView: View {

    @Bindable var engine: AudioEngineManager

    @State private var isImporting = false
    @State private var loadedTrackName: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let name = loadedTrackName {
                player(trackName: name)
            } else {
                emptyRow
            }
        }
        .padding(Spacing.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CornerRadius.xl))
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .animation(.smooth(duration: 0.25), value: loadedTrackName)
    }

    // MARK: - Empty

    private var emptyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.riffPrimary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.12)), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 1) {
                Text("Jam Track")
                    .font(.headline)
                Text("Play along with a song")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Import", systemImage: "plus") { isImporting = true }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }

    // MARK: - Player

    private func player(trackName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    engine.isBackingTrackPlaying ? engine.stopBackingTrack() : engine.playBackingTrack()
                } label: {
                    ZStack {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: engine.isBackingTrackPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.2)).interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityLabel(engine.isBackingTrackPlaying ? "Pause jam track" : "Play jam track")

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTrackName(trackName))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(formatTime(engine.backingTrackCurrentTime)) / \(formatTime(engine.backingTrackDuration))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Choose Another Song", systemImage: "arrow.triangle.2.circlepath") { isImporting = true }
                    Button("Remove", systemImage: "xmark", role: .destructive) {
                        engine.stopBackingTrack()
                        loadedTrackName = nil
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Jam track options")
            }

            if engine.backingTrackDuration > 0 {
                TrackTimeline(
                    currentTime: engine.backingTrackCurrentTime,
                    duration: engine.backingTrackDuration,
                    onSeek: { engine.seekBackingTrack(to: $0) }
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { engine.backingTrackVolume },
                        set: { engine.setBackingTrackVolume($0) }
                    ),
                    in: 0...1
                )
                .accessibilityLabel("Jam track volume")
            }

            Toggle(isOn: Binding(
                get: { engine.backingTrackThroughEffects },
                set: { _ in engine.toggleBackingTrackThroughEffects() }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Play through my pedals")
                        .font(.subheadline.weight(.medium))
                    Text("Hear how your effects shape a real song")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.orange)
        }
    }

    // MARK: - Helpers

    private func formatTrackName(_ name: String) -> String {
        var n = name
        if let dot = n.lastIndex(of: ".") { n = String(n[..<dot]) }
        return n
    }

    private func formatTime(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isLoading = true
        loadedTrackName = url.lastPathComponent
        Task { @MainActor in
            do {
                let accessing = url.startAccessingSecurityScopedResource()
                try await engine.loadBackingTrack(url: url)
                if accessing { url.stopAccessingSecurityScopedResource() }
                isLoading = false
            } catch {
                isLoading = false
                loadedTrackName = nil
            }
        }
    }
}



// MARK: - Track Timeline

struct TrackTimeline: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : currentTime / duration
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 8)

                    // Fill with glow
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.riffPrimary.opacity(0.6), Color.riffPrimary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * progress), height: 8)
                        .shadow(color: Color.riffPrimary.opacity(0.4), radius: 4, x: 0, y: 0)

                    // Scrubber knob
                    let knobX = max(10, min(geo.size.width - 10, geo.size.width * progress))
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 18 : 13, height: isDragging ? 18 : 13)
                        .shadow(color: .black.opacity(0.25), radius: 4)
                        .position(x: knobX, y: geo.size.height / 2)
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            isDragging = true
                            dragProgress = max(0, min(1, v.location.x / geo.size.width))
                        }
                        .onEnded { v in
                            isDragging = false
                            onSeek(max(0, min(1, v.location.x / geo.size.width)) * duration)
                        }
                )
            }
            .frame(height: 18)

            HStack {
                Text(String(format: "%d:%02d", Int(isDragging ? dragProgress * duration : currentTime) / 60,
                            Int(isDragging ? dragProgress * duration : currentTime) % 60))
                Spacer()
                Text("-" + String(format: "%d:%02d",
                                  Int(duration - (isDragging ? dragProgress * duration : currentTime)) / 60,
                                  Int(duration - (isDragging ? dragProgress * duration : currentTime)) % 60))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()
        BackingTrackView(engine: AudioEngineManager())
            .padding()
            .frame(width: 400)
    }
}
