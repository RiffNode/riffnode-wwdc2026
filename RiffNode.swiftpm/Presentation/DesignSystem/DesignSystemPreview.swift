import SwiftUI

// MARK: - Preview

#Preview("Design System Components") {
    ZStack {
        AdaptiveBackground()

        ScrollView {
            VStack(spacing: 24) {
                // Glass Card
                GlassCard(tint: .cyan) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Glass Card")
                            .font(.headline)
                        Text("Liquid Glass container with lensing and refraction")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Native iOS 26 Glass Buttons
                HStack(spacing: 16) {
                    Button("Glass") {}
                        .buttonStyle(.glass)

                    Button("Prominent") {}
                        .buttonStyle(.glassProminent)

                    GlassIconButton(icon: "gear", tint: .primary) {}
                }

                // Tab Pills
                HStack(spacing: 8) {
                    Button("Selected") {}
                        .buttonStyle(GlassPillStyle(isSelected: true, tint: .cyan))

                    Button("Unselected") {}
                        .buttonStyle(GlassPillStyle(isSelected: false))
                }

                // Knobs
                HStack(spacing: 32) {
                    GlassKnob(
                        value: .constant(75),
                        tint: .cyan,
                        label: "GAIN"
                    )

                    GlassKnob(
                        value: .constant(50),
                        tint: .orange,
                        label: "TONE"
                    )
                }

                // Native iOS 26 Slider
                Slider(value: .constant(0.7), in: 0...1)
                    .tint(.green)
                    .padding(.horizontal)
            }
            .padding()
        }
    }
}
