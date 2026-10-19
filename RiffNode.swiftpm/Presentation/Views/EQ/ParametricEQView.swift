import SwiftUI

// MARK: - Parametric EQ View
// Liquid Glass UI Design - iOS 26+
// Modern parametric equalizer with glass styling and smooth curves

struct ParametricEQView: View {
    let engine: any EqualizerControlling

    private var eqBands: Binding<[EQBand]> {
        Binding(get: { engine.parametricEQBands }, set: { engine.parametricEQBands = $0 })
    }
    /// Live spectrum drawn behind the curve, so you can see which frequencies you are shaping.
    var analyzer: (any SpectrumProviding)?
    @State private var selectedBand: Int? = nil
    @State private var isAnalyzerActive = true

    var body: some View {
        VStack(spacing: 16) {
            // Header with analyzer toggle and presets
            GlassEQHeader(
                isAnalyzerActive: $isAnalyzerActive,
                bands: eqBands,
                onReset: {
                    engine.resetEQ()
                }
            )

            // Main EQ Display with glass styling - larger for direct interaction
            GlassCard(cornerRadius: 16, padding: 0) {
                ZStack {
                    // Subtle gradient background
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.2)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Grid
                    GlassEQGridView()

                    // Live input spectrum behind the curve
                    if isAnalyzerActive, let analyzer {
                        EQSpectrumOverlay(analyzer: analyzer)
                            .transition(.opacity)
                    }

                    // Smooth frequency response curve with fill
                    GlassEQCurveView(bands: engine.parametricEQBands, selectedBand: selectedBand)

                    // Draggable band nodes - tap to select, drag to adjust
                    GlassEQBandNodes(
                        bands: eqBands,
                        selectedBand: $selectedBand
                    )

                    // Hint text when no band selected
                    if selectedBand == nil {
                        VStack {
                            Spacer()
                            Text("Tap a node to select • Drag to adjust")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                        }
                    }
                }
                .frame(height: 320)
                .animation(.easeInOut(duration: 0.2), value: isAnalyzerActive)
            }

            // Selected band controls - compact inline controls
            if let selected = selectedBand {
                GlassEQBandControls(band: eqBands[selected])
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(duration: 0.25), value: selectedBand)
    }
}

// MARK: - EQ Spectrum Overlay
// Draws the live FFT on the same log-frequency axis as the EQ curve.

private struct EQSpectrumOverlay: View {
    let analyzer: any SpectrumProviding

    var body: some View {
        Canvas { context, size in
            let magnitudes = analyzer.logMagnitudes
            let frequencies = analyzer.logFrequencies
            guard magnitudes.count > 1, magnitudes.count == frequencies.count else { return }

            let logMin = log10(Float(20)), logMax = log10(Float(20000))
            func x(_ frequency: Float) -> CGFloat {
                let logFreq = log10(max(frequency, 20))
                return 30 + CGFloat((logFreq - logMin) / (logMax - logMin)) * (size.width - 40)
            }

            var path = Path()
            path.move(to: CGPoint(x: x(max(frequencies[0], 20)), y: size.height))
            for (frequency, magnitude) in zip(frequencies, magnitudes) {
                // Ignore the bottom ~25 dB (noise floor) so the shape of the sound stands out,
                // and keep it below the curve so the EQ stays the focus
                let level = CGFloat(min(max((magnitude - 0.3) / 0.7, 0), 1))
                let y = size.height - level * size.height * 0.7
                path.addLine(to: CGPoint(x: x(frequency), y: y))
            }
            path.addLine(to: CGPoint(x: x(frequencies.last ?? 20000), y: size.height))
            path.closeSubpath()

            context.fill(path, with: .linearGradient(
                Gradient(colors: [Color.cyan.opacity(0.28), Color.cyan.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()

        ParametricEQView(engine: AppDependencies.live().engine)
            .frame(height: 500)
            .padding()
    }
}
