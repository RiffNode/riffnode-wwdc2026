import SwiftUI

// MARK: - Glass Effect Pedal

/// A pedal on the board: the classic stompbox it's modelled on (see `StompboxView`), plus
/// selection, hover-to-delete and the tap / double-tap gestures.
struct GlassEffectPedal: View {
    let effect: EffectNode
    var isSelected: Bool = false
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        StompboxView(effect: effect, isLive: effect.isEnabled)
        // Selected state: a glass-coloured ring around the pedal
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white, lineWidth: 2.5)
                    .shadow(color: Color.white.opacity(0.5), radius: 6)
            }
        }
        // Subtle drop shadow so pedals "sit" on the board
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        // Delete badge on hover
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .red)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(duration: 0.2), value: isHovering)
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(effect.type.rawValue) pedal, \(effect.isEnabled ? "enabled" : "bypassed")")
        .accessibilityHint("Tap to select, double-tap to toggle")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
