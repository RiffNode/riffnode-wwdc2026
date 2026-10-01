import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backing Track View

struct BackingTrackView: View {

    @Bindable var engine: AudioEngineManager

    @State private var isImporting = false
    @State private var loadedTrackName: String?
    @State private var isLoading = false

    var body: some View {
        GlassCard(cornerRadius: 16) {
            VStack(spacing: 14) {
                header
                if let name = loadedTrackName {
                    nowPlayingContent(trackName: name)
                } else {
                    emptyState
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .foregroundStyle(.secondary)
                Text("Backing Track")
                    .font(.headline)
            }
            Spacer()
            Button { isImporting = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: loadedTrackName != nil ? "arrow.triangle.2.circlepath" : "plus")
                    Text(loadedTrackName != nil ? "Change" : "Import")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.vertical, 6)
                .padding(.horizontal, 13)
                .glassEffect(.regular, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Now Playing

    private func nowPlayingContent(trackName: String) -> some View {
        VStack(spacing: 14) {
            // Track identity row
            HStack(spacing: 14) {
                trackArtwork
                VStack(alignment: .leading, spacing: 5) {
                    Text(formatTrackName(trackName))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if engine.isBackingTrackPlaying {
                            PlayingBarsIndicator()
                        } else {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Text(engine.isBackingTrackPlaying ? "Playing" : "Paused")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(engine.isBackingTrackPlaying ? .green : .secondary)
                    }
                    Text(fileFormat(trackName))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatTime(engine.backingTrackCurrentTime))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(formatTime(engine.backingTrackDuration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            // ── Through-Effects Toggle ──────────────────────────────
            ThroughEffectsToggle(
                isEnabled: engine.backingTrackThroughEffects,
                onToggle: { engine.toggleBackingTrackThroughEffects() }
            )

            // Educational hint when mode is active
            if engine.backingTrackThroughEffects {
                ThroughEffectsHint(effectsChain: engine.effectsChain)
            }

            // Timeline scrubber
            if engine.backingTrackDuration > 0 {
                TrackTimeline(
                    currentTime: engine.backingTrackCurrentTime,
                    duration: engine.backingTrackDuration,
                    onSeek: { engine.seekBackingTrack(to: $0) }
                )
            }

            // Transport controls
            TransportRow(
                isPlaying: engine.isBackingTrackPlaying,
                isLoading: isLoading,
                volume: Binding(
                    get: { engine.backingTrackVolume },
                    set: { engine.setBackingTrackVolume($0) }
                ),
                onSkipBack:  { engine.seekBackingTrack(to: max(0, engine.backingTrackCurrentTime - 15)) },
                onPlayPause: { engine.isBackingTrackPlaying ? engine.stopBackingTrack() : engine.playBackingTrack() },
                onSkipFwd:   { engine.seekBackingTrack(to: min(engine.backingTrackDuration, engine.backingTrackCurrentTime + 15)) }
            )
        }
    }

    // MARK: - Track Artwork Thumbnail

    private var trackArtwork: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.primary)
            } else {
                // Animated bars when playing, static icon when paused
                if engine.isBackingTrackPlaying {
                    MusicBarsArtwork()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 64, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.riffPrimary.opacity(0.15), Color.purple.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Button { isImporting = true } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.riffPrimary.opacity(0.1))
                        .frame(width: 52, height: 52)
                    Image(systemName: "plus.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.riffPrimary)
                }
                Text("Import a backing track")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("MP3, WAV, or AIFF")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatTrackName(_ name: String) -> String {
        var n = name
        if let dot = n.lastIndex(of: ".") { n = String(n[..<dot]) }
        return n.count > 28 ? String(n.prefix(25)) + "..." : n
    }

    private func fileFormat(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "Audio" : ext
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

// MARK: - Through Effects Toggle

struct ThroughEffectsToggle: View {
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isEnabled
                              ? LinearGradient(colors: [Color.orange, Color.red],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: isEnabled ? "guitars.fill" : "guitars")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isEnabled ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Play Through Pedalboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isEnabled ? .primary : .secondary)
                    Text(isEnabled ? "Music is going through your effects chain" : "Hear how effects shape real music")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Toggle pill
                ZStack {
                    Capsule()
                        .fill(isEnabled ? Color.orange.opacity(0.8) : Color.white.opacity(0.15))
                        .frame(width: 40, height: 24)
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .offset(x: isEnabled ? 8 : -8)
                        .shadow(radius: 2)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(isEnabled ? .regular.tint(.orange.opacity(0.15)) : .regular,
                         in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Through Effects Hint

struct ThroughEffectsHint: View {
    let effectsChain: [EffectNode]

    private var activeEffects: [EffectNode] { effectsChain.filter { $0.isEnabled } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Active effects chips
            if activeEffects.isEmpty {
                Label("Enable pedals on the right to hear them on the music", systemImage: "lightbulb.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("Active:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(activeEffects.prefix(4)) { effect in
                        Text(effect.type.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .glassEffect(.regular.tint(.orange.opacity(0.2)), in: Capsule())
                    }
                    if activeEffects.count > 4 {
                        Text("+\(activeEffects.count - 4)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Text("Try toggling the Parametric EQ to hear how cutting or boosting frequencies changes the mix.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.orange.opacity(0.08)), in: RoundedRectangle(cornerRadius: 10))
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

// MARK: - Transport Row

struct TransportRow: View {
    let isPlaying: Bool
    let isLoading: Bool
    @Binding var volume: Float
    let onSkipBack: () -> Void
    let onPlayPause: () -> Void
    let onSkipFwd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Buttons
            HStack(spacing: 0) {
                Spacer()

                // Skip back 15s
                Button(action: onSkipBack) {
                    VStack(spacing: 2) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20, weight: .medium))
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                // Play / Pause (larger, primary CTA)
                Button(action: onPlayPause) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.riffPrimary.opacity(0.8), Color.riffPrimary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: Color.riffPrimary.opacity(0.4), radius: 8, y: 4)
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: isPlaying ? 0 : 2) // optical center for play icon
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Skip forward 15s
                Button(action: onSkipFwd) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()
            }

            // Volume
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Slider(value: $volume, in: 0...1)
                    .tint(Color.riffPrimary)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
        }
    }
}

// MARK: - Animated Music Bars (artwork when playing)

struct MusicBarsArtwork: View {
    private static let heights: [[CGFloat]] = [
        [14, 28, 20, 34, 18, 26],
        [22, 16, 30, 18, 32, 14],
        [18, 30, 16, 28, 22, 32]
    ]
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.riffPrimary.opacity(0.9), Color.purple.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 5, height: Self.heights[phase % 3][i])
                    .animation(
                        .easeInOut(duration: 0.25 + Double(i) * 0.05)
                            .repeatForever(autoreverses: true),
                        value: phase
                    )
            }
        }
        .onAppear { phase = 1 }
    }
}

// MARK: - Playing Bars Indicator (small, in track info row)

struct PlayingBarsIndicator: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Color.green)
                    .frame(width: 2.5, height: phase ? CGFloat([6, 10, 8, 12][i]) : CGFloat([10, 6, 12, 8][i]))
                    .animation(
                        .easeInOut(duration: 0.3 + Double(i) * 0.07)
                            .repeatForever(autoreverses: true),
                        value: phase
                    )
            }
        }
        .frame(height: 14)
        .onAppear { phase = true }
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
