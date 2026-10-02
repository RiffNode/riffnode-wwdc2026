import Vision
import AVFoundation
import SwiftUI
import Observation

// MARK: - Vision Gesture Control View

struct VisionGestureControlView: View {
    @Bindable var controller: VisionGestureController
    let onGestureAction: (VisionGestureController.Gesture) -> Void

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(Color.riffPrimary)
                    Text("GESTURE CONTROL")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }

                Spacer()

                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(controller.faceDetected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(controller.faceDetected ? "Face Detected" : "No Face")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                // Toggle button
                Button {
                    Task {
                        if controller.isRunning {
                            controller.stop()
                        } else {
                            try? await controller.start()
                        }
                    }
                } label: {
                    Image(systemName: controller.isRunning ? "stop.fill" : "play.fill")
                        .foregroundStyle(controller.isRunning ? .red : .green)
                }
                .buttonStyle(.bordered)
            }

            if controller.isRunning {
                // Gesture indicators
                HStack(spacing: 16) {
                    // Head nod indicator
                    GestureIndicator(
                        gesture: .headNodDown,
                        isActive: controller.lastDetectedGesture == .headNodDown,
                        isEnabled: controller.enabledGestures.contains(.headNodDown)
                    )

                    // Mouth indicator with continuous value
                    MouthIndicator(
                        openness: controller.currentMouthOpenness,
                        isEnabled: controller.enabledGestures.contains(.mouthOpen)
                    )

                    // Tilt indicator
                    GestureIndicator(
                        gesture: .headTiltRight,
                        isActive: controller.lastDetectedGesture == .headTiltRight,
                        isEnabled: controller.enabledGestures.contains(.headTiltRight)
                    )
                }

                // Last gesture display
                if let lastGesture = controller.lastDetectedGesture {
                    HStack(spacing: 8) {
                        Image(systemName: lastGesture.icon)
                            .foregroundStyle(Color.riffPrimary)
                        Text(lastGesture.defaultAction)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.riffPrimary.opacity(0.2))
                    .clipShape(Capsule())
                }

                // Help text
                Text("Nod to switch presets • Open mouth for Wah")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                // Not running state
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Hands-free control disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Enable to control effects with head gestures")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .padding()
            }
        }
        .padding()
        .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.1)), in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            controller.onGestureDetected = { gesture in
                onGestureAction(gesture)
            }
        }
    }
}

// MARK: - Gesture Indicator

struct GestureIndicator: View {
    let gesture: VisionGestureController.Gesture
    let isActive: Bool
    let isEnabled: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.riffPrimary : Color.white.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: gesture.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? .white : (isEnabled ? .secondary : .secondary.opacity(0.3)))
            }

            Text(gesture.rawValue)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Mouth Indicator

struct MouthIndicator: View {
    let openness: Float
    let isEnabled: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 40)

                // Mouth visual
                Capsule()
                    .fill(Color.riffPrimary.opacity(Double(openness)))
                    .frame(width: 20, height: 8 + CGFloat(openness) * 12)
            }

            Text("Wah")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var previewController = VisionGestureController()
    VisionGestureControlView(
        controller: previewController,
        onGestureAction: { _ in }
    )
    .padding()
    .background(Color.black)
}
