import AVFoundation
import Foundation

// MARK: - AudioEngineManager · Chain Sync
// Keeps the audio units in step with the effects chain: bypass states, knob values,
// and rewiring when the pedal order changes.

extension AudioEngineManager {

    /// Sync bypass state for all effects
    func syncBypassStates() {
        guard let units = effectUnits else { return }
        
        // Create a set of enabled effect types
        var enabledTypes = Set<EffectType>()
        for effect in effectsChain where effect.isEnabled && !isPedalboardBypassed {
            enabledTypes.insert(effect.type)
        }
        
        // Set bypass for all effect units
        units.compressor.bypass = !enabledTypes.contains(.compressor)
        units.overdrive.auAudioUnit.shouldBypassEffect = !enabledTypes.contains(.overdrive)
        units.distortion.auAudioUnit.shouldBypassEffect = !enabledTypes.contains(.distortion)
        units.fuzz.auAudioUnit.shouldBypassEffect = !enabledTypes.contains(.fuzz)
        for type in [EffectType.chorus, .phaser, .flanger, .tremolo] {
            units.setBypass(for: type, bypassed: !enabledTypes.contains(type))
        }
        units.delay.auAudioUnit.shouldBypassEffect = !enabledTypes.contains(.delay)
        units.reverb.bypass = !enabledTypes.contains(.reverb)
        units.equalizer?.bypass = !enabledTypes.contains(.equalizer)
        units.wah.auAudioUnit.shouldBypassEffect = isPedalboardBypassed || !isWahActive
        
        Log.audio.debug("syncBypassStates: Bypass states synchronized")
    }
    /// Coalesces several edits in one turn of the run loop (e.g. append + sort) into one rewire.
    func scheduleAudioChainRebuild() {
        guard !isChainRebuildScheduled else { return }
        isChainRebuildScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isChainRebuildScheduled = false
            self.rebuildAudioChain()
        }
    }
    /// Gain pedals: Drive, Tone and Level knobs (0–100) straight onto the waveshaper.
    private func setDrive(_ kernel: ModulationKernel, _ effect: EffectNode, driveKey: String) {
        kernel.depth = (effect.parameters[driveKey] ?? 50) / 100
        kernel.tone = (effect.parameters["tone"] ?? 50) / 100
        kernel.level = (effect.parameters["level"] ?? 50) / 100
    }
    func applyEffectParameters(_ effect: EffectNode) {
        guard let units = effectUnits else { return }

        switch effect.type {
        case .compressor:
            // Apple Dynamics Processor parameters (set via C AU API):
            //   param 0 = Threshold    (-40 to +20 dB,  default -20)
            //   param 1 = HeadRoom     (0.1 to 40 dB,   default 5)  — relates to ratio
            //   param 4 = AttackTime   (0.0001 to 0.2s, default 0.001)
            //   param 5 = ReleaseTime  (0.01 to 3s,     default 0.024)
            //   param 6 = MasterGain   (-40 to +40 dB,  default 0)  — makeup gain
            let threshold = effect.parameters["threshold"] ?? -20
            let ratio     = effect.parameters["ratio"]     ?? 4
            let attackMs  = effect.parameters["attack"]    ?? 10
            let releaseMs = effect.parameters["release"]   ?? 100
            // Map ratio (1–20) to headRoom (40–2 dB): higher ratio = tighter = less headroom
            let headRoom  = max(2.0, min(40.0, 40.0 / ratio))
            let au = units.compressor.audioUnit
            AudioUnitSetParameter(au, 0, kAudioUnitScope_Global, 0, threshold, 0)
            AudioUnitSetParameter(au, 1, kAudioUnitScope_Global, 0, headRoom, 0)
            AudioUnitSetParameter(au, 4, kAudioUnitScope_Global, 0, attackMs / 1000.0, 0)
            AudioUnitSetParameter(au, 5, kAudioUnitScope_Global, 0, releaseMs / 1000.0, 0)

        case .equalizer:
            // A graph rebuild must not overwrite edits made on the parametric curve.
            applyParametricEQ()

        case .overdrive:
            setDrive(units.overdriveKernel, effect, driveKey: "drive")

        case .distortion:
            setDrive(units.distortionKernel, effect, driveKey: "drive")

        case .fuzz:
            setDrive(units.fuzzKernel, effect, driveKey: "fuzz")

        case .chorus:
            let kernel = units.chorusKernel
            kernel.rate = effect.parameters["rate"] ?? 1.0          // 0.1–10 Hz
            kernel.depth = (effect.parameters["depth"] ?? 50) / 100
            kernel.mix = (effect.parameters["mix"] ?? 50) / 100

        case .phaser:
            let kernel = units.phaserKernel
            kernel.rate = effect.parameters["rate"] ?? 0.5          // 0.1–5 Hz
            kernel.depth = (effect.parameters["depth"] ?? 50) / 100
            kernel.feedback = (effect.parameters["feedback"] ?? 30) / 100 * 0.9

        case .flanger:
            let kernel = units.flangerKernel
            kernel.rate = effect.parameters["rate"] ?? 0.3          // 0.1–2 Hz
            kernel.depth = (effect.parameters["depth"] ?? 50) / 100
            kernel.feedback = (effect.parameters["feedback"] ?? 50) / 100 * 0.9

        case .tremolo:
            let kernel = units.tremoloKernel
            kernel.rate = effect.parameters["rate"] ?? 5.0          // 0.5–15 Hz
            kernel.depth = (effect.parameters["depth"] ?? 50) / 100

        case .delay:
            units.delayKernel.rate = effect.parameters["time"] ?? 0.3
            units.delayKernel.feedback = (effect.parameters["feedback"] ?? 40) / 100
            units.delayKernel.mix = (effect.parameters["mix"] ?? 30) / 100

        case .reverb:
            units.reverb.wetDryMix = effect.parameters["wetDryMix"] ?? 40
            if let decay = effect.parameters["decay"] {
                selectReverbPreset(decaySeconds: decay)
            }
        }
    }
}
