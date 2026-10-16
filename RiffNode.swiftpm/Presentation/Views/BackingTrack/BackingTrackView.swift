import SwiftUI
import UniformTypeIdentifiers

// MARK: - Play Along Card
// Something to play over, three ways:
//  • Groove – a built-in drums-and-bass loop in any minor key and tempo, with the chord
//    you're on highlighted and the scale to solo with.
//  • Song – your own file, optionally run through your pedals.
//  • Music app – Apple Music (controlled from here on iPad) or Spotify, playing alongside.

struct BackingTrackView: View {

    @State private var viewModel: PlayAlongViewModel
    @State private var isImporting = false
    @State private var isDropTargeted = false

    private var player: any BackingTrackManaging { viewModel.player }
    private var music: any MusicAppControlling { viewModel.music }
    private var isLoading: Bool { viewModel.isLoading }

    init(player: any BackingTrackManaging, music: any MusicAppControlling = SystemMusicService()) {
        _viewModel = State(initialValue: PlayAlongViewModel(player: player, music: music))
    }
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker("Play along with", selection: $viewModel.mode) {
                ForEach(PlayAlongViewModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch viewModel.mode {
            case .groove: grooveSection
            case .song: songSection
            case .musicApp: musicAppSection
            }
        }
        .padding(Spacing.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CornerRadius.xl))
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .animation(.smooth(duration: 0.25), value: viewModel.mode)
        .animation(.smooth(duration: 0.25), value: player.backingTrackName)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.riffPrimary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.12)), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 1) {
                Text("Play Along")
                    .font(.headline)
                Text("A groove, your song, or your music app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Groove

    private var grooveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                playButton(isPlaying: viewModel.isGroovePlaying, label: "groove", action: viewModel.toggleGroove)
                    .disabled(!player.isReady)

                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        ForEach(viewModel.keys, id: \.transpose) { key in
                            Button(key.name) { viewModel.setKey(transpose: key.transpose) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.keyName)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        tempoButton("minus", by: -4)
                        Text("\(Int(player.grooveTempo)) BPM")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 54)
                        tempoButton("plus", by: 4)
                    }
                }
                Spacer(minLength: 0)
            }

            // The progression – the chord you're on lights up
            HStack(spacing: 6) {
                ForEach(Array(viewModel.chords.enumerated()), id: \.offset) { index, chord in
                    let isCurrent = viewModel.currentBar == index
                    Text(chord)
                        .font(.system(.callout, design: .rounded).weight(isCurrent ? .bold : .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(isCurrent ? Color.white : Color.primary)
                        .background(isCurrent ? Color.riffPrimary : Color.primary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .animation(.snappy(duration: 0.15), value: isCurrent)
                }
            }

            Label("Solo with \(viewModel.scale)", systemImage: "hand.point.up.left")
                .font(.caption)
                .foregroundStyle(.secondary)

            if player.isBuiltInJamTrack { volumeSlider }
        }
    }

    private func tempoButton(_ symbol: String, by step: Double) -> some View {
        Button { viewModel.stepTempo(by: step) } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step > 0 ? "Faster" : "Slower")
    }

    // MARK: - Song

    @ViewBuilder
    private var songSection: some View {
        if let name = viewModel.songName {
            songPlayer(trackName: name)
        } else {
            importDropZone
        }
    }

    /// Tap to pick a file, or drop one in (drag from Finder on Mac, or from Files on iPad).
    private var importDropZone: some View {
        Button { isImporting = true } label: {
            VStack(spacing: 8) {
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.riffPrimary)
                    .symbolEffect(.bounce, value: isDropTargeted)
                    .contentTransition(.symbolEffect(.replace))
                Text("Import a Song")
                    .font(.subheadline.weight(.semibold))
                Text("or drop an audio file here · MP3, M4A, WAV, AIFF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(Color.riffPrimary.opacity(isDropTargeted ? 0.25 : 0.08)).interactive(),
            in: RoundedRectangle(cornerRadius: CornerRadius.lg)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .strokeBorder(Color.riffPrimary.opacity(isDropTargeted ? 0.8 : 0.25),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            viewModel.importSong(from: url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .animation(.smooth(duration: 0.2), value: isDropTargeted)
        .disabled(!player.isReady)
        .accessibilityHint("Opens Files to choose a song")
    }

    private func songPlayer(trackName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                playButton(isPlaying: player.isBackingTrackPlaying, label: "song", action: viewModel.toggleSong)
                .disabled(isLoading)

                Text(trackName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Menu {
                    Button("Import Another Song", systemImage: "square.and.arrow.down") { isImporting = true }
                    Button("Remove", systemImage: "xmark", role: .destructive) {
                        player.unloadBackingTrack()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Song options")
            }

            if player.backingTrackDuration > 0 {
                TrackTimeline(
                    currentTime: player.backingTrackCurrentTime,
                    duration: player.backingTrackDuration,
                    onSeek: { player.seekBackingTrack(to: $0) }
                )
            }

            volumeSlider

            Toggle(isOn: Binding(
                get: { player.backingTrackThroughEffects },
                set: { _ in player.toggleBackingTrackThroughEffects() }
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

    // MARK: - Music App

    private var musicAppSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if music.canControlAppleMusic {
                appleMusicControls
            } else {
                appRow(name: "Apple Music", icon: "music.note", tint: .pink, url: SystemMusicService.appleMusicURL)
            }
            appRow(name: "Spotify", icon: "dot.radiowaves.left.and.right", tint: .green, url: SystemMusicService.spotifyURL)

            Label("Songs from Apple Music and Spotify keep playing while your guitar runs through RiffNode. Use headphones so the mic only hears your guitar.",
                  systemImage: "headphones")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            // Keep "now playing" current while this is on screen
            while !Task.isCancelled {
                music.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var appleMusicControls: some View {
        HStack(spacing: 10) {
            appIcon("music.note", tint: .pink)
            if music.isAuthorized {
                VStack(alignment: .leading, spacing: 1) {
                    Text(music.title ?? "Apple Music")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(music.artist ?? (music.title == nil ? "Press play to shuffle your library" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    transportButton("backward.fill", label: "Previous song", action: music.skipToPrevious)
                    transportButton(music.isPlaying ? "pause.fill" : "play.fill",
                                    label: music.isPlaying ? "Pause Apple Music" : "Play Apple Music",
                                    action: music.togglePlayback)
                    transportButton("forward.fill", label: "Next song", action: music.skipToNext)
                }
            } else if music.isDenied {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Apple Music").font(.subheadline.weight(.semibold))
                    Text("Allow access in Settings › Privacy › Media & Apple Music")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                Text("Apple Music").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Button("Connect") { Task { await music.requestAccess() } }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
    }

    private func appRow(name: String, icon: String, tint: Color, url: URL) -> some View {
        HStack(spacing: 10) {
            appIcon(icon, tint: tint)
            Text(name).font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Button("Open") { openURL(url) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityLabel("Open \(name)")
        }
    }

    private func appIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7))
    }

    private func transportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Shared

    private func playButton(isPlaying: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 40, height: 40)
            .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.2)).interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause \(label)" : "Play \(label)")
    }

    private var volumeSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { player.backingTrackVolume },
                    set: { player.setBackingTrackVolume($0) }
                ),
                in: 0...1
            )
            .accessibilityLabel("Play-along volume")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        viewModel.importSong(from: url)
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
        BackingTrackView(player: BackingTrackPlayer())
            .padding()
            .frame(width: 400)
    }
}
