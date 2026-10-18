import AVFoundation
import AudioToolbox
import Observation
import os

// MARK: - Audio Engine Manager
// Following Clean Architecture: Infrastructure Layer
// Implements segregated protocols following Interface Segregation Principle
// Single class coordinates audio operations but delegates to focused components

@Observable
@MainActor
final class AudioEngineManager: AudioManaging {

    // MARK: - State Properties (AudioEngineProtocol)

    private(set) var isRunning = false
    private(set) var hasPermission = false
    var errorMessage: String?

    // MARK: - Audio Input Device Properties

    var currentInputDeviceName: String = "No Input"
    var currentInputDeviceType: AudioInputDeviceType = .none
    var availableInputDevices: [AudioInputDevice] = []

    // MARK: - Visualization Properties (AudioVisualizationProviding)

    var waveformSamples: [Float] = Array(repeating: 0, count: 128)
    var inputLevel: Float = 0
    var outputLevel: Float = 0

    // MARK: - Audio Analysis Callbacks (for AI features)

    /// Callback for raw audio samples (used by FFT analyzer, chord detector)
    /// This callback runs on MainActor for thread safety with @Observable analyzers
    var onAudioSamplesAvailable: (@MainActor ([Float]) -> Void)?

    /// Sample rate of the audio handed to `onAudioSamplesAvailable` (mic and demo riff share it).
    var analysisSampleRate: Double {
        processingFormat?.sampleRate ?? inputNode?.outputFormat(forBus: 0).sampleRate ?? 44100
    }

    /// Latest audio samples buffer for analysis
    var latestAudioSamples: [Float] = []
    private let analysisBufferSize = 4096

    // MARK: - Effects Chain (EffectsChainManaging)

    /// Adding, removing, reordering or replacing pedals (presets, AI) rewires the audio graph.
    var effectsChain: [EffectNode] = [] {
        didSet { scheduleAudioChainRebuild() }
    }
    var isPedalboardBypassed = false {
        didSet { if oldValue != isPedalboardBypassed { syncBypassStates() } }
    }
    /// The pedal order currently wired into the audio graph (nil = not wired yet).
    @ObservationIgnored var connectedEffectOrder: [EffectType]?
    @ObservationIgnored var isChainRebuildScheduled = false

    /// The most recently applied preset, and a counter that bumps on every apply
    /// (so re-applying the same preset is still observable).
    private(set) var currentPreset: EffectPreset?
    private(set) var presetApplyCount = 0

    // MARK: - Play Along

    /// The groove, imported songs – everything you play along with.
    let backingTrack = BackingTrackPlayer()
    var playAlong: any BackingTrackManaging { backingTrack }

    // MARK: - Practice Tools
    let metronome = MetronomePlayer()
    let looper = Looper()
    var metronomeControls: any MetronomeControlling { metronome }
    var looperControls: any LooperControlling { looper }
    @ObservationIgnored private var looperTapInstalled = false

    // MARK: - Private Audio Components

    private var audioEngine: AVAudioEngine?
    var inputNode: AVAudioInputNode?
    var mainMixer: AVAudioMixerNode?

    // Effect units - following composition over inheritance
    var effectUnits: EffectUnitsContainer?
    
    // Format conversion mixer - used to resolve incompatibility between input format and effect units
    var formatConverterMixer: AVAudioMixerNode?

    // Pre-effects mixer — both guitar and (optionally) backing track feed into this
    var fxInputMixer: AVAudioMixerNode?

    // Audition – hear one effect on its own, A/B against the dry riff (Learn tab)
    var auditionEffect: EffectType?
    var isAuditionBypassed = false
    @ObservationIgnored var auditionSnapshot: (chain: [EffectNode], eqBands: [EQBand], startedDemo: Bool, bypassed: Bool)?

    // Demo source – a clean performance or the original synthesized arpeggio.
    let demoRiff = DemoRiffPlayer()

    // Visualization
    var tapInstalled = false

    // Signal Lab – taps on both sides of one pedal
    @ObservationIgnored let signalProbe = SignalProbeStore()
    @ObservationIgnored let outputLevelStore = OutputLevelStore()
    @ObservationIgnored var probedNodes: [AVAudioNode] = []
    /// The pedal whose input and output the Signal Lab is watching.
    var probedEffectType: EffectType?
    
    // Store processing format for rebuilding audio chain
    var processingFormat: AVAudioFormat?
    
