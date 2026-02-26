import Vision
import AVFoundation
import SwiftUI
import Observation

// MARK: - Extracted Face Data (Sendable for cross-isolation transfer)

private struct ExtractedFaceData: Sendable {
    let pitch: Float
    let yaw: Float
    let roll: Float
    let mouthOpenness: Float?
}

// MARK: - Global Face Data Handler
// This avoids capturing MainActor-isolated self in nonisolated callbacks
// Using @MainActor isolation for the shared instance to ensure thread safety

@MainActor
private var visionControllerInstance: VisionGestureController?

private func visionProcessFaceData(_ data: ExtractedFaceData) {
    // Dispatch to main actor to safely access the shared instance
    Task { @MainActor in
        visionControllerInstance?.processFaceData(data)
    }
}

// MARK: - Vision Gesture Controller
// Hands-free control using head movements and facial gestures
// Perfect accessibility feature - musicians can control effects while playing

@Observable
@MainActor
final class VisionGestureController: NSObject {

    // MARK: - Gesture Types

    enum Gesture: String, CaseIterable {
        case headNodDown = "Nod Down"
        case headNodUp = "Nod Up"
        case headTiltLeft = "Tilt Left"
        case headTiltRight = "Tilt Right"
        case mouthOpen = "Mouth Open"
        case eyebrowRaise = "Eyebrow Raise"

        var icon: String {
            switch self {
            case .headNodDown: return "arrow.down"
            case .headNodUp: return "arrow.up"
            case .headTiltLeft: return "arrow.left"
            case .headTiltRight: return "arrow.right"
            case .mouthOpen: return "mouth.fill"
            case .eyebrowRaise: return "eyebrow"
            }
        }

        var defaultAction: String {
            switch self {
            case .headNodDown: return "Next Preset"
            case .headNodUp: return "Previous Preset"
            case .headTiltLeft: return "Toggle Bypass"
            case .headTiltRight: return "Toggle Effect"
            case .mouthOpen: return "Wah Effect"
            case .eyebrowRaise: return "Boost Gain"
            }
        }
    }

    // MARK: - Callbacks

    var onGestureDetected: ((Gesture) -> Void)?
    var onMouthOpenValueChanged: ((Float) -> Void)? // 0.0 to 1.0 for Wah control

    // MARK: - State

    private(set) var isRunning = false
    private(set) var hasPermission = false
    private(set) var lastDetectedGesture: Gesture?
    private(set) var faceDetected = false
    private(set) var currentMouthOpenness: Float = 0
    private(set) var errorMessage: String?

    // Enable/disable specific gestures
    var enabledGestures: Set<Gesture> = Set(Gesture.allCases)

    // MARK: - Vision Components

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let processingQueue = DispatchQueue(label: "com.riffnode.vision", qos: .userInteractive)

    // MARK: - Tracking State for Gesture Detection

    private var pitchHistory: [Float] = []
    private var yawHistory: [Float] = []
    private var rollHistory: [Float] = []
    private var mouthHistory: [Float] = []

    private let historySize = 15
    private var lastGestureTime: Date = .distantPast
    private let gestureCooldown: TimeInterval = 0.5 // Prevent rapid triggers

    // Thresholds
    private let nodThreshold: Float = 0.15
    private let tiltThreshold: Float = 0.2
    private let mouthOpenThreshold: Float = 0.3

    // MARK: - Initialization

    override init() {
        super.init()
        // Register as the shared instance for global callback
        visionControllerInstance = self
    }

    // MARK: - Permission

