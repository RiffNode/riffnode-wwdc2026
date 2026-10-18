import AVFoundation
import Foundation

// MARK: - AudioEngineManager · Audition

extension AudioEngineManager {

    // MARK: - Audition (Learn tab)

    /// Plays the demo riff through `type` alone, with settings exaggerated enough to hear
    /// clearly. The player's chain and EQ are saved and restored by `stopAudition()`.
    func startAudition(_ type: EffectType) {
        guard canPlayDemoRiff else { return }

        if auditionSnapshot == nil {
            let savedChain = effectsChain.map {
                EffectNode(id: $0.id, type: $0.type, isEnabled: $0.isEnabled, parameters: $0.parameters)
            }
            auditionSnapshot = (savedChain, parametricEQBands, !isDemoRiffPlaying, isPedalboardBypassed)
        }
        isPedalboardBypassed = false

        var parameters = type.defaultParameters
        for (key, value) in type.auditionParameters { parameters[key] = value }
        effectsChain = [EffectNode(type: type, isEnabled: true, parameters: parameters)]
        if type == .equalizer {
            var bands = EQBand.defaultBands
            bands[0].gain = parameters["bass"] ?? 0
            bands[4].gain = parameters["mid"] ?? 0
            bands[9].gain = parameters["treble"] ?? 0
            parametricEQBands = bands
        }
        if let node = effectsChain.first { applyEffectParameters(node) }

        auditionEffect = type
        isAuditionBypassed = false
        startDemoRiff()
    }

    /// A/B: bypass the auditioned pedal to hear the dry riff, or bring it back.
    func setAuditionBypassed(_ bypassed: Bool) {
        guard let type = auditionEffect, let node = effectsChain.first(where: { $0.type == type }) else { return }
        if node.isEnabled == bypassed { toggleEffect(node) }
        isAuditionBypassed = bypassed
    }

    func stopAudition() {
        guard let snapshot = auditionSnapshot else { return }
        auditionSnapshot = nil
        auditionEffect = nil
        isAuditionBypassed = false
        if snapshot.startedDemo { stopDemoRiff() }
        effectsChain = snapshot.chain
        parametricEQBands = snapshot.eqBands
        isPedalboardBypassed = snapshot.bypassed
        for effect in effectsChain { applyEffectParameters(effect) }
        syncBypassStates()
    }
}
