import AVFoundation
import AudioToolbox
import Synchronization
#if canImport(CoreAudio)
import CoreAudio  // UnsafeMutableAudioBufferListPointer lives here on Mac Catalyst
#endif

// MARK: - Modulation Audio Unit
// AVFoundation ships delay, reverb, EQ and distortion units, but no modulation effects.
// This in-process Audio Unit implements the four classic ones with real LFO-driven DSP:
//
//  • Tremolo – the volume rises and falls with a sine LFO
//  • Chorus  – a 12–24 ms delay whose time wobbles, detuning a copy of the signal
//  • Flanger – a 1–5 ms swept delay with feedback, the "jet plane" comb filter
//  • Phaser  – six all-pass stages swept between 300 Hz and 3 kHz, carving moving notches
//
// and the three gain pedals, as waveshapers you can watch in the Signal Lab:
//
//  • Overdrive  – soft clipping of the mids and highs, mixed with the clean signal
//  • Distortion – hard clipping at a ceiling: flat tops, strong odd harmonics
//  • Fuzz       – huge gain into asymmetric clipping: close to a square wave
//
// and a wah – a resonant band-pass swept by the player's mouth (gesture control).
//
// Drive sets the gain before the clipper, Tone a low-pass after it, Level the output.
//
// The render block runs on the real-time audio thread: no allocation, no locks.
// Parameters cross threads through atomics; everything else is touched only while rendering.

final class ModulationAudioUnit: AUAudioUnit {

    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x7266_6D64,       // 'rfmd'
        componentManufacturer: 0x5266_6E64,  // 'Rfnd'
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static let registration: Void = {
        AUAudioUnit.registerSubclass(
            ModulationAudioUnit.self,
            as: componentDescription,
            name: "RiffNode: Modulation",
            version: 1
        )
    }()

    /// Creates a ready-to-attach unit running the given effect.
    static func make(_ mode: ModulationKernel.Mode) async throws -> (unit: AVAudioUnit, kernel: ModulationKernel) {
        _ = registration
        let unit = try await AVAudioUnit.instantiate(with: componentDescription, options: [])
        guard let modulation = unit.auAudioUnit as? ModulationAudioUnit else {
            throw AudioEngineError.engineNotSetup
        }
        modulation.kernel.mode = mode
        return (unit, modulation.kernel)
    }

    let kernel = ModulationKernel()

    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputBusArray: AUAudioUnitBusArray!
    private var outputBusArray: AUAudioUnitBusArray!

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
            throw AudioEngineError.engineNotSetup
        }
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 4096
    }

    override var inputBusses: AUAudioUnitBusArray { inputBusArray }
    override var outputBusses: AUAudioUnitBusArray { outputBusArray }
    override var canProcessInPlace: Bool { true }

    override var shouldBypassEffect: Bool {
        get { kernel.isBypassed }
        set { kernel.isBypassed = newValue }
    }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let format = outputBus.format
        kernel.prepare(sampleRate: Float(format.sampleRate), channelCount: Int(format.channelCount))
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let kernel = self.kernel

        return { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }

            // Let upstream render straight into the host's buffers (supplying its own
            // memory where ours is nil), then process in place: each effect reads a
            // sample before writing the same position back.
            var pullFlags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&pullFlags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }

            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            kernel.process(input: buffers, output: buffers, frameCount: Int(frameCount))
            return noErr
        }
    }
}

// MARK: - Atomic Float

/// A Float shared between the main thread (writes) and the audio thread (reads), lock-free.
struct AtomicFloat: ~Copyable {
    private let bits: Atomic<UInt32>
    init(_ value: Float) { bits = Atomic(value.bitPattern) }
    var value: Float {
        get { Float(bitPattern: bits.load(ordering: .relaxed)) }
        nonmutating set { bits.store(newValue.bitPattern, ordering: .relaxed) }
    }
}

// MARK: - Modulation Kernel

final class ModulationKernel: @unchecked Sendable {

