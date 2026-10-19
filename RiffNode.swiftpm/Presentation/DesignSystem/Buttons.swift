import SwiftUI

// MARK: - Buttons

/// Compact pill-shaped glass button for tabs and toggles
struct GlassPillStyle: ButtonStyle {
    var isSelected: Bool
    var tint: Color

    init(isSelected: Bool = false, tint: Color = .accentColor) {
        self.isSelected = isSelected
        self.tint = tint
    }

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(
                isSelected ? .regular.tint(tint) : .regular,
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Circular glass button for icons
struct GlassIconButton: View {
    let icon: String
    var tint: Color
    var size: CGFloat
    let action: () -> Void

    init(
        icon: String,
        tint: Color = .primary,
        size: CGFloat = 44,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.tint = tint
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Simple scale animation on press
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
