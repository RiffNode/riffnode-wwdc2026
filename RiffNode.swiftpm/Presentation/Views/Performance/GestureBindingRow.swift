import SwiftUI
import Observation

// MARK: - Gesture Binding Row View

struct GestureBindingRow: View {
    let gesture: VisionGestureController.Gesture
    @Binding var action: PerformanceGestureAction

    var body: some View {
        HStack(spacing: 12) {
            // Gesture icon
            Image(systemName: gesture.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.purple)
                .frame(width: 24)

            // Gesture name
            Text(gesture.rawValue)
                .font(.subheadline)
                .frame(width: 80, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Action picker
            Menu {
                ForEach(PerformanceGestureAction.allCases) { actionOption in
                    Button {
                        action = actionOption
                    } label: {
                        Label(actionOption.rawValue, systemImage: actionOption.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: action.icon)
                        .font(.system(size: 12))
                    Text(action.rawValue)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        GestureBindingRow(
            gesture: .headNodDown,
            action: .constant(.toggleFirstEffect)
        )

        GestureBindingRow(
            gesture: .mouthOpen,
            action: .constant(.wahControl)
        )
    }
    .padding()
}