    enum Mode {
        case tremolo, chorus, flanger, phaser
        case overdrive, distortion, fuzz
        case wah
        case amp
        case input
        case analogDelay

        /// The pedal family a mode plays, for its standard voicing.
        var effectType: EffectType? {
            switch self {
            case .tremolo: .tremolo
            case .chorus: .chorus
            case .flanger: .flanger
            case .phaser: .phaser
            case .overdrive: .overdrive
            case .distortion: .distortion
            case .fuzz: .fuzz
            case .analogDelay: .delay
            case .wah, .amp, .input: nil
            }
        }
    }

    /// Set once, before the unit starts rendering. Loads the mode's standard voicing.
    var mode: Mode = .tremolo {
        didSet { if let type = mode.effectType, let model = PedalModel.standard(for: type) { setVoicing(model.voicing) } }
    }

    /// The amp and cabinet (mode .amp only).
    let amp = AmpProcessor()
    /// Pickup + cable, volume pedal and noise gate (mode .input only).
    let input = InputProcessor()

    // MARK: Parameters (written on the main thread, read on the audio thread)

    private let rateBits = Atomic<UInt32>(Float(1).bitPattern)
    private let depthBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private let mixBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private let feedbackBits = Atomic<UInt32>(Float(0.3).bitPattern)
    private let toneBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private let levelBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private let bypassFlag = Atomic<Bool>(false)

    /// LFO speed in Hz.
    var rate: Float {
        get { Float(bitPattern: rateBits.load(ordering: .relaxed)) }
        set { rateBits.store(min(max(newValue, 0.01), 20).bitPattern, ordering: .relaxed) }
    }
    /// 0…1
    var depth: Float {
        get { Float(bitPattern: depthBits.load(ordering: .relaxed)) }
        set { depthBits.store(min(max(newValue, 0), 1).bitPattern, ordering: .relaxed) }
    }
    /// Wet/dry balance, 0…1 (chorus).
    var mix: Float {
        get { Float(bitPattern: mixBits.load(ordering: .relaxed)) }
        set { mixBits.store(min(max(newValue, 0), 1).bitPattern, ordering: .relaxed) }
    }
    /// 0…0.95 (flanger, phaser).
    var feedback: Float {
        get { Float(bitPattern: feedbackBits.load(ordering: .relaxed)) }
        set { feedbackBits.store(min(max(newValue, 0), 0.95).bitPattern, ordering: .relaxed) }
    }
    /// Gain pedals: 0 dark … 1 bright.
    var tone: Float {
        get { Float(bitPattern: toneBits.load(ordering: .relaxed)) }
        set { toneBits.store(min(max(newValue, 0), 1).bitPattern, ordering: .relaxed) }
    }
    /// Gain pedals: output volume, 0…1.
    var level: Float {
        get { Float(bitPattern: levelBits.load(ordering: .relaxed)) }
        set { levelBits.store(min(max(newValue, 0), 1).bitPattern, ordering: .relaxed) }
    }
    var isBypassed: Bool {
        get { bypassFlag.load(ordering: .relaxed) }
        set { bypassFlag.store(newValue, ordering: .relaxed) }
    }

    // MARK: Voicing (which classic pedal this is – written on the main thread)

    // Gain pedals
    private let gainMinDB = AtomicFloat(21.5)
    private let gainMaxDB = AtomicFloat(41.5)
    private let splitHz = AtomicFloat(720)
    private let clipping = AtomicFloat(0)
    private let cleanBlend = AtomicFloat(1)
    private let toneKind = AtomicFloat(0)
    private let toneMinHz = AtomicFloat(1_200)
    private let toneMaxHz = AtomicFloat(9_000)
    private let outputTrim = AtomicFloat(1)
    // Modulation
    private let baseDelayMs = AtomicFloat(12)
    private let sweepMs = AtomicFloat(12)
    private let phaserStageCount = AtomicFloat(6)
    private let sweepLowHz = AtomicFloat(300)
    private let sweepDecades = AtomicFloat(1)
    private let stageSpread = AtomicFloat(1)
    private let lfoShape = AtomicFloat(0)
    // Echo
    private let darkenHz = AtomicFloat(2_400)
    private let wowMs = AtomicFloat(0.9)
    private let saturation = AtomicFloat(1)

