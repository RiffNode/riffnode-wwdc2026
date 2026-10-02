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
                .foregroundStyle(Color.riffPrimary)

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
                    .background(Color.riffPrimary.opacity(0.85), in: Capsule())
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
        .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.12)), in: Capsule())
    }
}

// MARK: - Gesture Control Pill
// Compact toggle in the left panel. Shows face-detection status when active.

struct GestureControlPill: View {
    @Bindable var controller: VisionGestureController
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Gesture Control")
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            } icon: {
                Image(systemName: "face.dashed")
                    .symbolEffect(.pulse, options: .repeating, isActive: isEnabled && controller.faceDetected)
            }
        }
        .tint(Color.riffPrimary)
        .accessibilityHint("Nod to switch presets using the front camera")
    }

    private var statusText: String {
        guard isEnabled else { return "Nod to change presets" }
        return controller.faceDetected ? "Face detected" : "Looking for your face…"
    }

    private var statusColor: Color {
        guard isEnabled else { return .secondary }
        return controller.faceDetected ? .green : .secondary
    }
}
