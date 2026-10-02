import SwiftUI

// MARK: - Input Source Card
// One card for everything about the sound going in: where it comes from (your guitar or
// the built-in demo riff), what it looks like, and which note or chord is being played.
// Replaces the separate demo button, visualizer, mini spectrum and chord badge.

struct InputSourceCard: View {
    @Bindable var engine: AudioEngineManager
    let chordDetector: ChordDetector

    @State private var mode: VisualizerMode = .waveform

    enum VisualizerMode: CaseIterable {
        case waveform, bars, circular

        var icon: String {
            switch self {
            case .waveform: "waveform"
            case .bars: "chart.bar.fill"
            case .circular: "circle.hexagongrid.fill"
            }
        }

        var next: VisualizerMode {
            let all = Self.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    enum Source: Hashable { case guitar, demo }

    private var source: Binding<Source> {
        Binding(
            get: { engine.isDemoRiffPlaying ? .demo : .guitar },
            set: { newValue in
                if (newValue == .demo) != engine.isDemoRiffPlaying { engine.toggleDemoRiff() }
            }
        )
    }

    private var isSilent: Bool { engine.inputLevel < 0.01 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: title + source switch
            HStack {
                Picker("Source", selection: source) {
                    Label("Guitar", systemImage: "guitars").tag(Source.guitar)
                    Label("Demo riff", systemImage: "play.circle").tag(Source.demo)
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleOnly)
                .disabled(!engine.canPlayDemoRiff)
                .help("⌘D toggles the demo riff")
            }

            // Visualizer with IN / OUT meters
            HStack(spacing: 10) {
                LevelMeterView(level: engine.inputLevel, label: "IN")
                visualizer
                LevelMeterView(level: engine.outputLevel, label: "OUT")
            }
            .frame(height: 120)

            // What's being played
            HStack(spacing: 10) {
                noteBadge
                VStack(alignment: .leading, spacing: 1) {
                    Text(chordText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hasChord ? .primary : .secondary)
                        .lineLimit(1)
                    Label(sourceDetail, systemImage: engine.isDemoRiffPlaying ? "music.note" : engine.currentInputDeviceType.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Visualizer

    private var visualizer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.12))

            Group {
                switch mode {
                case .waveform: WaveformView(samples: engine.waveformSamples).padding(8)
                case .bars: BarVisualizationView(samples: engine.waveformSamples)
                case .circular: CircularVisualizationView(samples: engine.waveformSamples)
                }
            }
            .opacity(isSilent ? 0.3 : 1)

            if isSilent {
                VStack(spacing: 4) {
                    Image(systemName: engine.isRunning ? "waveform.badge.mic" : "play.circle")
                        .font(.system(size: 20))
                    Text(engine.isRunning ? "Play a note, or try the demo riff" : "Start the engine to listen")
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(8)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            // Tap to cycle the visual style
            Button {
                withAnimation(.smooth(duration: 0.2)) { mode = mode.next }
            } label: {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel("Change visualizer style")
        }
        .animation(.easeInOut(duration: 0.3), value: isSilent)
    }

    // MARK: - Note & chord

    private var hasNote: Bool { !isSilent && chordDetector.detectedNote != "—" }
    /// Low-confidence guesses flicker between chords; only name one the detector is fairly sure of.
    private var hasChord: Bool {
        !isSilent && chordDetector.confidence >= 0.3
            && chordDetector.detectedChord != "—" && !chordDetector.detectedChord.isEmpty
    }

    private var noteBadge: some View {
        Text(hasNote ? chordDetector.detectedNote : "–")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(hasNote ? (chordDetector.isInTune ? Color.green : Color.primary) : Color.secondary)
            .contentTransition(.numericText())
            .frame(width: 44, height: 44)
            .glassEffect(.regular.tint((hasNote && chordDetector.isInTune ? Color.green : Color.riffPrimary).opacity(0.12)), in: Circle())
            .animation(.snappy, value: chordDetector.detectedNote)
            .accessibilityLabel(hasNote ? "Note \(chordDetector.detectedNote)" : "No note")
    }

    private var chordText: String {
        hasChord ? chordDetector.detectedChord : "Listening for a chord…"
    }

    private var sourceDetail: String {
        engine.isDemoRiffPlaying ? "Demo riff through your pedals" : engine.currentInputDeviceName
    }
}
