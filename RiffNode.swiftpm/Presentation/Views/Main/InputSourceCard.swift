import SwiftUI

// MARK: - Input Source Card
// Everything about the sound going in: where it comes from (your guitar or the built-in demo
// riff), whether it's in tune, which chord you're holding, and how loud it is in and out.
// What the pedals do to the signal is shown in the Signal Lab, next to the pedals.

struct InputSourceCard: View {
    let engine: any InputEngine
    let chordDetector: any ChordDetecting

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
        VStack(alignment: .leading, spacing: 14) {
            // Header: title + source switch
            HStack {
                Label("Input", systemImage: "cable.connector")
                    .font(.headline)
                Spacer()
                Picker("Source", selection: source) {
                    Text("Guitar").tag(Source.guitar)
                    Text("Demo riff").tag(Source.demo)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(!engine.canPlayDemoRiff)
                .help("⌘D toggles the demo riff")
            }

            tuner

            // Chord and where the sound comes from
            HStack(spacing: 8) {
                Image(systemName: "pianokeys")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hasChord ? chordDetector.detectedChord : "No chord yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hasChord ? .primary : .secondary)
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                    Label(sourceDetail, systemImage: engine.isDemoRiffPlaying ? "music.note" : engine.currentInputDeviceType.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .animation(.smooth(duration: 0.2), value: chordDetector.detectedChord)

            // Real levels: what comes in, and what leaves after the pedals
            VStack(spacing: 6) {
                LevelBar(label: "IN", level: engine.inputLevel)
                LevelBar(label: "OUT", level: engine.outputLevel)
            }
        }
        .padding(Spacing.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CornerRadius.xl))
    }

    // MARK: - Tuner

    private var hasNote: Bool { !isSilent && chordDetector.detectedNote != "—" }
    /// Low-confidence guesses flicker between chords; only name one the detector is fairly sure of.
    private var hasChord: Bool {
        !isSilent && chordDetector.confidence >= 0.3
            && chordDetector.detectedChord != "—" && !chordDetector.detectedChord.isEmpty
            && !chordDetector.detectedChord.hasSuffix("note")   // a single note is the tuner's job
    }

    private var tuneColor: Color {
        guard hasNote else { return .secondary }
        return chordDetector.isInTune ? .green : (abs(chordDetector.centsDeviation) < 20 ? .yellow : .orange)
    }

    private var tuner: some View {
        HStack(spacing: 14) {
            Text(hasNote ? chordDetector.detectedNote : "–")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(hasNote ? tuneColor : .secondary)
                .contentTransition(.numericText())
                .frame(width: 58, height: 58)
                .glassEffect(.regular.tint(tuneColor.opacity(hasNote ? 0.18 : 0.05)), in: Circle())
                .animation(.snappy, value: chordDetector.detectedNote)

            VStack(alignment: .leading, spacing: 6) {
                CentsBar(cents: hasNote ? Double(chordDetector.centsDeviation) : 0, isActive: hasNote, color: tuneColor)
                    .frame(height: 18)
                HStack(spacing: 8) {
                    Text(tunerCaption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(hasNote ? tuneColor : .secondary)
                        .contentTransition(.opacity)
                    Spacer(minLength: 0)
                    // Like a tuner pedal: silence the amp while you tune
                    Button {
                        engine.isTunerMuted.toggle()
                    } label: {
                        Label(engine.isTunerMuted ? "Muted" : "Mute", systemImage: engine.isTunerMuted ? "speaker.slash.fill" : "speaker.wave.2")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(engine.isTunerMuted ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Silences the output while you tune; the tuner keeps listening")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasNote ? "Tuner: \(chordDetector.detectedNote), \(tunerCaption)" : "Tuner: no note")
    }

    private var tunerCaption: String {
        guard hasNote else {
            return engine.isRunning ? "Play a single string to tune" : "Start the engine to listen"
        }
        let cents = Int(chordDetector.centsDeviation.rounded())
        if chordDetector.isInTune { return "In tune" }
        return cents < 0 ? "\(-cents) cents flat – tune up" : "\(cents) cents sharp – tune down"
    }

    private var sourceDetail: String {
        engine.isDemoRiffPlaying ? "Demo riff through your pedals" : engine.currentInputDeviceName
    }
}

// MARK: - Cents Bar

/// −50…+50 cents, with the in-tune zone in the middle.
private struct CentsBar: View {
    let cents: Double
    let isActive: Bool
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = width / 2 + CGFloat(max(-50, min(50, cents)) / 50) * (width / 2 - 3)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                Capsule().fill(Color.green.opacity(0.35))
                    .frame(width: width * 0.1, height: 6)
                    .offset(x: width * 0.45)
                Rectangle().fill(Color.secondary.opacity(0.5))
                    .frame(width: 1.5, height: geo.size.height)
                    .offset(x: width / 2)
                Capsule().fill(isActive ? color : Color.secondary.opacity(0.3))
                    .frame(width: 5, height: geo.size.height)
                    .offset(x: x - 2.5)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: cents)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Level Bar

private struct LevelBar: View {
    let label: String
    let level: Float

    /// Levels arrive as RMS × 5; meters read in decibels (−60…0 dBFS) like a real mixer,
    /// so a normal signal sits in the green and only real peaks reach the red.
    private var meter: Float {
        let db = 20 * log10(max(level / 5, 1e-6))
        return min(max((db + 60) / 60, 0), 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .red],
                                             startPoint: .leading, endPoint: .trailing))
                        .mask(alignment: .leading) {
                            Capsule().frame(width: geo.size.width * CGFloat(meter))
                        }
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.05), value: level)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label) level")
        .accessibilityValue("\(Int(meter * 100)) percent")
    }
}