    func requestCameraPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            hasPermission = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            hasPermission = false
            errorMessage = "Camera access denied. Enable in Settings > Privacy > Camera."
        @unknown default:
            hasPermission = false
        }
    }

    // MARK: - Start/Stop

    func start() async throws {
        if !hasPermission {
            await requestCameraPermission()
            guard hasPermission else {
                throw VisionError.permissionDenied
            }
        }

        await setupCaptureSession()
        captureSession?.startRunning()
        isRunning = true
        print("VisionGestureController: Started")
    }

    func stop() {
        captureSession?.stopRunning()
        isRunning = false
        faceDetected = false
        print("VisionGestureController: Stopped")
    }

    // MARK: - Setup

    private func setupCaptureSession() async {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        // Get front camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            errorMessage = "No front camera available"
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: processingQueue)
            output.alwaysDiscardsLateVideoFrames = true

            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            // Set video orientation
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
                connection.isVideoMirrored = true
            }

            self.captureSession = session
            self.videoOutput = output

        } catch {
            errorMessage = "Failed to setup camera: \(error.localizedDescription)"
        }
    }

    // MARK: - Face Detection Handler

    fileprivate func processFaceData(_ data: ExtractedFaceData) {
        faceDetected = true

        // Update history with head pose angles
        updateHistory(&pitchHistory, with: data.pitch)
        updateHistory(&yawHistory, with: data.yaw)
        updateHistory(&rollHistory, with: data.roll)

        // Detect head gestures
        detectHeadGestures()

        // Process mouth openness for Wah control
        if let mouthOpenness = data.mouthOpenness {
            processMouthOpenness(mouthOpenness)
        }
    }

    private func updateHistory(_ history: inout [Float], with value: Float) {
        history.append(value)
        if history.count > historySize {
            history.removeFirst()
        }
    }

    // MARK: - Head Gesture Detection

    private func detectHeadGestures() {
        guard pitchHistory.count >= historySize else { return }
        guard Date().timeIntervalSince(lastGestureTime) > gestureCooldown else { return }

        // Calculate deltas (change over time)
        let recentPitch = pitchHistory.suffix(5)
        let olderPitch = pitchHistory.prefix(5)

        let pitchDelta = (recentPitch.reduce(0, +) / Float(recentPitch.count)) -
                         (olderPitch.reduce(0, +) / Float(olderPitch.count))

        let recentRoll = rollHistory.suffix(5)
        let olderRoll = rollHistory.prefix(5)

        let rollDelta = (recentRoll.reduce(0, +) / Float(recentRoll.count)) -
                        (olderRoll.reduce(0, +) / Float(olderRoll.count))

        // Detect nod down
        if pitchDelta < -nodThreshold && enabledGestures.contains(.headNodDown) {
            triggerGesture(.headNodDown)
        }
        // Detect nod up
        else if pitchDelta > nodThreshold && enabledGestures.contains(.headNodUp) {
            triggerGesture(.headNodUp)
        }
        // Detect tilt left
        else if rollDelta > tiltThreshold && enabledGestures.contains(.headTiltLeft) {
            triggerGesture(.headTiltLeft)
        }
        // Detect tilt right
        else if rollDelta < -tiltThreshold && enabledGestures.contains(.headTiltRight) {
            triggerGesture(.headTiltRight)
        }
    }

    // MARK: - Mouth Detection (for Wah Effect)

    private func processMouthOpenness(_ normalizedOpenness: Float) {
        // Smooth the value
        updateHistory(&mouthHistory, with: normalizedOpenness)
        let smoothedOpenness = mouthHistory.reduce(0, +) / Float(mouthHistory.count)

        currentMouthOpenness = smoothedOpenness

        // Trigger callback for continuous Wah control
        onMouthOpenValueChanged?(smoothedOpenness)

        // Detect mouth open gesture (discrete)
        if smoothedOpenness > mouthOpenThreshold && enabledGestures.contains(.mouthOpen) {
            // Only trigger once when opening
            if mouthHistory.count > 2 {
                let previousValue = mouthHistory[mouthHistory.count - 2]
                if previousValue < mouthOpenThreshold {
                    triggerGesture(.mouthOpen)
                }
            }
        }
    }

    // MARK: - Trigger Gesture

    private func triggerGesture(_ gesture: Gesture) {
        lastDetectedGesture = gesture
        lastGestureTime = Date()

        // Clear history to prevent repeated triggers
        pitchHistory.removeAll()
        rollHistory.removeAll()
        yawHistory.removeAll()

        print("VisionGestureController: Detected \(gesture.rawValue)")
        onGestureDetected?(gesture)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VisionGestureController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        // Create request on background thread
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3

        do {
            try requestHandler.perform([request])

            // Extract all data on background thread before crossing isolation boundary
            let extractedData: ExtractedFaceData? = {
                guard let face = request.results?.first else { return nil }

                let pitch = face.pitch?.floatValue ?? 0
                let yaw = face.yaw?.floatValue ?? 0
                let roll = face.roll?.floatValue ?? 0

                // Extract mouth openness from landmarks
                var mouthOpenness: Float? = nil
                if let innerLips = face.landmarks?.innerLips {
                    let innerPoints = innerLips.normalizedPoints
                    if innerPoints.count >= 6 {
                        let topLip = innerPoints[0]
                        let bottomLip = innerPoints[3]
                        let mouthHeight = abs(topLip.y - bottomLip.y)
                        mouthOpenness = min(1.0, max(0, (Float(mouthHeight) - 0.02) / 0.08))
                    }
                }

                return ExtractedFaceData(pitch: pitch, yaw: yaw, roll: roll, mouthOpenness: mouthOpenness)
            }()

            // Post face data to be processed on main actor
            // Use a global callback to avoid capturing MainActor-isolated self
            if let data = extractedData {
                visionProcessFaceData(data)
            }
        } catch {
            print("VisionGestureController: Face detection error - \(error)")
        }
    }
}

// MARK: - Errors

enum VisionError: Error, LocalizedError {
    case permissionDenied
    case noCameraAvailable
    case setupFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission denied"
        case .noCameraAvailable: return "No camera available"
        case .setupFailed: return "Failed to setup camera"
        }
    }
}

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
                        .foregroundStyle(.purple)
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
                            .foregroundStyle(.purple)
                        Text(lastGesture.defaultAction)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.2))
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
        .glassEffect(.regular.tint(.purple.opacity(0.1)), in: RoundedRectangle(cornerRadius: 12))
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
                    .fill(isActive ? Color.purple : Color.white.opacity(0.1))
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
                    .fill(Color.purple.opacity(Double(openness)))
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
