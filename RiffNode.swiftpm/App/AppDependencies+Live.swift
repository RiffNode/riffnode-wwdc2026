import Foundation

// MARK: - App Dependencies · Live
// The concrete Data types, named once. Kept apart from the struct so the struct itself
// – and everything built from it – compiles against the Domain alone.

extension AppDependencies {
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