    // Configuration change observer
    private var configurationObserver: Any?

    // MARK: - Visualization & Signal Probe State (see +Visualization, +SignalProbe)

    var audioSampleBuffer: [Float] = []
    var visualizationTask: Task<Void, Never>?
    @ObservationIgnored var probeOwner: UUID?

    // MARK: - Amp & Input State (see +AmpAndInput)

    /// The amp at the end of the chain. Every change is heard immediately.
    var ampSettings = AmpSettings() {
        didSet { if ampSettings != oldValue { applyAmpSettings() } }
    }
    /// Name of the loaded cabinet impulse response.
    var cabinetIRName: String?
    @ObservationIgnored var cabinetIR: [Float] = []
    /// Name of the loaded Neural Amp Modeler capture.
    var neuralModelName: String?
    /// Every capture ever loaded stays alive: the audio thread may still be using the previous one.
    @ObservationIgnored var neuralModels: [NeuralAmpModel] = []
    /// Pickup & cable, buffer, volume pedal and noise gate.
    var inputSettings = InputSettings() {
        didSet { if inputSettings != oldValue { applyInputSettings() } }
    }

    // MARK: - Latency State (see +Latency)

    /// Pick-to-ear delay: input + output hardware latency plus one buffer each way, in ms.
    var roundTripLatencyMs: Double = 0
    /// Buffer size the hardware actually granted, in ms.
    var bufferDurationMs: Double = 0
    /// Bluetooth headphones add 100–200 ms – far too much to play along to.
    var isBluetoothOutput = false
    /// Mutes the output while tuning; the tuner still hears the guitar.
    var isTunerMuted = false {
        didSet { mainMixer?.outputVolume = isTunerMuted ? 0 : 1 }
    }

    // MARK: - Initialization

    init() {
        setupDefaultEffectsChain()
        detectAudioInputDevices()
        setupConfigurationChangeObserver()
    }
    
