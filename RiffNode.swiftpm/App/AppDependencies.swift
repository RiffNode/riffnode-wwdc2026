import Foundation

// MARK: - App Dependencies
// The composition root: the one place that knows the concrete Data types. Everything
// past here – view models and views – sees only the Domain's protocols, so any piece
// can be swapped for a test double.

@MainActor
struct AppDependencies {
    let engine: AudioEngineManager
    let presets: PresetProviding
    let spectrum: any SpectrumAnalyzing
    let chords: any ChordAnalyzing
    let footswitch: any FootswitchListening
    let gestures: any GestureControlling
    let toneAssistant: any ToneAssisting
    let musicApp: any MusicAppControlling
    let songAnalyzer: any SongAnalyzing
    let effectGuide: any EffectGuideServiceProtocol
    let toneStore: any ToneStoring

    /// The real thing: audio engine, analysis, camera, MIDI and on-device AI.
    static func live() -> AppDependencies {
        AppDependencies(
            engine: AudioEngineManager(),
            presets: PresetService(),
            spectrum: FFTAnalyzer(),
            chords: ChordDetector(),
            footswitch: MIDIFootswitch(),
            gestures: VisionGestureController(),
            toneAssistant: SemanticCommandProcessor(),
            musicApp: SystemMusicService(),
            songAnalyzer: SongAnalyzer(),
            effectGuide: EffectGuideService.shared,
            toneStore: ToneAutosaveStore()
        )
    }
}
