import SwiftUI

// MARK: - Glass Card

/// A Liquid Glass card container using native iOS 26 .glassEffect() API
/// Supports optional tinting via GlassStyle.regular.tint(color)
struct GlassCard<Content: View>: View {
    let content: Content
    var tint: Color?
    var cornerRadius: CGFloat
    var padding: CGFloat

    init(
        tint: Color? = nil,
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .glassEffect(
                tint.map { .regular.tint($0) } ?? .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .highContrastOutline(cornerRadius: cornerRadius)
    }
}

private struct HighContrastOutline: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5)
            }
        }
    }
}

extension View {
    /// With Increase Contrast on, a glass card gets a clear edge instead of a soft one.
    func highContrastOutline(cornerRadius: CGFloat) -> some View {
        modifier(HighContrastOutline(cornerRadius: cornerRadius))
    }
}
