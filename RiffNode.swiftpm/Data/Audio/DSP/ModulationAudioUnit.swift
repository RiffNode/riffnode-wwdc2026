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
    }

    /// Set once, before the unit starts rendering.
    var mode: Mode = .tremolo

    // MARK: Parameters (written on the main thread, read on the audio thread)

    private let rateBits = Atomic<UInt32>(Float(1).bitPattern)
    private let depthBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private let mixBits = Atomic<UInt32>(Float(0.5).bitPattern)
    private let feedbackBits = Atomic<UInt32>(Float(0.3).bitPattern)
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

    init() {
        reset()
    }

    deinit {
        delayLine.deallocate()
        allpassInput.deallocate()
        allpassOutput.deallocate()
        phaserFeedbackSample.deallocate()
    }

    func prepare(sampleRate: Float, channelCount: Int) {
        self.sampleRate = max(sampleRate, 8_000)
        self.channelCount = min(max(channelCount, 1), Self.maxChannels)
        reset()
    }

    private func reset() {
        delayLine.initialize(repeating: 0, count: Self.maxChannels * Self.delayLength)
        allpassInput.initialize(repeating: 0, count: Self.maxChannels * Self.phaserStages)
        allpassOutput.initialize(repeating: 0, count: Self.maxChannels * Self.phaserStages)
        phaserFeedbackSample.initialize(repeating: 0, count: Self.maxChannels)
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
                }
            }

            if mode == .chorus || mode == .flanger {
                writeIndex = (writeIndex + 1) & (Self.delayLength - 1)
            }
            lfoPhase += phaseIncrement
            if lfoPhase >= 1 { lfoPhase -= 1 }
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
