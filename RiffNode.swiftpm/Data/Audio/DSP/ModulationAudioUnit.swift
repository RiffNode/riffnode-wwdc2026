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

// MARK: - Modulation Kernel

final class ModulationKernel: @unchecked Sendable {

    enum Mode {
        case tremolo, chorus, flanger, phaser
        case overdrive, distortion, fuzz
        case wah
        case amp
    }

    /// Set once, before the unit starts rendering.
    var mode: Mode = .tremolo

    /// The amp and cabinet (mode .amp only).
    let amp = AmpProcessor()

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
    private let dcBlockIn = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
    private let dcBlockOut = UnsafeMutablePointer<Float>.allocate(capacity: maxChannels)
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
        dcBlockIn.deallocate()
        dcBlockOut.deallocate()
        wahLow.deallocate()
        wahBand.deallocate()
    }

    func prepare(sampleRate: Float, channelCount: Int) {
        self.sampleRate = max(sampleRate, 8_000)
        self.channelCount = min(max(channelCount, 1), Self.maxChannels)
        amp.prepare(sampleRate: self.sampleRate)
        reset()
    }

    private func reset() {
        delayLine.initialize(repeating: 0, count: Self.maxChannels * Self.delayLength)
        allpassInput.initialize(repeating: 0, count: Self.maxChannels * Self.phaserStages)
        allpassOutput.initialize(repeating: 0, count: Self.maxChannels * Self.phaserStages)
        phaserFeedbackSample.initialize(repeating: 0, count: Self.maxChannels)
        highPassState.initialize(repeating: 0, count: Self.maxChannels)
        lowPassState.initialize(repeating: 0, count: Self.maxChannels)
        dcBlockIn.initialize(repeating: 0, count: Self.maxChannels)
        dcBlockOut.initialize(repeating: 0, count: Self.maxChannels)
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
        if mode == .amp {
            for channel in 0..<channels {
                guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                      let destination = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                if source != destination { destination.update(from: source, count: frameCount) }
                amp.process(destination, frames: frameCount, channel: channel)
            }
            return
        }

        let rate = self.rate, depth = self.depth, mix = self.mix, feedback = self.feedback
        let phaseIncrement = rate / sampleRate
        let twoPi = 2 * Float.pi

        for frame in 0..<frameCount {
            for channel in 0..<channels {
                guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                      let destination = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }

                // Right channel runs a quarter cycle ahead for stereo width
                let stereoOffset: Float = channel == 1 ? 0.25 : 0
                let lfo = sin(twoPi * (lfoPhase + stereoOffset))  // −1…1
                let dry = source[frame]
                let wet: Float

                switch mode {
                case .tremolo:
                    let gain = 1 - depth * (0.5 + 0.5 * lfo)
                    destination[frame] = dry * gain
                    continue

                case .chorus:
                    let delaySeconds = 0.012 + 0.012 * depth * (0.5 + 0.5 * lfo)
                    wet = readDelay(channel: channel, delaySamples: delaySeconds * sampleRate)
                    writeDelay(channel: channel, value: dry)
                    destination[frame] = dry * (1 - 0.5 * mix) + wet * mix

                case .flanger:
                    let delaySeconds = 0.001 + 0.004 * depth * (0.5 + 0.5 * lfo)
                    wet = readDelay(channel: channel, delaySamples: delaySeconds * sampleRate)
                    writeDelay(channel: channel, value: dry + feedback * wet)
                    destination[frame] = 0.5 * (dry + wet)

                case .phaser:
                    // Exponential sweep 300 Hz → 300 Hz · 10^depth (up to 3 kHz)
                    let sweep = 0.5 + 0.5 * lfo
                    let frequency = 300 * pow(10, depth * sweep)
                    let t = tan(Float.pi * min(frequency, sampleRate * 0.45) / sampleRate)
                    let coefficient = (t - 1) / (t + 1)

                    var signal = dry + feedback * phaserFeedbackSample[channel]
                    for stage in 0..<Self.phaserStages {
                        let index = channel * Self.phaserStages + stage
                        let out = coefficient * signal + allpassInput[index] - coefficient * allpassOutput[index]
                        allpassInput[index] = signal
                        allpassOutput[index] = out
                        signal = out
                    }
                    phaserFeedbackSample[channel] = signal
                    destination[frame] = 0.5 * (dry + signal)

                case .overdrive, .distortion, .fuzz, .wah, .amp:
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
    // Modelled on how the classic circuits work (not component-level emulations):
    //  • Overdrive – Tube Screamer: an op-amp stage with diodes in its feedback loop, 21.5–41.5 dB
    //    of gain applied only above ~720 Hz. The output is the clean signal plus the soft-clipped
    //    part, so the bass stays clean and the mids push forward.
    //  • Distortion – ProCo RAT: up to ~60 dB of op-amp gain, then diodes to ground clip the
    //    wave flat at a fixed ceiling (hard clipping), then a low-pass "filter" control.
    //  • Fuzz – Fuzz Face: two transistors with huge gain and different headroom on each half of
    //    the wave – soft, asymmetric clipping that turns hard as the fuzz goes up.

    private func processDrive(input: UnsafeMutableAudioBufferListPointer,
                              output: UnsafeMutableAudioBufferListPointer,
                              frameCount: Int, channels: Int) {
        let drive = depth, tone = self.tone, level = self.level

        let gainDB: Float = switch mode {
        case .overdrive: 21.5 + drive * 20     // TS808: ×12 … ×118
        case .distortion: 6 + drive * 54       // RAT: up to ~60 dB
        default: 20 + drive * 34               // Fuzz Face
        }
        let gain = pow(10, gainDB / 20)

        // Overdrive clips only what's above 720 Hz; the RAT trims rumble; the fuzz keeps it all
        let splitHz: Float = switch mode {
        case .overdrive: 720
        case .distortion: 60
        default: 20
        }
        let splitCoefficient = exp(-2 * Float.pi * splitHz / sampleRate)
        // Tone: low-pass from 1.2 kHz (dark) to 9 kHz (bright), exponential
        let lowPassHz = 1_200 * pow(7.5, tone)
        let lowPassCoefficient = exp(-2 * Float.pi * lowPassHz / sampleRate)
        // DC blocker after the asymmetric fuzz (the output capacitor's job in the real pedal)
        let dcCoefficient: Float = 0.995
        let outputGain = level * level * 1.6

        for channel in 0..<channels {
            guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                  let destination = output[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
            var lowState = highPassState[channel]   // the part below the split frequency
            var toneState = lowPassState[channel]
            var dcIn = dcBlockIn[channel], dcOut = dcBlockOut[channel]

            for frame in 0..<frameCount {
                let dry = source[frame]
                lowState = (1 - splitCoefficient) * dry + splitCoefficient * lowState
                let x = (dry - lowState) * gain

                var shaped: Float
                switch mode {
                case .overdrive:
                    // Diodes in the feedback loop limit the clipped part to about ±0.5;
                    // the clean signal passes straight through alongside it
                    shaped = dry + 0.5 * tanh(x / 0.5)
                case .distortion:
                    shaped = min(max(x, -0.6), 0.6) / 0.6      // diodes to ground: flat tops
                default:
                    // Different headroom on each half; tanh turns hard as the gain rises
                    shaped = x >= 0 ? 0.6 * tanh(x / 0.6) : 1.0 * tanh(x / 1.0)
                    let blocked = shaped - dcIn + dcCoefficient * dcOut
                    dcIn = shaped
                    dcOut = blocked
                    shaped = blocked * 1.3
                }

                toneState = (1 - lowPassCoefficient) * shaped + lowPassCoefficient * toneState
                destination[frame] = toneState * outputGain
            }
            highPassState[channel] = lowState
            lowPassState[channel] = toneState
            dcBlockIn[channel] = dcIn
            dcBlockOut[channel] = dcOut
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