    /// Makes this unit sound like a particular classic pedal.
    func setVoicing(_ voicing: PedalVoicing) {
        switch voicing {
        case .drive(let d):
            gainMinDB.value = d.gainDB.lowerBound
            gainMaxDB.value = d.gainDB.upperBound
            splitHz.value = d.preHighPassHz
            clipping.value = Float(d.clipping.rawValue)
            cleanBlend.value = d.cleanBlend
            toneKind.value = Float(d.tone.rawValue)
            toneMinHz.value = d.toneRangeHz.lowerBound
            toneMaxHz.value = d.toneRangeHz.upperBound
            outputTrim.value = d.outputTrim
        case .modulation(let m):
            baseDelayMs.value = m.baseDelayMs
            sweepMs.value = m.sweepMs
            phaserStageCount.value = Float(min(max(m.stages, 1), Self.phaserStages))
            sweepLowHz.value = m.sweepLowHz
            sweepDecades.value = m.sweepDecades
            stageSpread.value = m.stageSpread
            lfoShape.value = m.shape
        case .echo(let e):
            darkenHz.value = e.darkenHz
            wowMs.value = e.wowMs
            saturation.value = e.saturation
        case .standard:
            break
        }
    }

    // MARK: Render state (audio thread)

    private static let maxChannels = 2
    private static let delayLength = 8192        // > 50 ms at 96 kHz, power of two
    private static let phaserStages = 6

    private var sampleRate: Float = 44_100
    private var channelCount = 2
    private var lfoPhase: Float = 0

