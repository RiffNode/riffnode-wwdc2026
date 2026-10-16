import Foundation

// MARK: - Engine Requirements
// What each screen needs from the audio engine, composed from the Domain's small protocols.
// Views depend on these abstractions, never on AudioEngineManager itself, so a screen can
// only reach the capabilities it actually uses (and could run against a test double).

typealias SignalLabEngine = AudioEngineControlling & DemoRiffPlaying & SignalProbing & EffectsChainManaging
typealias PedalboardEngine = SignalLabEngine & AmpControlling & InputStageControlling
typealias LearnEngine = SignalLabEngine & EffectAuditioning & AudioLevelProviding
typealias InputEngine = AudioEngineControlling & AudioLevelProviding & DemoRiffPlaying & InputStageControlling & LatencyReporting
typealias StatusEngine = AudioEngineControlling & AudioLevelProviding & EffectsChainManaging & LatencyReporting
typealias ToneBalanceEngine = EqualizerControlling & DemoRiffPlaying & AudioLevelProviding
typealias PerformanceEngine = EffectsChainManaging & AudioLevelProviding & ExpressionControlling
