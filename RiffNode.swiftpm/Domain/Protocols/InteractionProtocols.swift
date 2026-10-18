import Foundation

// MARK: - Analysis Services
// What the main screen drives with the engine's samples. The read-only sides
// (SpectrumProviding, ChordDetecting) are all most views ever see.

/// Turns samples into the live spectrum.
@MainActor
protocol SpectrumAnalyzing: SpectrumProviding {
    var sampleRate: Double { get set }
    func analyze(samples: [Float])
}

/// Turns samples into the note, tuning and chord being played.
@MainActor
protocol ChordAnalyzing: ChordDetecting {
    var sampleRate: Float { get set }
    func analyze(samples: [Float])
    /// Forgets the current note and chord (a new source, or a reset).
    func reset()
}

// MARK: - Hands-free Control

/// Head and face gestures from the camera.
@MainActor
protocol GestureControlling: AnyObject {
    var isRunning: Bool { get }
    var faceDetected: Bool { get }
    var lastDetectedGesture: FaceGesture? { get }
    var currentMouthOpenness: Float { get }
    var enabledGestures: Set<FaceGesture> { get set }
    var onGestureDetected: ((FaceGesture) -> Void)? { get set }
    /// 0…1, closed to open: the wah pedal's position.
    var onMouthOpenValueChanged: ((Float) -> Void)? { get set }

    func start() async throws
    func stop()
}

// MARK: - Tone Assistant

/// Understands a request in plain words (or a photo) and turns it into pedal settings.
@MainActor
protocol ToneAssisting: AnyObject {
    /// True when Apple Intelligence can answer; otherwise an offline matcher does.
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    var canReadImages: Bool { get }
    var thinkingSteps: [AssistantThinkingStep] { get }

    // The outcome of the last request
    var lastCommandMode: String { get }
    var lastExplanation: String { get }
    var lastResponder: ToneResponder { get }
    var lastEnabledEffects: [String] { get }
    var lastDisabledEffects: [String] { get }
    var lastDeletedEffects: [String] { get }

    /// `pedalboard` describes the current chain, so relative edits ("more reverb") work.
    func processCommand(_ command: String, pedalboard: String?) async -> Bool
    func processImage(at url: URL) async -> Bool
    func applyToEngine(_ engine: any EffectsChainManaging)
    /// Starts a new conversation (the chat was cleared).
    func resetConversation()
}
