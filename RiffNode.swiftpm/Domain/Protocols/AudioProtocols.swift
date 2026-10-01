import Foundation

// MARK: - Protocols / Abstractions
// Following Interface Segregation Principle: Many specific interfaces
// Following Dependency Inversion Principle: Depend on abstractions, not concretions

// MARK: - Audio Engine Protocol

/// Core audio engine operations
/// Segregated from effects management for single responsibility
@MainActor
protocol AudioEngineProtocol: AnyObject {
    var isRunning: Bool { get }
    var hasPermission: Bool { get }
    var errorMessage: String? { get set }

    func requestMicrophonePermission() async
    func setupEngine() async throws
    func start() throws
    func stop()
}

// MARK: - Effects Chain Protocol

/// Manages the effects chain
/// Segregated interface for effect operations only
@MainActor
protocol EffectsChainManaging: AnyObject {
    var effectsChain: [EffectNode] { get set }

    func addEffect(_ type: EffectType)
    func removeEffect(at index: Int)
    func moveEffect(from source: IndexSet, to destination: Int)
    func toggleEffect(_ effect: EffectNode)
    func updateEffectParameter(_ effect: EffectNode, key: String, value: Float)
    func clearEffects()
    func applyPreset(_ preset: EffectPreset)
}

// MARK: - Audio Visualization Protocol

/// Provides audio visualization data
/// Read-only interface for visualization consumers
@MainActor
protocol AudioVisualizationProviding: AnyObject {
    var waveformSamples: [Float] { get }
    var inputLevel: Float { get }
    var outputLevel: Float { get }
}

// MARK: - Backing Track Protocol

/// Manages backing track playback
@MainActor
protocol BackingTrackManaging: AnyObject {
    var isBackingTrackPlaying: Bool { get }
    var backingTrackVolume: Float { get set }

    func loadBackingTrack(url: URL) async throws
    func playBackingTrack()
    func stopBackingTrack()
    func setBackingTrackVolume(_ volume: Float)
}

// MARK: - Preset Provider Protocol

/// Provides effect presets
/// Allows for different preset sources (built-in, user-created, cloud)
protocol PresetProviding {
    var presets: [EffectPreset] { get }
    func preset(for id: UUID) -> EffectPreset?
    func presets(for category: EffectPreset.PresetCategory) -> [EffectPreset]
}

// MARK: - Combined Audio Manager Protocol

/// Combined protocol for convenience when full access is needed
/// Composes the segregated interfaces
@MainActor
protocol AudioManaging: AudioEngineProtocol, EffectsChainManaging, AudioVisualizationProviding, BackingTrackManaging {}

// MARK: - Audio Engine Errors

enum AudioEngineError: Error, LocalizedError {
    case noPermission
    case engineNotSetup
    case bufferCreationFailed
    case noInputDevice
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Microphone permission not granted"
        case .engineNotSetup:
            return "Audio engine not configured"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .noInputDevice:
            return "No audio input device found. Please connect a microphone or audio interface."
        case .invalidConfiguration:
            return "Invalid audio configuration"
        }
    }
}
