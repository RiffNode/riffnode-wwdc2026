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

    private(set) var currentInputDeviceName: String = "No Input"
    private(set) var currentInputDeviceType: AudioInputDeviceType = .none
    private(set) var availableInputDevices: [AudioInputDevice] = []

    // MARK: - Visualization Properties (AudioVisualizationProviding)

    private(set) var waveformSamples: [Float] = Array(repeating: 0, count: 128)
    private(set) var inputLevel: Float = 0
    private(set) var outputLevel: Float = 0

    // MARK: - Audio Analysis Callbacks (for AI features)

    /// Callback for raw audio samples (used by FFT analyzer, chord detector)
    /// This callback runs on MainActor for thread safety with @Observable analyzers
    var onAudioSamplesAvailable: (@MainActor ([Float]) -> Void)?

    /// Sample rate of the audio handed to `onAudioSamplesAvailable` (mic and demo riff share it).
    var analysisSampleRate: Double {
        processingFormat?.sampleRate ?? inputNode?.outputFormat(forBus: 0).sampleRate ?? 44100
    }

    /// Latest audio samples buffer for analysis
    private(set) var latestAudioSamples: [Float] = []
    private let analysisBufferSize = 4096

    // MARK: - Effects Chain (EffectsChainManaging)

    /// Adding, removing, reordering or replacing pedals (presets, AI) rewires the audio graph.
    var effectsChain: [EffectNode] = [] {
        didSet { scheduleAudioChainRebuild() }
    }
    /// The pedal order currently wired into the audio graph (nil = not wired yet).
    @ObservationIgnored private var connectedEffectOrder: [EffectType]?
    @ObservationIgnored private var isChainRebuildScheduled = false

    /// The most recently applied preset, and a counter that bumps on every apply
    /// (so re-applying the same preset is still observable).
    private(set) var currentPreset: EffectPreset?
    private(set) var presetApplyCount = 0


    // MARK: - Play Along

    /// The groove, imported songs – everything you play along with.
    let backingTrack = BackingTrackPlayer()
    var playAlong: any BackingTrackManaging { backingTrack }

    // MARK: - Private Audio Components

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var mainMixer: AVAudioMixerNode?

    // Effect units - following composition over inheritance
    private var effectUnits: EffectUnitsContainer?
    
    // Format conversion mixer - used to resolve incompatibility between input format and effect units
    private var formatConverterMixer: AVAudioMixerNode?


    // Pre-effects mixer — both guitar and (optionally) backing track feed into this
    private var fxInputMixer: AVAudioMixerNode?


    // Audition – hear one effect on its own, A/B against the dry riff (Learn tab)
    private(set) var auditionEffect: EffectType?
    private(set) var isAuditionBypassed = false
    @ObservationIgnored private var auditionSnapshot: (chain: [EffectNode], eqBands: [EQBand], startedDemo: Bool)?

    // Demo riff – a synthesized guitar that stands in for a real one
    private let demoRiff = DemoRiffPlayer()

    // Visualization
    private var tapInstalled = false

    // Signal Lab – taps on both sides of one pedal
    @ObservationIgnored private let signalProbe = SignalProbeStore()
    @ObservationIgnored private let outputLevelStore = OutputLevelStore()
    @ObservationIgnored private var probedNodes: [AVAudioNode] = []
    /// The pedal whose input and output the Signal Lab is watching.
    private(set) var probedEffectType: EffectType?
    
    // Store processing format for rebuilding audio chain
    private var processingFormat: AVAudioFormat?
    
    // Configuration change observer
    private var configurationObserver: Any?

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
        print("🔄 Audio route changed - reinstalling visualization tap")
        
        // Refresh device detection
        detectAudioInputDevices()
        
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
            EffectNode(type: .distortion,  isEnabled: true),
            EffectNode(type: .chorus,      isEnabled: false),
            EffectNode(type: .delay,       isEnabled: false),
            EffectNode(type: .reverb,      isEnabled: true),
        ]
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
        print("setupEngine: START")

        // Configure audio session (required for iOS/Mac Catalyst)
        #if os(iOS) || targetEnvironment(macCatalyst)
        try await Self.configureAudioSession()
        #endif

        let engine = AVAudioEngine()
        self.audioEngine = engine
        mainMixer = engine.mainMixerNode

        // Setup input
        print("setupEngine: Getting input node...")
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        print("setupEngine: Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            inputNode = nil
            print("setupEngine: No valid input - demo mode")
            return
        }

        inputNode = input
        print("setupEngine: Input node ready")

        // Create format conversion mixer
        let converter = AVAudioMixerNode()
        formatConverterMixer = converter
        engine.attach(converter)

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
            standardFormatWithSampleRate: inputFormat.sampleRate,
            channels: 2
        ) ?? inputFormat
        
        self.processingFormat = format

        print("setupEngine: Processing format: \(format.sampleRate)Hz, \(format.channelCount)ch")

        // Connect signal chain
        connectSignalChain(engine: engine, input: input, converter: converter, inputFormat: inputFormat, processingFormat: format)
        
        // Play-along player: dry into the main mixer, or through the pedals on request
        if let mixer = mainMixer {
            backingTrack.attach(to: engine, dryOutput: mixer, effectsInput: fxMixer, format: format)
            demoRiff.attach(to: engine, output: fxMixer, format: format)
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

        print("setupEngine: DONE - audio chain ready")
    }

    func start() throws {
        guard let engine = audioEngine else {
            throw AudioEngineError.engineNotSetup
        }

        print("Starting audio engine...")
        
        engine.prepare()
        
        do {
        try engine.start()
        isRunning = true
        errorMessage = nil
            print("Audio engine started successfully")
        print("Audio engine running! Play your guitar!")
            
            // Start real audio visualization with tap
            startRealAudioVisualization()
        } catch {
            print("Failed to start audio engine: \(error)")
            throw error
        }
    }

    func stop() {
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
        units.setBypass(for: effect.type, bypassed: !effect.isEnabled)
        print("toggleEffect: \(effect.type.rawValue) \(effect.isEnabled ? "enabled" : "bypassed")")
    }

    func updateEffectParameter(_ effect: EffectNode, key: String, value: Float) {
        effect.parameters[key] = value
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
        }
    }

    /// Reset all EQ bands to flat (0 dB)
    func resetEQ() {
        parametricEQBands = EQBand.defaultBands
    }

    private func applyParametricEQ() {
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
            if units.wah.auAudioUnit.shouldBypassEffect { units.wah.auAudioUnit.shouldBypassEffect = false }
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

        // Sync bypass states
        syncBypassStates()

        // Apply all effect parameters
        for effect in effectsChain {
            applyEffectParameters(effect)
        }

        currentPreset = preset
        presetApplyCount += 1
        print("applyPreset: Applied preset '\(preset.name)'")
    }

    /// Rebuild effects chain with current settings
    /// Called after batch parameter updates (e.g., from AI tone assistant)
    func rebuildEffectsChain() {
        syncBypassStates()
        for effect in effectsChain {
            applyEffectParameters(effect)
        }
        print("rebuildEffectsChain: Effects chain updated")
    }

    // MARK: - Audition (Learn tab)

    /// Plays the demo riff through `type` alone, with settings exaggerated enough to hear
    /// clearly. The player's chain and EQ are saved and restored by `stopAudition()`.
    func startAudition(_ type: EffectType) {
        guard canPlayDemoRiff else { return }

        if auditionSnapshot == nil {
            let savedChain = effectsChain.map {
                EffectNode(id: $0.id, type: $0.type, isEnabled: $0.isEnabled, parameters: $0.parameters)
            }
            auditionSnapshot = (savedChain, parametricEQBands, !isDemoRiffPlaying)
        }

        var parameters = type.defaultParameters
        for (key, value) in type.auditionParameters { parameters[key] = value }
        effectsChain = [EffectNode(type: type, isEnabled: true, parameters: parameters)]
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
        for effect in effectsChain { applyEffectParameters(effect) }
        syncBypassStates()
    }

    // MARK: - Demo Riff

    var isDemoRiffPlaying: Bool { demoRiff.isPlaying }

    /// True once the effects chain exists, i.e. there is somewhere to send the riff.
    var canPlayDemoRiff: Bool { demoRiff.isReady }

    func toggleDemoRiff() {
        isDemoRiffPlaying ? stopDemoRiff() : startDemoRiff()
    }

    /// Loops the demo riff into the effects chain; the tuner, spectrum and chord detector follow it.
    func startDemoRiff() {
        guard !isDemoRiffPlaying, demoRiff.isReady else { return }
        if !isRunning { try? start() }
        guard isRunning else { return }
        inputNode?.removeTap(onBus: 0)   // the analysis tap moves from the mic to the riff
        demoRiff.play(analysisTap: audioTapCallback)
    }

    func stopDemoRiff() {
        guard isDemoRiffPlaying else { return }
        demoRiff.stop()
        // Hand the analysis tap back to the microphone
        if isRunning { startRealAudioVisualization() }
    }

    // MARK: - Private Helpers

    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Activating the session blocks while the audio hardware spins up,
    /// so it runs off the main thread to keep the UI responsive.
    private nonisolated static func configureAudioSession() async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        }.value
        print("setupEngine: Audio session configured")
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
        
        // Modulation
        engine.attach(units.chorus)
        engine.attach(units.phaser)
        engine.attach(units.flanger)
        engine.attach(units.tremolo)
        
        // Time & Ambience
        engine.attach(units.delay)
        engine.attach(units.reverb)
        
        print("attachAllEffects: All effect units attached")
    }

    private func connectSignalChain(engine: AVAudioEngine, input: AVAudioInputNode, converter: AVAudioMixerNode, inputFormat: AVAudioFormat, processingFormat: AVAudioFormat) {
        guard let fxMixer = fxInputMixer else { return }

        // Input -> Converter -> fxInputMixer. The backing track and demo riff also
        // feed fxInputMixer, so everything entering it passes through the pedals.
        engine.connect(input, to: converter, format: inputFormat)
        engine.connect(converter, to: fxMixer, format: processingFormat)

        // fxInputMixer -> every pedal in effectsChain order -> mainMixer
        connectedEffectOrder = nil
        rebuildAudioChain()
    }

    /// Wires fxInputMixer through **every** pedal in `effectsChain` (enabled or not) in order.
    /// Enabling or bypassing a pedal then only flips `bypass` – no reconnection, no dropout.
    /// Rewiring happens only when the chain's composition or order actually changes.
    private func rebuildAudioChain() {
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

        // The mouth-controlled wah sits first, like a wah pedal at the front of a real board
        engine.connect(fxMixer, to: units.wah, format: format)
        var currentNode: AVAudioNode = units.wah
        for type in order {
            guard let unit = units.audioUnit(for: type) else { continue }
            engine.connect(currentNode, to: unit, format: format)
            currentNode = unit
        }
        engine.connect(currentNode, to: mixer, format: format)
        connectedEffectOrder = order
        installProbeTaps()

        // Newly added pedals (AI, presets, Add Pedal) start from their own settings
        for effect in effectsChain { applyEffectParameters(effect) }
        syncBypassStates()
        print("rebuildAudioChain: Wired \(order.count) pedals: \(order.map(\.abbreviation).joined(separator: " → "))")

        guard wasRunning else { return }
        engine.prepare()
        do {
            try engine.start()
            // Stopping the engine halts player nodes; resume what was playing
            demoRiff.resumeAfterEngineRestart()
            if resumeBackingTrack { backingTrack.playBackingTrack() }
        } catch {
            isRunning = false
            print("rebuildAudioChain: Failed to restart engine: \(error)")
        }
    }

    // MARK: - Signal Probe

    /// Starts watching the signal just before and just after one pedal.
    /// `owner` identifies the view asking: views are rebuilt when you switch pedals or a preset
    /// replaces the chain, and the old view's "stop" can arrive after the new view's "start".
    func probe(_ type: EffectType, owner: UUID) {
        probeOwner = owner
        guard type != probedEffectType else { return }
        probedEffectType = type
        installProbeTaps()
    }

    func probeSnapshot() -> (before: SignalCapture, after: SignalCapture) {
        signalProbe.snapshot()
    }

    /// Stops the probe – only if `owner` is still the view that started it.
    func stopProbe(owner: UUID) {
        guard probeOwner == owner else { return }
        probeOwner = nil
        probedEffectType = nil
        installProbeTaps()
    }

    @ObservationIgnored private var probeOwner: UUID?

    /// Taps the node that feeds the probed pedal ("before") and the pedal itself ("after").
    /// Re-run after every rewire, since the node in front of a pedal can change.
    private func installProbeTaps() {
        for node in probedNodes { node.removeTap(onBus: 0) }
        probedNodes = []
        signalProbe.reset()

        guard let type = probedEffectType,
              let units = effectUnits,
              let fxMixer = fxInputMixer,
              let order = connectedEffectOrder,
              let index = order.firstIndex(of: type),
              let after = units.audioUnit(for: type) else { return }
        let before: AVAudioNode = index == 0
            ? units.wah
            : units.audioUnit(for: order[index - 1]) ?? fxMixer

        before.installTap(onBus: 0, bufferSize: 1024, format: nil,
                          block: SignalProbeStore.tapBlock(for: signalProbe, side: .before))
        after.installTap(onBus: 0, bufferSize: 1024, format: nil,
                         block: SignalProbeStore.tapBlock(for: signalProbe, side: .after))
        probedNodes = [before, after]
    }

    /// Coalesces several edits in one turn of the run loop (e.g. append + sort) into one rewire.
    private func scheduleAudioChainRebuild() {
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

    private func applyEffectParameters(_ effect: EffectNode) {
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
            // The EQ pedal's bass / mid / treble knobs (used by the AI and the
            // mouth-wah) drive bands 0, 4 and 9 of the shared parametric curve,
            // so the change is both audible and visible on the EQ tab.
            guard effect.isEnabled else { break }
            var bands = parametricEQBands
            bands[0].gain = effect.parameters["bass"] ?? 0
            bands[4].gain = effect.parameters["mid"] ?? 0
            bands[9].gain = effect.parameters["treble"] ?? 0
            parametricEQBands = bands

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
            units.delay.delayTime = TimeInterval(effect.parameters["time"] ?? 0.3)
            units.delay.feedback = effect.parameters["feedback"] ?? 40
            units.delay.wetDryMix = effect.parameters["mix"] ?? 30

        case .reverb:
            units.reverb.wetDryMix = effect.parameters["wetDryMix"] ?? 40
            if let decay = effect.parameters["decay"] {
                selectReverbPreset(decaySeconds: decay)
            }
        }
    }

    // MARK: - Reverb Preset Selection

    /// Select an appropriate AVAudioUnitReverb preset based on decay time
    private func selectReverbPreset(decaySeconds: Float) {
        guard let units = effectUnits else { return }
        let preset: AVAudioUnitReverbPreset
        if decaySeconds < 0.8 {
            preset = .smallRoom
        } else if decaySeconds < 1.5 {
            preset = .mediumRoom
        } else if decaySeconds < 2.5 {
            preset = .mediumHall
        } else if decaySeconds < 4.0 {
            preset = .largeHall
        } else {
            preset = .cathedral
        }
        units.reverb.loadFactoryPreset(preset)
    }

    /// Sync bypass state for all effects
    private func syncBypassStates() {
        guard let units = effectUnits else { return }
        
        // Create a set of enabled effect types
        var enabledTypes = Set<EffectType>()
        for effect in effectsChain where effect.isEnabled {
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
        units.delay.bypass = !enabledTypes.contains(.delay)
        units.reverb.bypass = !enabledTypes.contains(.reverb)
        units.equalizer?.bypass = !enabledTypes.contains(.equalizer)
        
        print("syncBypassStates: Bypass states synchronized")
    }

    // MARK: - Audio Visualization

    private var visualizationPhase: Float = 0
    private var audioSampleBuffer: [Float] = []
    private var analysisFrameCounter = 0
    private let analysisFrameSkip = 3 // Only analyze every Nth frame for performance

    private func startRealAudioVisualization() {
        stopVisualization()

        // Refresh device detection
        detectAudioInputDevices()

        guard let input = inputNode else {
            print("⚠️ No input node available - visualization disabled")
            return
        }

        // Get and validate input format
        let inputFormat = input.outputFormat(forBus: 0)

        // Validate format to prevent crashes
        guard inputFormat.sampleRate > 0,
              inputFormat.sampleRate.isFinite,
              inputFormat.sampleRate <= 192000,
              inputFormat.channelCount > 0,
              inputFormat.channelCount <= 8 else {
            print("⚠️ Invalid input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")
            return
        }

        print("📊 Installing audio tap: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        input.removeTap(onBus: 0)

        // CRITICAL FIX for Swift 6 Strict Concurrency:
        // Use a nonisolated function reference to completely break MainActor inheritance.
        // The closure passed to installTap would inherit @MainActor isolation from this class,
        // causing a crash when the closure executes on the audio thread.
        // By using a global function reference, we ensure no actor isolation is inherited.
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: audioTapCallback)

        tapInstalled = true

        // Start polling using MainActor-safe async loop
        startVisualizationPolling()

        print("✅ Audio visualization started successfully")
    }

    private func startVisualizationPolling() {
        // Use a simple async loop that's fully MainActor-isolated
        visualizationTask = Task {
            await runVisualizationLoop()
        }
    }

    private func runVisualizationLoop() async {
        var frameCounter = 0
        while !Task.isCancelled && isRunning {
            let data = AudioSampleBuffer.shared.read()

            inputLevel = min(1.0, data.rms * 5)
            outputLevel = min(1.0, outputLevelStore.rms * 5)
            waveformSamples = data.waveform

            // Feed audio samples to FFT/chord every 3rd frame (~10 Hz at 30fps base rate)
            // 10fps is more than enough for educational spectrum + pitch display
            frameCounter += 1
            if frameCounter >= 3 && !data.samples.isEmpty && data.samples.count >= 2048 {
                frameCounter = 0
                latestAudioSamples = data.samples

                if let callback = onAudioSamplesAvailable {
                    callback(data.samples)
                }
            }

            // 33ms = ~30fps — half the @Observable update rate vs 60fps, no perceptible difference
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private var visualizationTask: Task<Void, Never>?


    private func stopVisualization() {
        visualizationTask?.cancel()
        visualizationTask = nil
        if tapInstalled {
            inputNode?.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioSampleBuffer.removeAll()
    }
}

// MARK: - Audio Input Device Detection Extension

extension AudioEngineManager {

    /// Detect and update available audio input devices
    /// This method is safe to call from MainActor - updates properties directly
    func detectAudioInputDevices() {
        #if os(macOS)
        let result = AudioEngineManager.collectMacOSInputDevices()
        #else
        let result = AudioEngineManager.collectIOSInputDevices()
        #endif

        // Update properties directly (we're on MainActor)
        self.availableInputDevices = result.devices
        self.currentInputDeviceName = result.currentName
        self.currentInputDeviceType = result.currentType

        print("detectAudioInputDevices: Found \(result.devices.count) devices, current: \(result.currentName)")
    }

    // MARK: - Static Device Collection (Thread-Safe, No Self Capture)

    /// Result type for device detection - avoids any self capture
    private struct DeviceDetectionResult {
        let devices: [AudioInputDevice]
        let currentName: String
        let currentType: AudioInputDeviceType
    }

    #if os(macOS)
    /// Static function to collect macOS input devices - no MainActor dependency
    private static func collectMacOSInputDevices() -> DeviceDetectionResult {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        var devices: [AudioInputDevice] = []

        for device in discoverySession.devices {
            let deviceType = classifyInputDeviceStatic(name: device.localizedName)
            devices.append(AudioInputDevice(
                id: device.uniqueID,
                name: device.localizedName,
                type: deviceType
            ))
        }

        let currentName: String
        let currentType: AudioInputDeviceType

        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            currentName = defaultDevice.localizedName
            currentType = classifyInputDeviceStatic(name: defaultDevice.localizedName)
        } else if let firstDevice = devices.first {
            currentName = firstDevice.name
            currentType = firstDevice.type
        } else {
            currentName = "No Input"
            currentType = .none
        }

        return DeviceDetectionResult(devices: devices, currentName: currentName, currentType: currentType)
    }
    #endif

    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Static function to collect iOS input devices - no MainActor dependency
    private static func collectIOSInputDevices() -> DeviceDetectionResult {
        let session = AVAudioSession.sharedInstance()
        var devices: [AudioInputDevice] = []

        if let availableInputs = session.availableInputs {
            for input in availableInputs {
                let deviceType = classifyIOSPortStatic(portType: input.portType)
                devices.append(AudioInputDevice(
                    id: input.uid,
                    name: input.portName,
                    type: deviceType
                ))
            }
        }

        let currentName: String
        let currentType: AudioInputDeviceType

        if let currentInput = session.currentRoute.inputs.first {
            currentName = currentInput.portName
            currentType = classifyIOSPortStatic(portType: currentInput.portType)
        } else if let firstDevice = devices.first {
            currentName = firstDevice.name
            currentType = firstDevice.type
        } else {
            currentName = "No Input"
            currentType = .none
        }

        return DeviceDetectionResult(devices: devices, currentName: currentName, currentType: currentType)
    }

    /// Static port classification - no self dependency
    private static func classifyIOSPortStatic(portType: AVAudioSession.Port) -> AudioInputDeviceType {
        switch portType {
        case .builtInMic:
            return .builtInMicrophone
        case .headsetMic:
            return .headset
        case .usbAudio:
            return .usbAudioInterface
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            return .bluetooth
        default:
            return .external
        }
    }
    #endif

    /// Static device classification - no self dependency
    private static func classifyInputDeviceStatic(name: String) -> AudioInputDeviceType {
        let lowercaseName = name.lowercased()

        // USB Audio Interfaces
        if lowercaseName.contains("scarlett") ||
           lowercaseName.contains("focusrite") ||
           lowercaseName.contains("steinberg") ||
           lowercaseName.contains("presonus") ||
           lowercaseName.contains("behringer") ||
           lowercaseName.contains("motu") ||
           lowercaseName.contains("apogee") ||
           lowercaseName.contains("universal audio") ||
           lowercaseName.contains("usb audio") ||
           lowercaseName.contains("audio interface") {
            return .usbAudioInterface
        }

        // Built-in microphone
        if lowercaseName.contains("built-in") ||
           lowercaseName.contains("internal") ||
           lowercaseName.contains("macbook") ||
           lowercaseName.contains("imac") {
            return .builtInMicrophone
        }

        // Headsets
        if lowercaseName.contains("headset") ||
           lowercaseName.contains("airpods") ||
           lowercaseName.contains("earbuds") {
            return .headset
        }

        // Bluetooth
        if lowercaseName.contains("bluetooth") {
            return .bluetooth
        }

        return .external
    }

    /// Refresh input device list
    func refreshInputDevices() {
        detectAudioInputDevices()
    }
}
