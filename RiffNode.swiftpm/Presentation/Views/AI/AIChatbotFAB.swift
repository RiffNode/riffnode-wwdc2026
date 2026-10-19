import SwiftUI
import Observation
import PhotosUI

// MARK: - Tone Assistant Button

struct AIChatbotFAB: View {
    let isExpanded: Bool
    let isThinking: Bool
    let usesAppleIntelligence: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false
    @State private var ringRotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        if isExpanded { return "xmark" }
        return usesAppleIntelligence ? "apple.intelligence" : "wand.and.stars"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(isExpanded ? AnyShapeStyle(.secondary) : AnyShapeStyle(assistantGradient))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, options: .repeating, isActive: isThinking && !reduceMotion)

                if !isExpanded {
                    Text(isThinking ? "Thinking…" : "Tone Assistant")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.opacity)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .padding(.horizontal, isExpanded ? 0 : 18)
            .frame(width: isExpanded ? 48 : nil, height: 48)
            .contentShape(Capsule())
            .glassEffect(.regular.tint(.purple.opacity(isExpanded ? 0 : 0.18)).interactive(), in: Capsule())
            .glassEffectID("fab", in: namespace)
            // Apple Intelligence–style glow ring while the model works
            .overlay {
                if isThinking {
                    Capsule()
                        .strokeBorder(
                            AngularGradient(
                                colors: [.purple, .pink, .orange, .cyan, .purple],
                                center: .center,
                                angle: .degrees(ringRotation)
                            ),
                            lineWidth: 2.5
                        )
                        .blur(radius: 0.5)
                        .transition(.opacity)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                ringRotation = 360
                            }
                        }
                        .onDisappear { ringRotation = 0 }
                }
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .purple.opacity(isExpanded ? 0 : 0.25), radius: isHovered ? 14 : 8, y: 4)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .animation(.easeInOut(duration: 0.25), value: isThinking)
        .onHover { isHovered = $0 }
        .help("Tone Assistant (⌘J)")
        .accessibilityLabel(isExpanded ? "Close Tone Assistant" : "Open Tone Assistant")
        .accessibilityValue(isThinking ? "Thinking" : "")
    }

    private var assistantGradient: LinearGradient {
        LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
