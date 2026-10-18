import AVFoundation
import AudioToolbox

// MARK: - Effect Units Container
// Following Clean Architecture: Infrastructure Layer
// Following Single Responsibility: Only manages audio unit instances

final class EffectUnitsContainer {
    // Dynamics — real Apple Dynamics Processor AU (not a distortion simulation)
    let compressor: AVAudioUnitEffect
    
    // Filter & Pitch
    let equalizer: AVAudioUnitEQ?
    
    // Gain / Dirt – real waveshapers (see ModulationAudioUnit)
    let overdrive: AVAudioUnit
    let distortion: AVAudioUnit
    let fuzz: AVAudioUnit
    let overdriveKernel: ModulationKernel
    let distortionKernel: ModulationKernel
    let fuzzKernel: ModulationKernel

    /// Mouth-controlled wah – always first in the chain, bypassed unless gesture control drives it.
    let wah: AVAudioUnit
    let wahKernel: ModulationKernel

    /// Amp and speaker cabinet – always last, like the amp a real pedalboard plugs into.
    let amp: AVAudioUnit
    let ampKernel: ModulationKernel

    /// Pickup + cable, volume pedal and noise gate – always first, before the wah.
    let input: AVAudioUnit
    let inputKernel: ModulationKernel
    
    // Modulation – real LFO-driven DSP (see ModulationAudioUnit)
    let chorus: AVAudioUnit
    let phaser: AVAudioUnit
    let flanger: AVAudioUnit
    let tremolo: AVAudioUnit
    let chorusKernel: ModulationKernel
    let phaserKernel: ModulationKernel
    let flangerKernel: ModulationKernel
    let tremoloKernel: ModulationKernel

    /// Modulation units are custom Audio Units, which AVFoundation instantiates asynchronously.
    static func make() async throws -> EffectUnitsContainer {
        let chorus = try await ModulationAudioUnit.make(.chorus)
        let phaser = try await ModulationAudioUnit.make(.phaser)
        let flanger = try await ModulationAudioUnit.make(.flanger)
        let tremolo = try await ModulationAudioUnit.make(.tremolo)
        let overdrive = try await ModulationAudioUnit.make(.overdrive)
        let distortion = try await ModulationAudioUnit.make(.distortion)
        let fuzz = try await ModulationAudioUnit.make(.fuzz)
        let wah = try await ModulationAudioUnit.make(.wah)
        let amp = try await ModulationAudioUnit.make(.amp)
        let input = try await ModulationAudioUnit.make(.input)
        let delay = try await ModulationAudioUnit.make(.analogDelay)
        return EffectUnitsContainer(chorus: chorus, phaser: phaser, flanger: flanger, tremolo: tremolo,
                                    overdrive: overdrive, distortion: distortion, fuzz: fuzz, wah: wah, amp: amp, input: input, delay: delay)
    }
    
    // Time & Ambience
    let delay: AVAudioUnit
    let delayKernel: ModulationKernel
    let reverb: AVAudioUnitReverb

    private init(
        chorus chorusUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        phaser phaserUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        flanger flangerUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        tremolo tremoloUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        overdrive overdriveUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        distortion distortionUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        fuzz fuzzUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        wah wahUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        amp ampUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        input inputUnit: (unit: AVAudioUnit, kernel: ModulationKernel),
        delay delayUnit: (unit: AVAudioUnit, kernel: ModulationKernel)
    ) {
        // Dynamics — Apple's real Dynamics Processor (hardware compressor AU)
        let compDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        compressor = AVAudioUnitEffect(audioComponentDescription: compDesc)
        compressor.bypass = true
        
        // 10-band Parametric EQ
        // Frequencies: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz
        equalizer = AVAudioUnitEQ(numberOfBands: 10)
        if let eq = equalizer {
            let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
            for (index, freq) in frequencies.enumerated() {
                eq.bands[index].filterType = index == 0 ? .lowShelf : (index == 9 ? .highShelf : .parametric)
                eq.bands[index].frequency = freq
                eq.bands[index].bandwidth = 1.0
                eq.bands[index].gain = 0
                eq.bands[index].bypass = false
            }
        }
        
        // Overdrive (soft clip), distortion (hard clip), fuzz (asymmetric square-ish clip)
        (overdrive, overdriveKernel) = overdriveUnit
        (distortion, distortionKernel) = distortionUnit
        (fuzz, fuzzKernel) = fuzzUnit

        (chorus, chorusKernel) = chorusUnit
        (phaser, phaserKernel) = phaserUnit
        (flanger, flangerKernel) = flangerUnit
        (tremolo, tremoloKernel) = tremoloUnit
        (wah, wahKernel) = wahUnit
        (amp, ampKernel) = ampUnit
        (input, inputKernel) = inputUnit
        (delay, delayKernel) = delayUnit
        for unit in [chorus, phaser, flanger, tremolo, overdrive, distortion, fuzz, wah, delay] {
            unit.auAudioUnit.shouldBypassEffect = true
        }

        // Delay – analog-style echo in the custom Audio Unit (see ModulationAudioUnit)
        delayKernel.rate = 0.3
        delayKernel.feedback = 0.4
        delayKernel.mix = 0.3

        // Reverb
        reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 40
        reverb.bypass = true
    }

    /// Every unit, so wiring code can disconnect them all without listing them again.
    var allUnits: [AVAudioUnit] {
        EffectType.allCases.compactMap { audioUnit(for: $0) } + [wah, amp, input]
    }

    func audioUnit(for type: EffectType) -> AVAudioUnit? {
        switch type {
        case .compressor: return compressor
        case .equalizer: return equalizer
        case .overdrive: return overdrive
        case .distortion: return distortion
        case .fuzz: return fuzz
        case .chorus: return chorus
        case .phaser: return phaser
        case .flanger: return flanger
        case .tremolo: return tremolo
        case .delay: return delay
        case .reverb: return reverb
        }
    }
    
    /// The custom DSP kernel playing this effect type (nil for Apple's own units).
    func kernel(for type: EffectType) -> ModulationKernel? {
        switch type {
        case .overdrive: overdriveKernel
        case .distortion: distortionKernel
        case .fuzz: fuzzKernel
        case .chorus: chorusKernel
        case .phaser: phaserKernel
        case .flanger: flangerKernel
        case .tremolo: tremoloKernel
        case .delay: delayKernel
        case .compressor, .equalizer, .reverb: nil
        }
    }

    /// Set bypass state for a specific effect type
    /// AVAudioUnit base class doesn't have bypass, so we access concrete types directly
    func setBypass(for type: EffectType, bypassed: Bool) {
        switch type {
        case .compressor:
            compressor.bypass = bypassed
        case .equalizer:
            equalizer?.bypass = bypassed
        case .overdrive:
            overdrive.auAudioUnit.shouldBypassEffect = bypassed
        case .distortion:
            distortion.auAudioUnit.shouldBypassEffect = bypassed
        case .fuzz:
            fuzz.auAudioUnit.shouldBypassEffect = bypassed
        case .chorus:
            chorus.auAudioUnit.shouldBypassEffect = bypassed
        case .phaser:
            phaser.auAudioUnit.shouldBypassEffect = bypassed
        case .flanger:
            flanger.auAudioUnit.shouldBypassEffect = bypassed
        case .tremolo:
            tremolo.auAudioUnit.shouldBypassEffect = bypassed
        case .delay:
            delay.auAudioUnit.shouldBypassEffect = bypassed
        case .reverb:
            reverb.bypass = bypassed
        }
    }
}
