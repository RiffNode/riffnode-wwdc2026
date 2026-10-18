import AVFoundation
import Foundation

// MARK: - AudioEngineManager · Pedal Units
// Real boards often carry two of a kind – two drives stacked, a short and a long delay.
// The first pedal of each type plays through the shared unit in EffectUnitsContainer; every
// further one gets an audio unit of its own, created on demand and released when the pedal
// leaves the board. Everything that talks to a pedal's audio goes through `audioUnit(for:)`
// and `kernel(for:)`, so it reaches the right copy.

/// The audio unit (and, for RiffNode's own DSP, its kernel) playing one pedal.
struct PedalUnit {
    let unit: AVAudioUnit
    let kernel: ModulationKernel?
}

extension AudioEngineManager {

    /// True when this pedal is the first of its type on the board (it uses the shared unit).
    func isPrimary(_ effect: EffectNode) -> Bool {
        effectsChain.first(where: { $0.type == effect.type })?.id == effect.id
    }

    /// The audio unit playing this pedal, or nil while its own unit is still being created.
    func audioUnit(for effect: EffectNode) -> AVAudioUnit? {
        if isPrimary(effect) { return effectUnits?.audioUnit(for: effect.type) }
        return extraUnits[effect.id]?.unit
    }

    /// RiffNode's DSP kernel for this pedal (nil for Apple's compressor, EQ and reverb).
    func kernel(for effect: EffectNode) -> ModulationKernel? {
        if isPrimary(effect) { return effectUnits?.kernel(for: effect.type) }
        return extraUnits[effect.id]?.kernel
    }

    /// Switches one pedal in or out without touching the wiring.
    func setBypass(_ unit: AVAudioUnit?, usesKernel: Bool, bypassed: Bool) {
        guard let unit else { return }
        if !usesKernel, let effect = unit as? AVAudioUnitEffect {
            effect.bypass = bypassed
        } else {
            unit.auAudioUnit.shouldBypassEffect = bypassed
        }
    }

    /// Makes sure every second-or-later pedal has its own unit, and lets go of units whose
    /// pedal has left (or become the first of its type). Units RiffNode builds itself are
    /// created asynchronously; the chain is rewired again once they're ready.
    func prepareExtraUnits(on engine: AVAudioEngine) {
        let needed = Set(effectsChain.filter { !isPrimary($0) && $0.type != .equalizer }.map(\.id))

        for (id, pedal) in extraUnits where !needed.contains(id) {
            if engine.attachedNodes.contains(pedal.unit) {
                engine.disconnectNodeOutput(pedal.unit)
                engine.detach(pedal.unit)
            }
            extraUnits[id] = nil
        }

        for effect in effectsChain where needed.contains(effect.id) && extraUnits[effect.id] == nil
            && !pendingExtraUnits.contains(effect.id) {
            switch effect.type {
            case .compressor:
                let unit = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
                    componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor,
                    componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
                engine.attach(unit)
                extraUnits[effect.id] = PedalUnit(unit: unit, kernel: nil)
            case .reverb:
                let unit = AVAudioUnitReverb()
                unit.loadFactoryPreset(.mediumHall)
                engine.attach(unit)
                extraUnits[effect.id] = PedalUnit(unit: unit, kernel: nil)
            case .equalizer:
                break
            default:
                guard let mode = Self.kernelMode(for: effect.type) else { continue }
                let id = effect.id
                pendingExtraUnits.insert(id)
                Task { @MainActor [weak self] in
                    defer { self?.pendingExtraUnits.remove(id) }
                    guard let (unit, kernel) = try? await ModulationAudioUnit.make(mode),
                          let self, self.audioEngine === engine,
                          self.effectsChain.contains(where: { $0.id == id }) else { return }
                    unit.auAudioUnit.shouldBypassEffect = true
                    engine.attach(unit)
                    self.extraUnits[id] = PedalUnit(unit: unit, kernel: kernel)
                    self.connectedNodeIDs = nil      // force the rewire that adds it
                    self.rebuildAudioChain()
                }
            }
        }
    }

    /// Releases every extra unit (a new engine is being built).
    func discardExtraUnits() {
        extraUnits.removeAll()
        pendingExtraUnits.removeAll()
    }

    private static func kernelMode(for type: EffectType) -> ModulationKernel.Mode? {
        switch type {
        case .overdrive: .overdrive
        case .distortion: .distortion
        case .fuzz: .fuzz
        case .chorus: .chorus
        case .phaser: .phaser
        case .flanger: .flanger
        case .tremolo: .tremolo
        case .delay: .analogDelay
        case .compressor, .equalizer, .reverb: nil
        }
    }
}
