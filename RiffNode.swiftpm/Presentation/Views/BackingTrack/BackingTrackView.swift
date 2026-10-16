import SwiftUI
import UniformTypeIdentifiers

// MARK: - Play Along Card
// Something to play over, three ways:
//  • Groove – a built-in drums-and-bass loop in any minor key and tempo, with the chord
//    you're on highlighted and the scale to solo with.
//  • Song – your own file, optionally run through your pedals.
//  • Music app – Apple Music (controlled from here on iPad) or Spotify, playing alongside.

struct BackingTrackView: View {

    @Bindable var engine: AudioEngineManager

    enum Mode: String, CaseIterable, Identifiable {
        case groove = "Groove", song = "Song", musicApp = "Music app"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .groove
    @State private var music = SystemMusicService()
    @State private var isImporting = false
    @State private var isLoading = false
    /// Name shown while an imported file is still loading.
    @State private var pendingTrackName: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker("Play along with", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
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
        .onChange(of: mode) { _, newMode in
            // One thing at a time: leaving a mode stops what it was playing
            switch newMode {
            case .groove where !engine.isBuiltInJamTrack, .song where engine.isBuiltInJamTrack, .musicApp:
                engine.stopBackingTrack()
            default: break
            }
        }
        .animation(.smooth(duration: 0.25), value: mode)
        .animation(.smooth(duration: 0.25), value: engine.backingTrackName)
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

    private var isGroovePlaying: Bool { engine.isBuiltInJamTrack && engine.isBackingTrackPlaying }

    /// The bar (0–3) the groove is on, so the matching chord lights up.
    private var currentBar: Int? {
        guard isGroovePlaying else { return nil }
        let barSeconds = 240 / engine.grooveTempo
        return Int(engine.backingTrackCurrentTime / barSeconds) % 4
    }

    private var grooveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                playButton(isPlaying: isGroovePlaying, label: "groove") {
                    if isGroovePlaying { engine.stopBackingTrack() } else { playGroove() }
                }
                .disabled(!engine.canPlayDemoRiff)

                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        ForEach(JamTrackSynthesizer.keys, id: \.transpose) { key in
                            Button(key.name) { restartGroove(transpose: key.transpose) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(JamTrackSynthesizer.keyName(transpose: engine.grooveTranspose))
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        tempoButton("minus", by: -4)
                        Text("\(Int(engine.grooveTempo)) BPM")
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
                ForEach(Array(JamTrackSynthesizer.chords(transpose: engine.grooveTranspose).enumerated()), id: \.offset) { index, chord in
                    let isCurrent = currentBar == index
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

            Label("Solo with \(JamTrackSynthesizer.scale(transpose: engine.grooveTranspose))", systemImage: "hand.point.up.left")
                .font(.caption)
                .foregroundStyle(.secondary)

            if engine.isBuiltInJamTrack { volumeSlider }
        }
    }

    private func tempoButton(_ symbol: String, by step: Double) -> some View {
        Button {
            let tempo = min(max(engine.grooveTempo + step, JamTrackSynthesizer.tempoRange.lowerBound),
                            JamTrackSynthesizer.tempoRange.upperBound)
            restartGroove(tempo: tempo)
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step > 0 ? "Faster" : "Slower")
    }

    private func playGroove() {
        guard (try? engine.loadBuiltInJamTrack()) != nil else { return }
        engine.playBackingTrack()
    }

    /// Applies a new key or tempo; keeps playing if it was playing.
    private func restartGroove(tempo: Double? = nil, transpose: Int? = nil) {
        let wasPlaying = isGroovePlaying
        guard engine.canPlayDemoRiff, (try? engine.loadBuiltInJamTrack(tempo: tempo, transpose: transpose)) != nil else { return }
        if wasPlaying { engine.playBackingTrack() }
    }

    // MARK: - Song

    @ViewBuilder
    private var songSection: some View {
        if let name = (engine.isBuiltInJamTrack ? nil : engine.backingTrackName) ?? pendingTrackName {
            songPlayer(trackName: name)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import a song from Files – MP3, M4A, WAV or AIFF – and play over it. Your pedals can process it too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Import a Song", systemImage: "square.and.arrow.down") { isImporting = true }
                    .buttonStyle(.glassProminent)
                    .tint(.riffPrimary)
                    .controlSize(.small)
                    .disabled(!engine.canPlayDemoRiff)
            }
        }
    }

    private func songPlayer(trackName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                playButton(isPlaying: engine.isBackingTrackPlaying, label: "song") {
                    engine.isBackingTrackPlaying ? engine.stopBackingTrack() : engine.playBackingTrack()
                }
                .disabled(isLoading)

                Text(trackName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Menu {
                    Button("Import Another Song", systemImage: "square.and.arrow.down") { isImporting = true }
                    Button("Remove", systemImage: "xmark", role: .destructive) {
                        engine.unloadBackingTrack()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Song options")
            }

            if engine.backingTrackDuration > 0 {
                TrackTimeline(
                    currentTime: engine.backingTrackCurrentTime,
                    duration: engine.backingTrackDuration,
                    onSeek: { engine.seekBackingTrack(to: $0) }
                )
            }

            volumeSlider

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
                    get: { engine.backingTrackVolume },
                    set: { engine.setBackingTrackVolume($0) }
                ),
                in: 0...1
            )
            .accessibilityLabel("Play-along volume")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isLoading = true
        pendingTrackName = url.deletingPathExtension().lastPathComponent
        Task { @MainActor in
            let accessing = url.startAccessingSecurityScopedResource()
            try? await engine.loadBackingTrack(url: url)
            if accessing { url.stopAccessingSecurityScopedResource() }
            isLoading = false
            pendingTrackName = nil
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
