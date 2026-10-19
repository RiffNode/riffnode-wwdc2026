import SwiftUI

// MARK: - EQ Controls

struct GlassEQHeader: View {
    @Binding var isAnalyzerActive: Bool
    @Binding var bands: [EQBand]
    let onReset: () -> Void
    @State private var showPresets = false

    var body: some View {
        HStack {
            // EQ Icon and title
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.primary)
                Text("Parametric EQ")
                    .font(.headline)
            }

            Spacer()

            // Controls
            HStack(spacing: 8) {
                Button {
                    showPresets.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(.caption2))
                        Text("Presets")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPresets) {
                    GlassEQPresetPicker(bands: $bands, isPresented: $showPresets)
                }

                // Analyzer toggle
                Button {
                    isAnalyzerActive.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isAnalyzerActive ? Color.white : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text("Analyzer")
                    }
                }
                .buttonStyle(GlassPillStyle(isSelected: isAnalyzerActive, tint: .riffPrimary))

                // Reset button
                Button(action: onReset) {
                    Text("Reset")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct GlassEQPresetPicker: View {
    @Binding var bands: [EQBand]
    @Binding var isPresented: Bool
    var onPresetApplied: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("EQ Presets")
                    .font(.headline)
                Spacer()
            }
            .padding()

            // Preset list – each item is its own glass pill so they fuse
            ScrollView {
                GlassEffectContainer(spacing: 8) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(EQPreset.presets) { preset in
                            Button {
                                withAnimation(.spring(duration: 0.3)) {
                                    var newBands = bands
                                    preset.applyTo(&newBands)
                                    bands = newBands
                                }
                                onPresetApplied?()
                                isPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: preset.icon)
                                        .font(.system(.subheadline))
                                        .foregroundStyle(.primary)
                                        .frame(width: 24)

                                    Text(preset.name)
                                        .font(.system(.caption, weight: .medium))
                                        .foregroundStyle(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 280, height: 400)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct GlassEQBandControls: View {
    @Binding var band: EQBand

    var body: some View {
        GlassCard(cornerRadius: 12) {
            VStack(spacing: 12) {
                // Type selector – each type pill gets glass; selected one is tinted
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(EQBand.BandType.allCases, id: \.self) { type in
                            Button {
                                band.type = type
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: type.icon)
                                        .font(.system(.caption))
                                    Text(type.shortName)
                                        .font(.system(size: 8, weight: .medium))
                                }
                                .frame(width: 46, height: 32)
                                .foregroundStyle(band.type == type ? .white : .secondary)
                                .glassEffect(
                                    band.type == type
                                        ? .regular.tint(type.color)
                                        : .regular,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Value controls
                HStack(spacing: 20) {
                    // Frequency
                    VStack(spacing: 4) {
                        Text("FREQ")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Text(formatFrequency(band.frequency))
                            .font(.system(.callout, weight: .bold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 70)

                    // Gain with +/- buttons
                    VStack(spacing: 4) {
                        Text("GAIN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                band.gain = max(-24, band.gain - 1)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(.caption, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)

                            Text(String(format: "%+.1f", band.gain))
                                .font(.system(.callout, weight: .bold).monospacedDigit())
                                .foregroundStyle(.primary)
                                .frame(width: 50)

                            Button {
                                band.gain = min(24, band.gain + 1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(.caption, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }

                    // Q with +/- buttons
                    VStack(spacing: 4) {
                        Text("Q")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                band.q = max(0.1, band.q - 0.1)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(.caption, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)

                            Text(String(format: "%.1f", band.q))
                                .font(.system(.callout, weight: .bold).monospacedDigit())
                                .foregroundStyle(.primary)
                                .frame(width: 36)

                            Button {
                                band.q = min(10, band.q + 0.1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(.caption, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.2fk", freq / 1000)
        }
        return String(format: "%.0f", freq)
    }
}
