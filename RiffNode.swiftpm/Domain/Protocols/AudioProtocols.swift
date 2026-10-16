import Foundation

// MARK: - Protocols / Abstractions
// Following Interface Segregation Principle: Many specific interfaces
// Following Dependency Inversion Principle: Depend on abstractions, not concretions

// MARK: - Audio Engine

/// Starting, stopping and choosing the input.
@MainActor
protocol AudioEngineControlling: AnyObject {
    var isRunning: Bool { get }
    var hasPermission: Bool { get }
    var errorMessage: String? { get set }
    var currentInputDeviceName: String { get }
    var currentInputDeviceType: AudioInputDeviceType { get }

    func requestMicrophonePermission() async
    func setupEngine() async throws
    func start() throws
    func stop()
    func refreshInputDevices()
}

/// Live samples for the tuner, chord detector and spectrum.
@MainActor
protocol AudioAnalysisSource: AnyObject {
    var analysisSampleRate: Double { get }
    var onAudioSamplesAvailable: (@MainActor ([Float]) -> Void)? { get set }
    var currentPreset: EffectPreset? { get }
}

/// Live loudness, for meters.
@MainActor
protocol AudioLevelProviding: AnyObject {
    var inputLevel: Float { get }
    var outputLevel: Float { get }
}

// MARK: - Effects Chain

/// The pedals, their order and their settings.
@MainActor
protocol EffectsChainManaging: AnyObject {
    var effectsChain: [EffectNode] { get set }
    /// Bumped on every preset application, so re-applying the same preset is observable.
    var presetApplyCount: Int { get }

    func addEffect(_ type: EffectType)
    func removeEffect(at index: Int)
    func moveEffect(from source: IndexSet, to destination: Int)
    func toggleEffect(_ effect: EffectNode)
    func updateEffectParameter(_ effect: EffectNode, key: String, value: Float)
    func clearEffects()
    func applyPreset(_ preset: EffectPreset)
    /// Adds a pedal at its usual place in the chain if it's missing (used by the Tone Assistant).
    func ensureEffectInChain(_ type: EffectType)
    /// Re-applies every pedal's settings and bypass state after a batch of changes.
    func rebuildEffectsChain()
}

/// The 10-band parametric EQ.
@MainActor
protocol EqualizerControlling: AnyObject {
    var parametricEQBands: [EQBand] { get set }
    func resetEQ()
    func applyToneSuggestion(_ suggestion: ToneSuggestion)
}

// MARK: - Sources

/// The built-in demo riff that stands in for a guitar.
@MainActor
protocol DemoRiffPlaying: AnyObject {
    var isDemoRiffPlaying: Bool { get }
    /// True once there is an effects chain to play into.
    var canPlayDemoRiff: Bool { get }
    func toggleDemoRiff()
    func startDemoRiff()
    func stopDemoRiff()
}

/// Hearing one pedal on its own, A/B against the dry riff (Learn tab).
@MainActor
protocol EffectAuditioning: AnyObject {
    var auditionEffect: EffectType? { get }
    var isAuditionBypassed: Bool { get }
    func startAudition(_ type: EffectType)
    func setAuditionBypassed(_ bypassed: Bool)
    func stopAudition()
}

/// Watching the signal on both sides of one pedal (Signal Lab).
@MainActor
protocol SignalProbing: AnyObject {
    func probe(_ type: EffectType, owner: UUID)
    func stopProbe(owner: UUID)
    /// The latest captures into and out of the probed pedal.
    func probeSnapshot() -> (before: SignalCapture, after: SignalCapture)
}

/// Hands-free control: the mouth wah and other expression targets.
@MainActor
protocol ExpressionControlling: AnyObject {
    /// nil turns the wah off; 0…1 is the pedal position (heel → toe).
    func setWah(_ position: Float?)
    func setExpressionValue(_ value: Float, for effectType: EffectType)
}

// MARK: - Play Along

/// The groove and imported songs.
@MainActor
protocol BackingTrackManaging: AnyObject {
    var isReady: Bool { get }
    var isBackingTrackPlaying: Bool { get }
    var backingTrackVolume: Float { get }
    var backingTrackDuration: TimeInterval { get }
    var backingTrackCurrentTime: TimeInterval { get }
    var backingTrackName: String? { get }
    var isBuiltInJamTrack: Bool { get }
    var backingTrackThroughEffects: Bool { get }
    var grooveTempo: Double { get }
    var grooveTranspose: Int { get }

    func loadBackingTrack(url: URL) async throws
    func loadBuiltInJamTrack(tempo: Double?, transpose: Int?) throws
    func unloadBackingTrack()
    func playBackingTrack()
    func stopBackingTrack()
    func seekBackingTrack(to time: TimeInterval)
    func setBackingTrackVolume(_ volume: Float)
    func toggleBackingTrackThroughEffects()
}

/// Apple Music and Spotify playing alongside RiffNode.
@MainActor
protocol MusicAppControlling: AnyObject {
    /// Apple Music can be controlled from inside RiffNode (iPad only).
    var canControlAppleMusic: Bool { get }
    var isAuthorized: Bool { get }
    var isDenied: Bool { get }
    var title: String? { get }
    var artist: String? { get }
    var isPlaying: Bool { get }

    func requestAccess() async
    func refresh()
    func togglePlayback()
    func skipToNext()
    func skipToPrevious()
}

// MARK: - Analysis

/// The live spectrum on a log-frequency axis.
@MainActor
protocol SpectrumProviding: AnyObject {
    var logFrequencies: [Float] { get }
    var logMagnitudes: [Float] { get }
}

/// The note and chord being played.
@MainActor
protocol ChordDetecting: AnyObject {
    var detectedNote: String { get }
    var detectedChord: String { get }
    var confidence: Float { get }
    var centsDeviation: Float { get }
    var isInTune: Bool { get }
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

/// Everything the audio engine offers, for the few places that coordinate it all
/// (MainViewModel, ContentView). Views take only the pieces they need.
@MainActor
protocol AudioManaging: AudioEngineControlling, AudioLevelProviding, AudioAnalysisSource, EffectsChainManaging,
    EqualizerControlling, DemoRiffPlaying, EffectAuditioning, SignalProbing, ExpressionControlling {
    /// The groove and imported songs.
    var playAlong: any BackingTrackManaging { get }
}

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
