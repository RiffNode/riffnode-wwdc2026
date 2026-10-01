import SwiftUI

// MARK: - Glass Top Bar View

struct GlassTopBarView: View {
    @Bindable var engine: AudioEngineManager
    let chordDetector: ChordDetector?
    @Binding var showingSettings: Bool
    @Binding var showingPresets: Bool

    init(engine: AudioEngineManager, chordDetector: ChordDetector? = nil, showingSettings: Binding<Bool>, showingPresets: Binding<Bool>) {
        self.engine = engine
        self.chordDetector = chordDetector
        self._showingSettings = showingSettings
        self._showingPresets = showingPresets
    }

    var body: some View {
        // One container wraps everything so all toolbar pills / buttons
        // fuse into a single liquid glass bar.
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 16) {
                // Logo with custom RiffNode icon
                HStack(spacing: 12) {
                    Image("RiffNodeLogo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .foregroundStyle(Color.riffPrimary)

                    Text("RiffNode")
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Audio Input Device indicator
                GlassAudioInputBadge(
                    deviceName: engine.currentInputDeviceName,
                    deviceType: engine.currentInputDeviceType,
                    onRefresh: {
                        engine.refreshInputDevices()
                    }
                )

                // Presets button
                Button {
                    showingPresets = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill")
                        Text("Presets")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)

                // Engine status lives in the notch; the play/stop tint mirrors it here.
                // Play/Stop + Settings – already inside the outer container
                // so they fuse with the buttons next to them
                GlassIconButton(
                    icon: engine.isRunning ? "stop.fill" : "play.fill",
                    tint: engine.isRunning ? .red : .green
                ) {
                    if engine.isRunning {
                        engine.stop()
                    } else {
                        try? engine.start()
                    }
                }
                .accessibilityLabel(engine.isRunning ? "Stop engine" : "Start engine")

                GlassIconButton(icon: "gear", tint: .primary) {
                    showingSettings = true
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            // The outer glass shape covers the whole bar
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Glass Audio Input Badge

struct GlassAudioInputBadge: View {
    let deviceName: String
    let deviceType: AudioInputDeviceType
    let onRefresh: () -> Void

    var body: some View {
        Button(action: onRefresh) {
            HStack(spacing: 8) {
                // Device type icon
                ZStack {
                    Circle()
                        .fill(deviceType.color.opacity(0.2))
                        .frame(width: 28, height: 28)

                    Image(systemName: deviceType.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(deviceType.color)
                }

                // Device info
                VStack(alignment: .leading, spacing: 1) {
                    Text(deviceType.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(formatDeviceName(deviceName))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                // Signal indicator
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundStyle(deviceType == .none ? Color.secondary : Color.green)
                    .symbolEffect(.pulse, options: .repeating, value: deviceType != .none)
            }
        }
        .buttonStyle(.plain)
        .glassPill()
        .help("Click to refresh audio input devices")
    }

    private func formatDeviceName(_ name: String) -> String {
        var displayName = name
            .replacingOccurrences(of: "MacBook Pro Microphone", with: "MacBook Pro Mic")
            .replacingOccurrences(of: "Built-in Microphone", with: "Built-in Mic")
            .replacingOccurrences(of: "USB Audio Device", with: "USB Audio")

        if displayName.count > 22 {
            displayName = String(displayName.prefix(20)) + "..."
        }
        return displayName
    }
}
