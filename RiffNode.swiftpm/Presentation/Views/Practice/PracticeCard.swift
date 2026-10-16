import SwiftUI

// MARK: - Practice Card
// A looper with one footswitch (Record → Play → Overdub → Play) and a metronome that can
// match the groove – the two tools every practice pedalboard ends up with.

struct PracticeCard: View {
    let looper: any LooperControlling
    let metronome: any MetronomeControlling
    /// The groove's tempo, so the metronome can match it.
    let grooveTempo: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Practice", systemImage: "repeat.circle")
                .font(.headline)

            looperRow
            Divider()
            metronomeRow
        }
        .padding(Spacing.md)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CornerRadius.xl))
    }

    // MARK: Looper

    private var footswitchColor: Color {
        switch looper.state {
        case .recording: .red
        case .overdubbing: .orange
        case .playing: .green
        case .empty, .stopped: .secondary
        }
    }

    private var looperRow: some View {
        HStack(spacing: 12) {
            Button(action: looper.press) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle()
                        .strokeBorder(footswitchColor, lineWidth: looper.state == .empty || looper.state == .stopped ? 2 : 4)
                    Image(systemName: looper.state == .recording || looper.state == .overdubbing ? "record.circle" : "repeat")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(looper.state == .recording ? Color.red : Color(white: 0.2))
                        .symbolEffect(.pulse, isActive: looper.state == .recording || looper.state == .overdubbing)
                }
                .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .disabled(!looper.isReady)
            .accessibilityLabel("Looper footswitch: \(looper.state.nextActionTitle)")

            VStack(alignment: .leading, spacing: 2) {
                Text("Looper").font(.subheadline.weight(.semibold))
                Text(looperCaption)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                smallButton("stop.fill", label: "Stop loop", action: looper.stop)
                    .disabled(looper.state == .empty || looper.state == .stopped)
                smallButton("arrow.uturn.backward", label: "Undo last overdub", action: looper.undo)
                    .disabled(!looper.canUndo)
                smallButton("trash", label: "Clear loop", action: looper.clear)
                    .disabled(looper.state == .empty)
            }
        }
    }

    private var looperCaption: String {
        switch looper.state {
        case .empty: "Tap to record a loop"
        case .recording: "Recording… tap to loop it"
        case .playing: String(format: "%.1f s loop · tap to overdub", looper.loopDuration)
        case .overdubbing: "Overdubbing… tap to keep it"
        case .stopped: String(format: "%.1f s loop · tap to play", looper.loopDuration)
        }
    }

    // MARK: Metronome

    private var metronomeRow: some View {
        HStack(spacing: 12) {
            Button(action: metronome.toggle) {
                Image(systemName: metronome.isPlaying ? "pause.fill" : "metronome.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 52, height: 40)
                    .glassEffect(.regular.tint(Color.riffPrimary.opacity(metronome.isPlaying ? 0.35 : 0.12)).interactive(), in: Capsule())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!metronome.isReady)
            .accessibilityLabel(metronome.isPlaying ? "Stop metronome" : "Start metronome")

            VStack(alignment: .leading, spacing: 4) {
                Text("Metronome").font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    smallButton("minus", label: "Slower") { metronome.setTempo(metronome.beatsPerMinute - 2) }
                    Text("\(Int(metronome.beatsPerMinute)) BPM")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 58)
                    smallButton("plus", label: "Faster") { metronome.setTempo(metronome.beatsPerMinute + 2) }
                }
            }

            Spacer(minLength: 0)

            Button("Match groove") { metronome.setTempo(grooveTempo) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.glass)
                .controlSize(.small)
        }
    }

    private func smallButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 26, height: 26)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
