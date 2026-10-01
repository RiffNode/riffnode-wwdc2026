import SwiftUI

// MARK: - AI Tools View

struct AIToolsView: View {
    let fftAnalyzer: FFTAnalyzer
    let chordDetector: ChordDetector
    @Bindable var engine: AudioEngineManager

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 20) {
                VStack(spacing: Spacing.lg) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.title2)
                                    .foregroundStyle(.cyan)

                                Text("Audio Analysis")
                                    .font(.title2.bold())
                            }

                            Text("Real-time frequency and pitch analysis powered by Accelerate framework")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .glassEffect(.regular.tint(.cyan.opacity(0.1)), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, Spacing.lg)

                    // Spectrum Analyzer (FFT)
                    GlassCard(cornerRadius: CornerRadius.lg) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Real-Time Spectrum Analysis", systemImage: "waveform.path.ecg")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Fast Fourier Transform (FFT) decomposes your audio into frequency components")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            FFTSpectrumView(analyzer: fftAnalyzer)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)

                    // Chord Detection
                    GlassCard(cornerRadius: CornerRadius.lg) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("AI Chord Detection", systemImage: "pianokeys")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Pitch detection using autocorrelation algorithm identifies notes and chords")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ChordDetectorView(detector: chordDetector)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)

                    // Educational note
                    TechExplanationCard()
                        .padding(.horizontal, Spacing.lg)
                }
                .padding(.vertical, Spacing.md)
            }
        }
    }
}

// MARK: - Tech Explanation Card

struct TechExplanationCard: View {
    var body: some View {
        GlassCard(tint: Color.riffPrimary.opacity(0.3), cornerRadius: CornerRadius.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("The Science Behind", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.riffPrimary)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    TechBullet(
                        framework: "Foundation Models",
                        description: "On-device LLM for natural language to DSP parameter conversion"
                    )

                    TechBullet(
                        framework: "Accelerate (vDSP)",
                        description: "Apple's high-performance math library for FFT calculations"
                    )

                    TechBullet(
                        framework: "Vision Framework",
                        description: "Real-time face landmark detection for gesture recognition"
                    )

                    TechBullet(
                        framework: "Autocorrelation",
                        description: "Signal processing algorithm to detect fundamental pitch frequency"
                    )

                    TechBullet(
                        framework: "Swift Charts",
                        description: "Native data visualization for spectrum display"
                    )
                }
            }
        }
    }
}

struct TechBullet: View {
    let framework: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.riffPrimary)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(framework)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.15)), in: RoundedRectangle(cornerRadius: 6))

                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
