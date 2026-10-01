import SwiftUI
import Observation

// MARK: - View Models
// Following MVVM pattern within Clean Architecture
// ViewModels handle presentation logic and coordinate between Views and Services

// MARK: - Setup View Model

/// Handles the onboarding/setup flow logic
@Observable
@MainActor
final class SetupViewModel {

    // MARK: - State

    enum SetupStep: Int, CaseIterable {
        case welcome = 0
        case permission = 1
        case engine = 2
        case ready = 3

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .permission: return "Microphone Access"
            case .engine: return "Audio Engine"
            case .ready: return "Ready to Rock"
            }
        }

        var description: String {
            switch self {
            case .welcome: return "Let's get started"
            case .permission: return "Connect your guitar through an audio interface"
            case .engine: return "Initialize the effects processing engine"
            case .ready: return "Start creating your sound"
            }
        }

        var icon: String {
            switch self {
            case .welcome: return "hand.wave.fill"
            case .permission: return "mic.fill"
            case .engine: return "waveform.path.ecg"
            case .ready: return "guitars.fill"
            }
        }
    }

    private(set) var currentStep: SetupStep = .welcome
    private(set) var isLoading = false
    var isSetupComplete = false

    // MARK: - Dependencies

    private let audioEngine: AudioEngineProtocol

    // MARK: - Initialization

    init(audioEngine: AudioEngineProtocol) {
        self.audioEngine = audioEngine
    }

    // MARK: - Computed Properties

    var buttonTitle: String {
        switch currentStep {
        case .welcome: return "Get Started"
        case .permission: return "Allow Access"
        case .engine: return "Start Engine"
        case .ready: return "Let's Rock!"
        }
    }

    var hasPermission: Bool {
        audioEngine.hasPermission
    }

    var isEngineRunning: Bool {
        audioEngine.isRunning
    }

    var errorMessage: String? {
        get { audioEngine.errorMessage }
        set { audioEngine.errorMessage = newValue }
    }

    // MARK: - Actions

    func performNextStep() async {
        isLoading = true

        do {
            // Single-step setup: request permission and start engine automatically
            await audioEngine.requestMicrophonePermission()
            
            if audioEngine.hasPermission {
                try await audioEngine.setupEngine()
                try audioEngine.start()
                currentStep = .ready
                isSetupComplete = true
                audioEngine.errorMessage = nil
            } else if audioEngine.errorMessage == nil {
                audioEngine.errorMessage = "Microphone permission is required to continue."
            }
        } catch {
            audioEngine.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func advanceStep() {
        withAnimation(.spring(duration: 0.3)) {
            if let nextStep = SetupStep(rawValue: currentStep.rawValue + 1) {
                currentStep = nextStep
            }
        }
    }

    func stepStatus(for step: SetupStep) -> StepStatus {
        if step.rawValue < currentStep.rawValue {
            return .completed
        } else if step == currentStep {
            return .active
        }
        return .pending
    }

    enum StepStatus {
        case pending, active, completed
    }
}