    private func setupConfigurationChangeObserver() {
        // Listen for audio route changes (device switches)
        // Use AVAudioSession.routeChangeNotification which works on iOS/Mac Catalyst
        #if os(iOS) || targetEnvironment(macCatalyst)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioConfigurationChange()
            }
        }
        #endif
    }
    
    private func handleAudioConfigurationChange() {
        Log.audio.notice("Audio route changed - reinstalling visualization tap")

        // Refresh device detection
        detectAudioInputDevices()
        refreshLatency()
        
        // Reinstall the visualization tap if engine is running
        if isRunning {
            startRealAudioVisualization()
        }
    }

    private func setupDefaultEffectsChain() {
        // Start with a clean 6-pedal chain. The AI adds missing pedals on demand.
        effectsChain = [
            EffectNode(type: .compressor,  isEnabled: false),
            EffectNode(type: .overdrive,   isEnabled: false),
            EffectNode(type: .distortion,  isEnabled: false),
            EffectNode(type: .chorus,      isEnabled: false),
            EffectNode(type: .delay,       isEnabled: false),
            EffectNode(type: .reverb,      isEnabled: false),
        ]
    }

    func resetEffectsToDefaults() {
        stopAudition()
        isPedalboardBypassed = false
        parametricEQBands = EQBand.defaultBands
        setupDefaultEffectsChain()
        currentPreset = nil
        syncBypassStates()
        for effect in effectsChain { applyEffectParameters(effect) }
    }

    /// Ensure an effect type exists in the chain, inserting it in the correct
    /// signal-chain position if it's missing. Called by the AI before enabling.
    func ensureEffectInChain(_ type: EffectType) {
        guard !effectsChain.contains(where: { $0.type == type }) else { return }
        effectsChain.append(EffectNode(type: type, isEnabled: false))
        effectsChain.sort { $0.type.recommendedOrder < $1.type.recommendedOrder }
    }

    // MARK: - AudioEngineProtocol Implementation

    func requestMicrophonePermission() async {
        #if targetEnvironment(macCatalyst) || os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            hasPermission = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            hasPermission = false
            errorMessage = "Microphone access denied. Please enable in System Settings > Privacy > Microphone."
        @unknown default:
            hasPermission = false
        }
        #else
        // Use modern AVAudioApplication API for iOS 17+
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                hasPermission = true
            case .undetermined:
                hasPermission = await AVAudioApplication.requestRecordPermission()
            case .denied:
                hasPermission = false
                errorMessage = "Microphone access denied. Please enable in Settings > Privacy > Microphone."
            @unknown default:
                hasPermission = false
            }
        } else {
            // Fallback for older iOS versions
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted:
                hasPermission = true
            case .undetermined:
                hasPermission = await withCheckedContinuation { continuation in
                    session.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            case .denied:
                hasPermission = false
                errorMessage = "Microphone access denied. Please enable in Settings > Privacy > Microphone."
            @unknown default:
                hasPermission = false
            }
        }
        #endif
    }

    func setupEngine() async throws {
        Log.audio.debug("setupEngine: START")

        stopVisualization()
        demoRiff.stop()
        backingTrack.stopBackingTrack()
        if let previous = audioEngine {
            previous.stop()
            demoRiff.detach(from: previous)
            backingTrack.detach(from: previous)
        }
        isRunning = false
        inputNode = nil
        formatConverterMixer = nil
        connectedEffectOrder = nil
        probedNodes = []

        // Configure audio session (required for iOS/Mac Catalyst)
        #if os(iOS) || targetEnvironment(macCatalyst)
        try await Self.configureAudioSession(useLiveInput: hasPermission)
        #endif

        let engine = AVAudioEngine()
        self.audioEngine = engine
        mainMixer = engine.mainMixerNode

        // Playback is a complete graph on its own. Never open the microphone for Demo.
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate.isFinite && outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000

        // Pre-effects input mixer (guitar converter + optionally backing track feed into here)
        let fxMixer = AVAudioMixerNode()
        fxInputMixer = fxMixer
        engine.attach(fxMixer)

        // Create effect units
        effectUnits = try await EffectUnitsContainer.make()
        guard let units = effectUnits else { return }

        // Attach all effects to engine
        attachAllEffects(to: engine, units: units)
        applyParametricEQ()
        
        // Use standard processing format to avoid format mismatch issues
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!
        
        self.processingFormat = format

        Log.audio.debug("setupEngine: processing format \(format.sampleRate) Hz, \(format.channelCount) ch")

        if hasPermission {
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            if inputFormat.sampleRate > 0, inputFormat.channelCount > 0 {
                inputNode = input
                let converter = AVAudioMixerNode()
                formatConverterMixer = converter
                engine.attach(converter)
                engine.connect(input, to: converter, format: inputFormat)
                engine.connect(converter, to: fxMixer, format: format)
            }
        }
        rebuildAudioChain()
        
        // Play-along player: dry into the main mixer, or through the pedals on request
        if let mixer = mainMixer {
            backingTrack.attach(to: engine, dryOutput: mixer, effectsInput: fxMixer, format: format)
            demoRiff.attach(to: engine, output: fxMixer, format: format)
            metronome.attach(to: engine, output: mixer, format: format)
            looper.attach(to: engine, output: mixer, format: format)
            metronome.startEngineIfNeeded = { [weak self] in
                if self?.isRunning == false { try? self?.start() }
            }
            looper.startEngineIfNeeded = { [weak self] in
                if self?.isRunning == false { try? self?.start() }
            }
            looper.setRecordingTap = { [weak self] on in self?.setLooperTap(on) }
            backingTrack.startEngineIfNeeded = { [weak self] in
                if self?.isRunning == false { try? self?.start() }
            }
        }

        // Set bypass state based on effects chain
        syncBypassStates()

        // Measure what actually comes out, for the OUT meter
        mainMixer?.removeTap(onBus: 0)
        mainMixer?.installTap(onBus: 0, bufferSize: 1024, format: nil,
                              block: OutputLevelStore.tapBlock(for: outputLevelStore))

        refreshLatency()
        Log.audio.debug("setupEngine: DONE - audio chain ready")
    }

    func enableLiveInput() async throws {
        if !hasPermission { await requestMicrophonePermission() }
        guard hasPermission else { throw AudioEngineError.noPermission }
        stopDemoRiff()
        if inputNode == nil {
            try await setupEngine()
            guard inputNode != nil else { throw AudioEngineError.noInputDevice }
        }
        if !isRunning { try start() }
        formatConverterMixer?.outputVolume = 1
        startRealAudioVisualization()
    }

    func start() throws {
        guard let engine = audioEngine else {
            throw AudioEngineError.engineNotSetup
        }

        Log.audio.debug("Starting audio engine...")
        
        engine.prepare()
        
        do {
        try engine.start()
        isRunning = true
        errorMessage = nil
            Log.audio.debug("Audio engine started successfully")
            
            // Start real audio visualization with tap
            startRealAudioVisualization()
        } catch {
            Log.audio.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func stop() {
        backingTrack.stopBackingTrack()
        stopDemoRiff()
        stopVisualization()
        
        audioEngine?.stop()
        isRunning = false
        
        // Reset visualization data
        waveformSamples = Array(repeating: 0, count: 128)
        outputLevel = 0
        inputLevel = 0
    }

    // MARK: - EffectsChainManaging Implementation

    func addEffect(_ type: EffectType) {
        let newEffect = EffectNode(type: type, isEnabled: true)
        effectsChain.append(newEffect)
        rebuildAudioChain()
    }

    func removeEffect(at index: Int) {
        guard effectsChain.indices.contains(index) else { return }
        effectsChain.remove(at: index)
        rebuildAudioChain()
    }

    func moveEffect(from source: IndexSet, to destination: Int) {
        effectsChain.move(fromOffsets: source, toOffset: destination)
        rebuildAudioChain()
    }

    func toggleEffect(_ effect: EffectNode) {
        effect.isEnabled.toggle()
        
        // Use bypass instead of rebuilding entire chain (more stable)
        guard let units = effectUnits else {
        rebuildAudioChain()
            return
        }
        
        // Set bypass directly on the specific effect unit
        units.setBypass(for: effect.type, bypassed: isPedalboardBypassed || !effect.isEnabled)
        Log.audio.debug("toggleEffect: \(effect.type.rawValue, privacy: .public) \(effect.isEnabled ? "enabled" : "bypassed", privacy: .public)")
    }

    func updateEffectParameter(_ effect: EffectNode, key: String, value: Float) {
        effect.parameters[key] = value
        if effect.type == .equalizer, let index = ["bass": 0, "mid": 4, "treble": 9][key] {
            parametricEQBands[index].gain = value
        }
        applyEffectParameters(effect)
    }

    func setPedalModel(_ effect: EffectNode, modelID: String) {
        guard let model = PedalModel.model(id: modelID), model.fits(effect.type) else { return }
        effect.modelID = model.id
        applyEffectParameters(effect)
    }

    func clearEffects() {
        effectsChain.removeAll()
        rebuildAudioChain()
    }

    // MARK: - Parametric EQ Control

    /// The 10-band parametric EQ curve. Lives in the engine (not the view) so it survives
    /// tab switches, and so AI and expression changes to bass/mid/treble show on the curve.
    var parametricEQBands: [EQBand] = EQBand.defaultBands {
        didSet {
            guard parametricEQBands != oldValue else { return }
            applyParametricEQ()
            // Shaping the curve should be audible: make sure the EQ pedal is on the board
            if parametricEQBands != EQBand.defaultBands { activateEqualizerPedal() }
            if let pedal = effectsChain.first(where: { $0.type == .equalizer }) {
                pedal.parameters["bass"] = parametricEQBands[0].gain
                pedal.parameters["mid"] = parametricEQBands[4].gain
                pedal.parameters["treble"] = parametricEQBands[9].gain
            }
        }
    }

    /// Reset all EQ bands to flat (0 dB)
    func resetEQ() {
        parametricEQBands = EQBand.defaultBands
    }

    func applyParametricEQ() {
        guard let eq = effectUnits?.equalizer else { return }
        for (index, band) in parametricEQBands.enumerated() where index < eq.bands.count {
            let unitBand = eq.bands[index]
            unitBand.filterType = band.type.audioUnitFilterType
            unitBand.frequency = band.frequency
            unitBand.gain = band.gain
            unitBand.bandwidth = Self.octaves(forQ: band.q)
            unitBand.bypass = !band.isEnabled
        }
    }

    private func activateEqualizerPedal() {
        ensureEffectInChain(.equalizer)
        if let node = effectsChain.first(where: { $0.type == .equalizer }), !node.isEnabled {
            toggleEffect(node)
        }
    }

    /// AVAudioUnitEQ measures bandwidth in octaves; the UI uses Q.
    /// BW = 2/ln2 · asinh(1 / 2Q), clamped to the unit's 0.05–5 octave range.
    private static func octaves(forQ q: Float) -> Float {
        let bandwidth = 2 / log(2) * asinh(1 / (2 * max(q, 0.01)))
        return min(max(bandwidth, 0.05), 5)
    }

    /// The looper records the amp's output: your guitar through the whole board.
    private func setLooperTap(_ on: Bool) {
        guard let amp = effectUnits?.amp else { return }
        if on && !looperTapInstalled {
            amp.installTap(onBus: 0, bufferSize: 1024, format: nil, block: LoopTape.tapBlock(for: looper.tape))
            looperTapInstalled = true
        } else if !on && looperTapInstalled {
            amp.removeTap(onBus: 0)
            looperTapInstalled = false
        }
    }

    // MARK: - Tone Suggestions

    /// Applies one EQ move from the Tone balance card and switches the EQ on so it's heard.
    func applyToneSuggestion(_ suggestion: ToneSuggestion) {
        guard parametricEQBands.indices.contains(suggestion.band) else { return }
        parametricEQBands[suggestion.band].gain = suggestion.gain
    }

    // MARK: - Wah

    /// Mouth wah: nil turns it off; 0…1 is the pedal position (heel → toe).
    func setWah(_ position: Float?) {
        guard let units = effectUnits else { return }
        if let position {
            units.wahKernel.depth = position
            units.wah.auAudioUnit.shouldBypassEffect = isPedalboardBypassed
        } else {
            units.wah.auAudioUnit.shouldBypassEffect = true
        }
        isWahActive = position != nil
    }

    private(set) var isWahActive = false

    // MARK: - Expression/CV Control

    /// Set expression value for CV-controlled parameters (e.g., Wah via mouth openness)
    /// - Parameters:
    ///   - value: Expression value from 0.0 to 1.0
    ///   - effectType: The effect type to control
    func setExpressionValue(_ value: Float, for effectType: EffectType) {
        guard let effect = effectsChain.first(where: { $0.type == effectType && $0.isEnabled }) else { return }

        // Map 0-1 expression value to appropriate parameter range
        switch effectType {
        case .equalizer:
            // Wah effect = sweep mid frequency from low to high
            // Map 0-1 to -12 to +12 dB mid boost (creates wah sweep)
            let midValue = (value - 0.5) * 24  // -12 to +12
            updateEffectParameter(effect, key: "mid", value: midValue)

            // Also boost treble slightly at higher wah positions
            let trebleValue = value * 6  // 0 to +6 dB
            updateEffectParameter(effect, key: "treble", value: trebleValue)

        case .delay:
            // Expression controls delay mix (for swell effects)
            let mixValue = value * 100  // 0 to 100
            updateEffectParameter(effect, key: "mix", value: mixValue)

        case .reverb:
            // Expression controls reverb mix
            let mixValue = value * 100  // 0 to 100
            updateEffectParameter(effect, key: "wetDryMix", value: mixValue)

        case .chorus, .phaser, .flanger:
            // Expression controls modulation depth
            let depthValue = value * 100  // 0 to 100
            updateEffectParameter(effect, key: "depth", value: depthValue)

        case .tremolo:
            // Expression controls tremolo depth
            let depthValue = value * 100  // 0 to 100
            updateEffectParameter(effect, key: "depth", value: depthValue)

        case .distortion, .overdrive, .fuzz:
            // Expression controls drive level
            let driveValue = 30 + value * 70  // 30 to 100
            updateEffectParameter(effect, key: "level", value: driveValue)

        case .compressor:
            // Expression controls threshold
            let thresholdValue = -40 + value * 40  // -40 to 0 dB
            updateEffectParameter(effect, key: "threshold", value: thresholdValue)
        }
    }

    func applyPreset(_ preset: EffectPreset) {
        effectsChain = preset.effects.map { $0.toEffectNode() }
        if let eq = preset.effects.first(where: { $0.type == .equalizer && $0.isEnabled }) {
            var bands = parametricEQBands
            bands[0].gain = eq.parameters["bass"] ?? 0
            bands[4].gain = eq.parameters["mid"] ?? 0
            bands[9].gain = eq.parameters["treble"] ?? 0
            parametricEQBands = bands
        }

        // Sync bypass states
        syncBypassStates()

        // Apply all effect parameters
        for effect in effectsChain {
            applyEffectParameters(effect)
        }

        currentPreset = preset
        presetApplyCount += 1
        Log.audio.debug("applyPreset: \(preset.name, privacy: .public)")
    }

    /// Rebuild effects chain with current settings
    /// Called after batch parameter updates (e.g., from AI tone assistant)
    func rebuildEffectsChain() {
        syncBypassStates()
        for effect in effectsChain {
            applyEffectParameters(effect)
        }
        Log.audio.debug("rebuildEffectsChain: Effects chain updated")
    }

    // MARK: - Private Helpers

    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Activating the session blocks while the audio hardware spins up,
    /// so it runs off the main thread to keep the UI responsive.
    private nonisolated static func configureAudioSession(useLiveInput: Bool) async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            if useLiveInput {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            } else {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            // Live guitar needs a short buffer: ~5 ms (256 frames at 48 kHz) instead of the
            // ~20 ms default, so a note comes out of the amp right as you pick it.
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        }.value
        Log.audio.debug("setupEngine: Audio session configured")
    }
    #endif

    private func attachAllEffects(to engine: AVAudioEngine, units: EffectUnitsContainer) {
        // Dynamics
        engine.attach(units.compressor)
        
        // Filter & Pitch
        if let eq = units.equalizer {
            engine.attach(eq)
        }
        
        // Gain / Dirt
        engine.attach(units.overdrive)
        engine.attach(units.distortion)
        engine.attach(units.fuzz)
        engine.attach(units.wah)
        engine.attach(units.amp)
        engine.attach(units.input)
        
        // Modulation
        engine.attach(units.chorus)
        engine.attach(units.phaser)
        engine.attach(units.flanger)
        engine.attach(units.tremolo)
        
        // Time & Ambience
        engine.attach(units.delay)
        engine.attach(units.reverb)
        
        Log.audio.debug("attachAllEffects: All effect units attached")
    }

    /// Wires fxInputMixer through **every** pedal in `effectsChain` (enabled or not) in order.
    /// Enabling or bypassing a pedal then only flips `bypass` – no reconnection, no dropout.
    /// Rewiring happens only when the chain's composition or order actually changes.
    func rebuildAudioChain() {
        guard let engine = audioEngine,
              let mixer = mainMixer,
              let fxMixer = fxInputMixer,
              let units = effectUnits,
              let format = processingFormat else { return }

        let order = effectsChain.map(\.type)
        guard order != connectedEffectOrder else { return }

        let wasRunning = engine.isRunning
        let resumeBackingTrack = backingTrack.isBackingTrackPlaying
        if resumeBackingTrack { backingTrack.stopBackingTrack() }
        if wasRunning { engine.stop() }

        // Tear down the old pedal wiring (input -> converter -> fxInputMixer stays intact)
        engine.disconnectNodeOutput(fxMixer)
        for unit in units.allUnits where engine.attachedNodes.contains(unit) {
            engine.disconnectNodeOutput(unit)
        }

        // Guitar → pickup & cable (input stage) → wah, like the front of a real board
        engine.connect(fxMixer, to: units.input, format: format)
        engine.connect(units.input, to: units.wah, format: format)
        applyInputSettings()
        var currentNode: AVAudioNode = units.wah
        for type in order {
            guard let unit = units.audioUnit(for: type) else { continue }
            engine.connect(currentNode, to: unit, format: format)
            currentNode = unit
        }
        // The amp and cabinet sit last, like the amp a real pedalboard plugs into
        engine.connect(currentNode, to: units.amp, format: format)
        engine.connect(units.amp, to: mixer, format: format)
        applyAmpSettings()
        connectedEffectOrder = order
        installProbeTaps()

        // Newly added pedals (AI, presets, Add Pedal) start from their own settings
        for effect in effectsChain { applyEffectParameters(effect) }
        syncBypassStates()
        Log.audio.debug("rebuildAudioChain: wired \(order.map(\.abbreviation).joined(separator: " → "), privacy: .public)")

        guard wasRunning else { return }
        engine.prepare()
        do {
            try engine.start()
            // Stopping the engine halts player nodes; resume what was playing
            demoRiff.resumeAfterEngineRestart()
            metronome.resumeAfterEngineRestart()
            looper.resumeAfterEngineRestart()
            if resumeBackingTrack { backingTrack.playBackingTrack() }
        } catch {
            isRunning = false
            Log.audio.error("rebuildAudioChain: failed to restart engine: \(error.localizedDescription, privacy: .public)")
        }
    }
}
