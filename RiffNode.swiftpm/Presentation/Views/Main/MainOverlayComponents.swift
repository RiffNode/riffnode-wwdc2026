import SwiftUI

// MARK: - Chord Suggestion Chip
// Appears above the chatbot FAB when a chord is detected with high confidence.
// Lets the user one-tap into an AI tone suggestion without interrupting their playing.

struct ChordSuggestionChip: View {
    let suggestion: String
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.purple)

            Text(suggestion)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button(action: onApply) {
                Text("Apply")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.purple.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.purple.opacity(0.12)), in: Capsule())
    }
}

// MARK: - Gesture Control Pill
// Compact toggle in the left panel. Shows face-detection status when active.

struct GestureControlPill: View {
    @Bindable var controller: VisionGestureController
    @Binding var isEnabled: Bool

    var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isEnabled ? .purple : .secondary)
                    .symbolEffect(.pulse, options: .repeating, value: isEnabled && controller.faceDetected)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Gesture Control")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                Spacer()

                Circle()
                    .fill(statusColor.opacity(0.8))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(
                .regular.tint(isEnabled ? .purple.opacity(0.1) : .clear),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        guard isEnabled else { return "Tap to enable" }
        return controller.faceDetected ? "Face Detected" : "Looking for face..."
    }

    private var statusColor: Color {
        guard isEnabled else { return .secondary }
        return controller.faceDetected ? .green : .orange
    }
}