    private let delayLine = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels * delayLength)
    private var writeIndex = 0

    private let allpassInput = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels * phaserStages)
    private let allpassOutput = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels * phaserStages)
    private let phaserFeedbackSample = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    /// Gain pedals: one-pole filter states (bass cut before, tone after the clipper).
    private let highPassState = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private let lowPassState = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private let scoopHighState = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private let dcBlockIn = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private let dcBlockOut = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private let oversamplePrevious = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    /// Analog delay: up to ~2.7 s at 96 kHz per channel, allocated in prepare() (not on the audio thread).
    private static let longDelayLength = 1 << 18
    private var longDelay: UnsafeMutablePointer<Float>?
    private let delayFilterState = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private var longWriteIndex = 0
    /// Wah: state-variable filter states and the smoothed pedal position.
    private let wahLow = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private let wahBand = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private var wahPosition: Float = 0.5

    init() {
        reset()
    }

    deinit {
        delayLine.deallocate()
        allpassInput.deallocate()
        allpassOutput.deallocate()
        phaserFeedbackSample.deallocate()
        highPassState.deallocate()
        lowPassState.deallocate()
        scoopHighState.deallocate()
        dcBlockIn.deallocate()
        dcBlockOut.deallocate()
        oversamplePrevious.deallocate()
        delayFilterState.deallocate()
        longDelay?.deallocate()
        wahLow.deallocate()
        wahBand.deallocate()
    }

    func prepare(sampleRate: Float, channelCount: Int) {
        self.sampleRate = max(sampleRate, 8_000)
        self.channelCount = min(max(channelCount, 1), Self.maxChannels)
        amp.prepare(sampleRate: self.sampleRate)
        input.prepare(sampleRate: self.sampleRate)
        if mode == .analogDelay && longDelay == nil {
            longDelay = UnsafeMutablePointer<Float>.allocate(capacity: Self.maxChannels * Self.longDelayLength)
        }
        reset()
    }

    private func reset() {
        delayLine.initialize(repeating: 0, count: Self.maxChannels * Self.delayLength)
        allpassInput.initialize(repeating: 0, count: Self.maxChannels * Self.phaserStages)
        allpassOutput.initialize(repeating: 0, count: Self.maxChannels * Self.phaserStages)
        phaserFeedbackSample.initialize(repeating: 0, count: Self.maxChannels)
        highPassState.initialize(repeating: 0, count: Self.maxChannels)
        lowPassState.initialize(repeating: 0, count: Self.maxChannels)
        scoopHighState.initialize(repeating: 0, count: Self.maxChannels)
        dcBlockIn.initialize(repeating: 0, count: Self.maxChannels)
        dcBlockOut.initialize(repeating: 0, count: Self.maxChannels)
        oversamplePrevious.initialize(repeating: 0, count: Self.maxChannels)
        delayFilterState.initialize(repeating: 0, count: Self.maxChannels)
        longDelay?.update(repeating: 0, count: Self.maxChannels * Self.longDelayLength)
        longWriteIndex = 0
        wahLow.initialize(repeating: 0, count: Self.maxChannels)
        wahBand.initialize(repeating: 0, count: Self.maxChannels)
        writeIndex = 0
        lfoPhase = 0
    }

    // MARK: Processing

    func process(input: UnsafeMutableAudioBufferListPointer,
                 output: UnsafeMutableAudioBufferListPointer,
                 frameCount: Int) {
        let channels = min(channelCount, input.count, output.count)
        guard channels > 0 else { return }

        if isBypassed {
            for channel in 0..<channels {
                guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                      let destination = output[channel].mData?.assumingMemoryBound(to: Float.self),
                      source != destination else { continue }
                destination.update(from: source, count: frameCount)
            }
            return
        }

        if mode == .overdrive || mode == .distortion || mode == .fuzz {
            processDrive(input: input, output: output, frameCount: frameCount, channels: channels)
            return
        }
        if mode == .wah {
            processWah(input: input, output: output, frameCount: frameCount, channels: channels)
            return
        }
        if mode == .input {
            guard let left = output[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            for channel in 0..<channels {
                guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                      let destination = output[channel].mData?.assumingMemoryBound(to: Float.self),
                      source != destination else { continue }
                destination.update(from: source, count: frameCount)
            }
            let right = channels > 1 ? output[1].mData?.assumingMemoryBound(to: Float.self) : nil
            self.input.process(left, right, frames: frameCount)
            return
        }
        if mode == .analogDelay {
            processAnalogDelay(input: input, output: output, frameCount: frameCount, channels: channels)
            return
        }
        if mode == .amp {
            for channel in 0..<channels {
                guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                      let destination = output[channel].mData?.assumingMemoryBound(to: Float.self),
                      source != destination else { continue }
                destination.update(from: source, count: frameCount)
            }
            // A neural capture is mono: run it once on the left channel and copy it across
            if let left = output[0].mData?.assumingMemoryBound(to: Float.self) {
                amp.processNeural(left, frames: frameCount)
                if amp.usesNeuralModel, channels > 1, let right = output[1].mData?.assumingMemoryBound(to: Float.self) {
                    right.update(from: left, count: frameCount)
                }
            }
            for channel in 0..<channels {
                guard let destination = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                amp.process(destination, frames: frameCount, channel: channel)
            }
            return
        }

        let rate = self.rate, depth = self.depth, mix = self.mix, feedback = self.feedback
        let phaseIncrement = rate / sampleRate
        let twoPi = 2 * Float.pi
        let baseDelay = baseDelayMs.value / 1000, sweep = sweepMs.value / 1000
        let stages = Int(phaserStageCount.value)
        let lowHz = sweepLowHz.value, decades = sweepDecades.value, spread = stageSpread.value
        let shape = lfoShape.value
        let squareness = 1 + 9 * shape
        let squareNorm = tanh(squareness)

        for frame in 0..<frameCount {
            for channel in 0..<channels {
                guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                      let destination = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }

                // Right channel runs a quarter cycle ahead for stereo width
                let stereoOffset: Float = channel == 1 ? 0.25 : 0
                let sine = sin(twoPi * (lfoPhase + stereoOffset))  // −1…1
                // Tremolo squares the wave off; a vibe lingers low and swells up like a lamp
                let lfo: Float = switch mode {
                case .tremolo: shape > 0 ? tanh(sine * squareness) / squareNorm : sine
                case .phaser: shape > 0 ? 2 * pow(0.5 + 0.5 * sine, 1 + 2 * shape) - 1 : sine
                default: sine
                }
                let dry = source[frame]
                let wet: Float

                switch mode {
                case .tremolo:
                    let gain = 1 - depth * (0.5 + 0.5 * lfo)
                    destination[frame] = dry * gain
                    continue

                case .chorus:
                    let delaySeconds = baseDelay + sweep * depth * (0.5 + 0.5 * lfo)
                    wet = readDelay(channel: channel, delaySamples: delaySeconds * sampleRate)
                    writeDelay(channel: channel, value: dry)
                    destination[frame] = dry * (1 - 0.5 * mix) + wet * mix

                case .flanger:
                    let delaySeconds = baseDelay + sweep * depth * (0.5 + 0.5 * lfo)
                    wet = readDelay(channel: channel, delaySamples: delaySeconds * sampleRate)
                    writeDelay(channel: channel, value: dry + feedback * wet)
                    destination[frame] = 0.5 * (dry + wet)

                case .phaser:
                    // Exponential sweep: lowest notch → lowest · 10^(depth · decades)
                    let position = 0.5 + 0.5 * lfo
                    let frequency = lowHz * pow(10, depth * decades * position)
                    let t = tan(Float.pi * min(frequency, sampleRate * 0.45) / sampleRate)
                    var coefficient = (t - 1) / (t + 1)

                    var signal = dry + feedback * phaserFeedbackSample[channel]
                    for stage in 0..<stages {
                        if spread != 1 && stages > 1 {
                            // Mismatched stages: each one centred a little higher than the last
                            let offset = Float(stage) / Float(stages - 1) - 0.5
                            let f = frequency * pow(spread, offset)
                            let ts = tan(Float.pi * min(f, sampleRate * 0.45) / sampleRate)
                            coefficient = (ts - 1) / (ts + 1)
                        }
                        let index = channel * Self.phaserStages + stage
                        let out = coefficient * signal + allpassInput[index] - coefficient * allpassOutput[index]
                        allpassInput[index] = signal
                        allpassOutput[index] = out
                        signal = out
                    }
                    phaserFeedbackSample[channel] = signal
                    destination[frame] = 0.5 * (dry + signal)

                case .overdrive, .distortion, .fuzz, .wah, .amp, .input, .analogDelay:
                    continue  // handled by processDrive / processWah
                }
            }

            if mode == .chorus || mode == .flanger {
                writeIndex = (writeIndex + 1) & (Self.delayLength - 1)
            }
            lfoPhase += phaseIncrement
            if lfoPhase >= 1 { lfoPhase -= 1 }
        }
    }

    // MARK: Gain pedals
    // One processor for every gain pedal, voiced by how the classic circuits work (not
    // component-level emulations): a bass cut before the clipper, gain, a clipping curve,
    // an optional clean blend, then a tone control. See `PedalVoicing.Drive`.

    private func processDrive(input: UnsafeMutableAudioBufferListPointer,
                              output: UnsafeMutableAudioBufferListPointer,
                              frameCount: Int, channels: Int) {
        let drive = depth, tone = self.tone, level = self.level
        let gain = pow(10, (gainMinDB.value + drive * (gainMaxDB.value - gainMinDB.value)) / 20)
        let splitCoefficient = exp(-2 * Float.pi * splitHz.value / sampleRate)
        let clip = Int(clipping.value)
        let blend = cleanBlend.value
        let toneMode = Int(toneKind.value)
        let lowHz = toneMinHz.value, highHz = toneMaxHz.value
        // Low-pass tone: opens exponentially from lowHz to highHz. Mid-scoop: a low-pass at
        // lowHz blended with a high-pass at highHz. Fixed: a low-pass at lowHz.
        let lowPassHz = toneMode == 0 ? lowHz * pow(highHz / lowHz, tone) : lowHz
        let lowPassCoefficient = exp(-2 * Float.pi * lowPassHz / sampleRate)
        let scoopCoefficient = exp(-2 * Float.pi * highHz / sampleRate)
        // Asymmetric clipping leaves DC behind: block it (the output capacitor's job)
        let needsDCBlock = clip == 2 || clip == 6 || clip == 3
        let dcCoefficient: Float = 0.995
        let outputGain = level * level * 1.6 * outputTrim.value

        for channel in 0..<channels {
            guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                  let destination = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
            var lowState = highPassState[channel]   // the part below the split frequency
            var toneState = lowPassState[channel]
            var scoopState = scoopHighState[channel]
            var dcIn = dcBlockIn[channel], dcOut = dcBlockOut[channel]

            for frame in 0..<frameCount {
                let dry = source[frame]
                lowState = (1 - splitCoefficient) * dry + splitCoefficient * lowState
                let x = (dry - lowState) * gain

                // 4× oversampling: clipping creates harmonics above Nyquist that would fold back
                // as harsh aliasing. Clip four interpolated points per sample and average them.
                let previous = oversamplePrevious[channel]
                var clipped: Float = 0
                for step in 1...4 {
                    clipped += Self.clip(previous + (x - previous) * Float(step) * 0.25, kind: clip)
                }
                oversamplePrevious[channel] = x
                clipped *= 0.25

                if needsDCBlock {
                    let blocked = clipped - dcIn + dcCoefficient * dcOut
                    dcIn = clipped
                    dcOut = blocked
                    clipped = blocked * 1.3
                }
                let shaped = blend * dry + clipped

                toneState = (1 - lowPassCoefficient) * shaped + lowPassCoefficient * toneState
                var y = toneState
                if toneMode == 1 {
                    scoopState = (1 - scoopCoefficient) * shaped + scoopCoefficient * scoopState
                    let highPassed = shaped - scoopState
                    y = (1 - tone) * toneState + tone * highPassed * 1.6
                }
                destination[frame] = y * outputGain
            }
            highPassState[channel] = lowState
            lowPassState[channel] = toneState
            scoopHighState[channel] = scoopState
            dcBlockIn[channel] = dcIn
            dcBlockOut[channel] = dcOut
        }
    }

    /// The clipping curves, by `PedalVoicing.Drive.Clipping` raw value.
    @inline(__always)
    private static func clip(_ x: Float, kind: Int) -> Float {
        switch kind {
        case 0: return 0.5 * tanh(x / 0.5)                                   // diodes in feedback
        case 1: return min(max(x, -0.6), 0.6) / 0.6                          // diodes to ground
        case 2: return x >= 0 ? 0.6 * tanh(x / 0.6) : tanh(x)                // two-transistor fuzz
        case 3: return x >= 0 ? x / pow(1 + pow(x, 2.5), 0.4) : tanh(x)      // MOSFET soft knee
        case 4: return 0.6 * tanh(x / 0.35)                                  // germanium, low threshold
        case 5: return tanh(2.5 * tanh(x))                                   // two stages in a row
        default: return x >= 0 ? 0.5 * tanh(x / 0.5) : 0.7 * tanh(x / 0.7)  // asymmetric soft
        }
    }

    // MARK: Analog Delay

    /// A bucket-brigade / tape style echo: each repeat runs through a low-pass and a soft
    /// saturator, so echoes get darker and warmer as they fade, and a slow "wow" LFO wobbles
    /// the delay time like a tape transport. `rate` = delay time (s), `feedback`, `mix`.
    private func processAnalogDelay(input source: UnsafeMutableAudioBufferListPointer,
                                    output: UnsafeMutableAudioBufferListPointer,
                                    frameCount: Int, channels: Int) {
        guard let line = longDelay else { return }
        let time = min(max(rate, 0.02), 2.5)
        let feedback = self.feedback, mix = self.mix
        let mask = Self.longDelayLength - 1
        let darkenFrequency = darkenHz.value
        let darken = darkenFrequency > 0 ? 1 - exp(-2 * Float.pi * darkenFrequency / sampleRate) : 1   // 1 = clean
        let warmth = saturation.value
        let wowIncrement: Float = 0.55 / sampleRate
        let wowDepth = wowMs.value / 1000 * sampleRate

        for frame in 0..<frameCount {
            let wow = sin(2 * Float.pi * lfoPhase) * wowDepth
            let delaySamples = min(Float(mask - 2), max(1, time * sampleRate + wow))
            for channel in 0..<channels {
                guard let src = source[channel].mData?.assumingMemoryBound(to: Float.self),
                      let dst = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = line + channel * Self.longDelayLength
                let position = Float(longWriteIndex) - delaySamples
                let i0 = Int(position.rounded(.down))
                let fraction = position - Float(i0)
                let a = base[i0 & mask], b = base[(i0 + 1) & mask]
                let echo = a + (b - a) * fraction

                // Darken, then saturate gently – what the repeats go through on each lap
                delayFilterState[channel] += (echo - delayFilterState[channel]) * darken
                let warm = delayFilterState[channel]
                let dry = src[frame]
                let echoBack = warm * feedback
                base[longWriteIndex] = dry + (warmth > 0 ? tanh(echoBack * 1.1) / 1.1 : echoBack)
                dst[frame] = dry + warm * mix
            }
            longWriteIndex = (longWriteIndex + 1) & mask
            lfoPhase += wowIncrement
            if lfoPhase >= 1 { lfoPhase -= 1 }
        }
    }

    // MARK: Wah

    /// A Cry Baby–style wah: a resonant band-pass (Q ≈ 4) whose centre sweeps from 350 Hz
    /// (heel down) to 2.2 kHz (toe down). `depth` is the pedal position – here, how far the
    /// player's mouth is open. The position is smoothed per sample so the sweep never zips.
    private func processWah(input: UnsafeMutableAudioBufferListPointer,
                            output: UnsafeMutableAudioBufferListPointer,
                            frameCount: Int, channels: Int) {
        let target = depth
        let damping: Float = 1 / 4          // 1/Q
        let smoothing: Float = 1 - exp(-1 / (0.02 * sampleRate))   // ~20 ms glide

        for frame in 0..<frameCount {
            wahPosition += (target - wahPosition) * smoothing
            let centre = 350 * pow(2_200 / 350, wahPosition)
            let f = 2 * sin(Float.pi * min(centre, sampleRate * 0.2) / sampleRate)

            for channel in 0..<channels {
                guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                      let destination = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                // Chamberlin state-variable filter
                let dry = source[frame]
                let low = wahLow[channel] + f * wahBand[channel]
                let high = dry - low - damping * wahBand[channel]
                let band = wahBand[channel] + f * high
                wahLow[channel] = low
                wahBand[channel] = band
                destination[frame] = band * 0.6 + dry * 0.1
            }
        }
    }

    private func writeDelay(channel: Int, value: Float) {
        delayLine[channel * Self.delayLength + writeIndex] = value
    }

    /// Linear-interpolated read `delaySamples` behind the write head.
    private func readDelay(channel: Int, delaySamples: Float) -> Float {
        let mask = Self.delayLength - 1
        let position = Float(writeIndex) - max(1, delaySamples)
        let base = Int(position.rounded(.down))
        let fraction = position - Float(base)
        let first = delayLine[channel * Self.delayLength + (base & mask)]
        let second = delayLine[channel * Self.delayLength + ((base + 1) & mask)]
        return first + (second - first) * fraction
    }
}
