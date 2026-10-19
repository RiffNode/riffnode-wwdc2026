import SwiftUI

// MARK: - Adaptive Background

/// Creates a vibrant dynamic background for iOS 26 Liquid Glass testing
/// High-contrast animated orbs to showcase glass lensing and refraction
struct AdaptiveBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Vibrant gradient base
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.1, green: 0.05, blue: 0.2), Color(red: 0.05, green: 0.1, blue: 0.15)]
                    : [Color(red: 0.95, green: 0.9, blue: 1.0), Color(red: 0.9, green: 0.95, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Animated floating orbs - more vibrant for glass testing
            // With Reduce Transparency the colourful orbs go: glass then sits on a calm,
            // even background and text keeps its contrast.
            if !reduceTransparency {
                // Slow drifting orbs need ~15 fps, not 30 – the GPU time goes to the audio views
                // instead; with Reduce Motion they hold still.
                TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate

                    Canvas { context, size in
                        // More vibrant orbs to see lensing effect
                        let orbs: [(color: Color, baseX: CGFloat, baseY: CGFloat, radius: CGFloat, speedX: Double, speedY: Double)] = colorScheme == .dark ? [
                            (.purple.opacity(0.7), 0.2, 0.3, 250, 0.3, 0.2),
                            (.blue.opacity(0.6), 0.8, 0.2, 220, 0.2, 0.35),
                            (.cyan.opacity(0.65), 0.5, 0.7, 280, 0.25, 0.15),
                            (.pink.opacity(0.55), 0.3, 0.8, 200, 0.35, 0.25),
                            (.orange.opacity(0.5), 0.7, 0.5, 240, 0.15, 0.3),
                            (.green.opacity(0.4), 0.1, 0.6, 180, 0.28, 0.22)
                        ] : [
                            (.purple.opacity(0.4), 0.2, 0.3, 250, 0.3, 0.2),
                            (.blue.opacity(0.35), 0.8, 0.2, 220, 0.2, 0.35),
                            (.cyan.opacity(0.3), 0.5, 0.7, 280, 0.25, 0.15),
                            (.pink.opacity(0.35), 0.3, 0.8, 200, 0.35, 0.25),
                            (.orange.opacity(0.25), 0.7, 0.5, 240, 0.15, 0.3),
                            (.mint.opacity(0.3), 0.1, 0.6, 180, 0.28, 0.22)
                        ]

                        for orb in orbs {
                            // Calculate animated position
                            let x = orb.baseX * size.width + sin(time * orb.speedX) * 100
                            let y = orb.baseY * size.height + cos(time * orb.speedY) * 80

                            // Create radial gradient for soft glow effect
                            let center = CGPoint(x: x, y: y)
                            let gradient = Gradient(stops: [
                                .init(color: orb.color, location: 0),
                                .init(color: orb.color.opacity(0.6), location: 0.4),
                                .init(color: orb.color.opacity(0), location: 1)
                            ])

                            context.fill(
                                Circle().path(in: CGRect(
                                    x: x - orb.radius,
                                    y: y - orb.radius,
                                    width: orb.radius * 2,
                                    height: orb.radius * 2
                                )),
                                with: .radialGradient(
                                    gradient,
                                    center: center,
                                    startRadius: 0,
                                    endRadius: orb.radius
                                )
                            )
                        }
                    }
                }
                .blur(radius: 40) // Less blur to see more detail through glass
            }
        }
        .ignoresSafeArea()
    }
}
