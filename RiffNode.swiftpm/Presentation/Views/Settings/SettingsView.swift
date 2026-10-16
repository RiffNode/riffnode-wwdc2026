import SwiftUI
#if os(iOS) && !targetEnvironment(macCatalyst)
import CoreAudioKit
#endif

// MARK: - Settings View
// Apple-style settings with proper section grouping and professional appearance

struct SettingsView: View {
    let engine: any StatusEngine
    var footswitch: (any FootswitchListening)?
    @Environment(\.dismiss) private var dismiss
    @State private var showingBluetoothMIDI = false

    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveBackground()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Audio Engine Section
                        SettingsSection(title: "Audio Engine") {
                            SettingsRow(
                                icon: "waveform.circle.fill",
                                iconColor: engine.isRunning ? .green : .red,
                                title: "Engine Status",
                                subtitle: engine.isRunning ? "Audio processing active" : "Engine stopped"
                            ) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(engine.isRunning ? Color.green : Color.red)
                                        .frame(width: 10, height: 10)
                                    Text(engine.isRunning ? "Running" : "Stopped")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(engine.isRunning ? .green : .red)
                                }
                            }

                            GlassDivider()

                            SettingsRow(
                                icon: "mic.fill",
                                iconColor: engine.hasPermission ? .green : .orange,
                                title: "Microphone Access",
                                subtitle: engine.hasPermission ? "Permission granted" : "Permission required"
                            ) {
                                Image(systemName: engine.hasPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(engine.hasPermission ? .green : .orange)
                            }
                        }

                        // Latency – what you feel when you pick a note
                        SettingsSection(title: "Latency") {
                            SettingsRow(
                                icon: "timer",
                                iconColor: engine.roundTripLatencyMs < 15 ? .green : (engine.roundTripLatencyMs < 30 ? .orange : .red),
                                title: String(format: "%.1f ms from string to ear", engine.roundTripLatencyMs),
                                subtitle: String(format: "Buffer %.1f ms · under 10 ms feels instant, over 30 ms feels late", engine.bufferDurationMs)
                            ) {
                                Button { engine.refreshLatency() } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.glass)
                                .accessibilityLabel("Measure again")
                            }
                            if engine.isBluetoothOutput {
                                GlassDivider()
                                SettingsRow(
                                    icon: "exclamationmark.triangle.fill",
                                    iconColor: .orange,
                                    title: "Bluetooth headphones",
                                    subtitle: "They add 100–200 ms. Use wired headphones or an audio interface to play live."
                                ) { EmptyView() }
                            }
                        }

                        // MIDI foot controllers
                        if let footswitch {
                            SettingsSection(title: "MIDI Footswitch") {
                                SettingsRow(
                                    icon: "pianokeys",
                                    iconColor: footswitch.sourceNames.isEmpty ? .secondary : .green,
                                    title: footswitch.sourceNames.isEmpty ? "No MIDI device" : footswitch.sourceNames.joined(separator: ", "),
                                    subtitle: footswitch.lastMessage.map { "Last: \($0)" } ?? "Connect a USB or Bluetooth MIDI pedal"
                                ) {
                                    #if os(iOS) && !targetEnvironment(macCatalyst)
                                    Button("Bluetooth…") { showingBluetoothMIDI = true }
                                        .buttonStyle(.glass)
                                    #else
                                    EmptyView()
                                    #endif
                                }
                                GlassDivider()
                                VStack(alignment: .leading, spacing: 4) {
                                    SettingsInfoRow(label: "Program Change n", value: "Preset n")
                                    SettingsInfoRow(label: "CC 80 / CC 81", value: "Next / previous preset")
                                    SettingsInfoRow(label: "CC 82", value: "Looper footswitch")
                                    SettingsInfoRow(label: "CC 83", value: "Mute while tuning")
                                }
                            }
                        }

                        // Audio Input Section
                        SettingsSection(title: "Audio Input") {
                            SettingsRow(
                                icon: engine.currentInputDeviceType.icon,
                                iconColor: engine.currentInputDeviceType.color,
                                title: "Input Device",
                                subtitle: engine.currentInputDeviceName
                            ) {
                                Button {
                                    engine.refreshInputDevices()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            GlassDivider()

                            SettingsRow(
                                icon: "slider.horizontal.3",
                                iconColor: .purple,
                                title: "Input Level",
                                subtitle: "Current signal strength"
                            ) {
                                // Mini level meter
                                HStack(spacing: 2) {
                                    ForEach(0..<8, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(
                                                i < Int(AudioMeter.normalized(engine.inputLevel) * 8)
                                                    ? (i < 6 ? Color.green : Color.orange)
                                                    : Color.primary.opacity(0.15)
                                            )
                                            .frame(width: 4, height: 16)
                                    }
                                }
                            }
                        }

                        // Effects Chain Section
                        SettingsSection(title: "Effects Chain") {
                            SettingsRow(
                                icon: "square.stack.3d.up.fill",
                                iconColor: .riffPrimary,
                                title: "Active Effects",
                                subtitle: "\(engine.effectsChain.filter { $0.isEnabled }.count) of \(engine.effectsChain.count) enabled"
                            ) {
                                Text("\(engine.effectsChain.filter { $0.isEnabled }.count)")
                                    .font(.title2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Color.riffPrimary)
                            }

                            GlassDivider()

                            SettingsRow(
                                icon: "arrow.counterclockwise",
                                iconColor: .orange,
                                title: "Reset Effects",
                                subtitle: "Restore default chain"
                            ) {
                                Button("Reset") {
                                    showResetConfirmation = true
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 14)
                                .glassEffect(.regular.tint(.orange.opacity(0.15)), in: Capsule())
                                .buttonStyle(.plain)
                            }
                        }

                        // About Section
                        SettingsSection(title: "About") {
                            // App Info Header
                            HStack(spacing: 16) {
                                Image("RiffNodeLogo")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                                    .foregroundStyle(Color.riffPrimary)
                                    .padding(12)
                                    .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.12)), in: RoundedRectangle(cornerRadius: 16))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("RiffNode")
                                        .font(.title2.bold())

                                    Text("Version 1.0")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Text("Swift Student Challenge 2026")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()
                            }
                            .padding(.bottom, Spacing.sm)

                            GlassDivider()

                            SettingsInfoRow(label: "Built with", value: "Swift 6 & SwiftUI")
                            GlassDivider()
                            SettingsInfoRow(label: "UI Framework", value: "iOS 26 Liquid Glass")
                            GlassDivider()
                            SettingsInfoRow(label: "Audio Engine", value: "AVAudioEngine")
                            GlassDivider()
                            SettingsInfoRow(label: "Architecture", value: "Clean Architecture")
                        }

                        // Description
                        VStack(spacing: Spacing.sm) {
                            Text("Guitar Effects Playground")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("RiffNode is a visual guitar effects playground. Connect your guitar through an audio interface and explore a world of effects with AI-powered tone assistance, real-time spectrum analysis, and hands-free gesture control.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, Spacing.lg)
                    }
                    .padding(.vertical, Spacing.md)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset Effects Chain?", isPresented: $showResetConfirmation) {
                Button("Reset to Default", role: .destructive) {
                    engine.resetEffectsToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This restores the six default pedals, turns them off, and resets the pedal settings and EQ.")
            }
            #if os(iOS) && !targetEnvironment(macCatalyst)
            .sheet(isPresented: $showingBluetoothMIDI) {
                NavigationStack {
                    BluetoothMIDIPairing()
                        .navigationTitle("Bluetooth MIDI")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingBluetoothMIDI = false }
                            }
                        }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(width: 450, height: 650)
        #endif
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.lg + 4)

            VStack(spacing: 0) {
                content
            }
            .padding(Spacing.md)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, Spacing.lg)
        }
    }
}

// MARK: - Settings Row

private struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            // Labels
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Trailing content
            trailing
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Info Row

private struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
    }
}


#if os(iOS) && !targetEnvironment(macCatalyst)
// MARK: - Bluetooth MIDI Pairing

/// Apple's Bluetooth MIDI pairing screen – pair a wireless foot controller without leaving RiffNode.
private struct BluetoothMIDIPairing: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController { CABTMIDICentralViewController() }
    func updateUIViewController(_ controller: CABTMIDICentralViewController, context: Context) {}
}
#endif
