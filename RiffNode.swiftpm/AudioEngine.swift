import AVFoundation
import Observation
import os
import SwiftUI

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

    /// Latest audio samples buffer for analysis
    private(set) var latestAudioSamples: [Float] = []
    private let analysisBufferSize = 4096

    // MARK: - Effects Chain (EffectsChainManaging)

    var effectsChain: [EffectNode] = []

    // MARK: - Backing Track (BackingTrackManaging)

    private(set) var isBackingTrackPlaying = false
    var backingTrackVolume: Float = 0.5
    private(set) var backingTrackDuration: TimeInterval = 0
    private(set) var backingTrackCurrentTime: TimeInterval = 0
    private var backingTrackStartTime: Date?
    private var backingTrackStartPosition: TimeInterval = 0
    private var playbackUpdateTimer: Timer?

    // MARK: - Private Audio Components

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var mainMixer: AVAudioMixerNode?

    // Effect units - following composition over inheritance
    private var effectUnits: EffectUnitsContainer?
    
    // Format conversion mixer - used to resolve incompatibility between input format and effect units
    private var formatConverterMixer: AVAudioMixerNode?

    // Backing track
    private var backingTrackPlayer: AVAudioPlayerNode?
    private var backingTrackBuffer: AVAudioPCMBuffer?

    // Pre-effects mixer — both guitar and (optionally) backing track feed into this
    private var fxInputMixer: AVAudioMixerNode?

    /// When true the backing track is routed through the full effects chain
    private(set) var backingTrackThroughEffects: Bool = false

    // Visualization
    private var tapInstalled = false
    
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
        // Default chain following recommended signal chain order
        effectsChain = [
            EffectNode(type: .compressor, isEnabled: false),
            EffectNode(type: .overdrive, isEnabled: false),
            EffectNode(type: .distortion, isEnabled: true),
            EffectNode(type: .chorus, isEnabled: false),
            EffectNode(type: .delay, isEnabled: false),
            EffectNode(type: .reverb, isEnabled: true)
        ]
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
        try configureAudioSession()
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
        effectUnits = EffectUnitsContainer()
        guard let units = effectUnits else { return }

        // Attach all effects to engine
        attachAllEffects(to: engine, units: units)
        
        // Create and attach backing track player
        let player = AVAudioPlayerNode()
        backingTrackPlayer = player
        engine.attach(player)

        // Use standard processing format to avoid format mismatch issues
        let format = AVAudioFormat(
            standardFormatWithSampleRate: inputFormat.sampleRate,
            channels: 2
        ) ?? inputFormat
        
        self.processingFormat = format

        print("setupEngine: Processing format: \(format.sampleRate)Hz, \(format.channelCount)ch")

        // Connect signal chain
        connectSignalChain(engine: engine, input: input, converter: converter, inputFormat: inputFormat, processingFormat: format)
        
        // Connect backing track player to mixer
        if let mixer = mainMixer {
            engine.connect(player, to: mixer, format: format)
            print("setupEngine: Backing track player connected")
        }

        // Set bypass state based on effects chain
        syncBypassStates()

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

    /// Update a specific EQ band's parameters
    /// - Parameters:
    ///   - bandIndex: Index of the band (0-9 for 10-band EQ)
    ///   - frequency: Center frequency in Hz
    ///   - gain: Gain in dB (-24 to +24)
    ///   - q: Q factor (bandwidth)
    func updateEQBand(index bandIndex: Int, frequency: Float, gain: Float, q: Float) {
        guard let eq = effectUnits?.equalizer,
              bandIndex >= 0 && bandIndex < eq.bands.count else {
            return
        }

        let band = eq.bands[bandIndex]
        band.frequency = frequency
        band.gain = gain
        band.bandwidth = q
        band.bypass = false

        print("updateEQBand: Band \(bandIndex) - freq: \(frequency)Hz, gain: \(gain)dB, Q: \(q)")
    }

    /// Update all EQ bands at once from an array of band configurations
    /// - Parameter bands: Array of tuples containing (frequency, gain, q, isEnabled)
    func updateAllEQBands(_ bands: [(frequency: Float, gain: Float, q: Float, isEnabled: Bool)]) {
        guard let eq = effectUnits?.equalizer else { return }

        for (index, config) in bands.enumerated() where index < eq.bands.count {
            eq.bands[index].frequency = config.frequency
            eq.bands[index].gain = config.gain
            eq.bands[index].bandwidth = config.q
            eq.bands[index].bypass = !config.isEnabled
        }

        print("updateAllEQBands: Updated \(bands.count) bands")
    }

    /// Reset all EQ bands to flat (0 dB)
    func resetEQ() {
        guard let eq = effectUnits?.equalizer else { return }

        let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        for (index, freq) in frequencies.enumerated() where index < eq.bands.count {
            eq.bands[index].frequency = freq
            eq.bands[index].gain = 0
            eq.bands[index].bandwidth = 1.0
            eq.bands[index].bypass = false
        }

        print("resetEQ: All bands reset to flat")
    }

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

    // MARK: - BackingTrackManaging Implementation

    func loadBackingTrack(url: URL) async throws {
        print("loadBackingTrack: Loading \(url.lastPathComponent)")

        let file = try AVAudioFile(forReading: url)
        let fileFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        print("loadBackingTrack: File format: \(fileFormat.sampleRate)Hz, \(fileFormat.channelCount)ch")

        guard let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: frameCount) else {
            throw AudioEngineError.bufferCreationFailed
        }

        try file.read(into: buffer)
        backingTrackBuffer = buffer

        // Calculate duration
        backingTrackDuration = Double(frameCount) / fileFormat.sampleRate
        backingTrackCurrentTime = 0

        print("loadBackingTrack: Loaded \(frameCount) frames, duration: \(backingTrackDuration)s")
    }

    func playBackingTrack() {
        guard let player = backingTrackPlayer,
              let buffer = backingTrackBuffer else {
            print("playBackingTrack: Player or buffer not available")
            return
        }

        player.stop()

        // Schedule from current position
        let framePosition = AVAudioFramePosition(backingTrackCurrentTime * buffer.format.sampleRate)
        let frameCount = AVAudioFrameCount(buffer.frameLength)

        if framePosition < Int64(frameCount) {
            // Create a segment buffer from current position
            let remainingFrames = AVAudioFrameCount(Int64(frameCount) - framePosition)
            if let segmentBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: remainingFrames) {
                segmentBuffer.frameLength = remainingFrames

                // Copy from offset position
                if let srcData = buffer.floatChannelData, let dstData = segmentBuffer.floatChannelData {
                    for channel in 0..<Int(buffer.format.channelCount) {
                        memcpy(dstData[channel], srcData[channel].advanced(by: Int(framePosition)), Int(remainingFrames) * MemoryLayout<Float>.size)
                    }
                }

                player.scheduleBuffer(segmentBuffer, at: nil, options: [])
            }
        }

        player.volume = backingTrackVolume
        player.play()
        isBackingTrackPlaying = true
        backingTrackStartTime = Date()
        backingTrackStartPosition = backingTrackCurrentTime

        // Start playback position update timer
        startPlaybackTimer()

        print("playBackingTrack: Started playing from \(backingTrackCurrentTime)s")
    }

    func stopBackingTrack() {
        backingTrackPlayer?.stop()
        isBackingTrackPlaying = false
        stopPlaybackTimer()

        // Update current time based on how long we played
        if let startTime = backingTrackStartTime {
            backingTrackCurrentTime = backingTrackStartPosition + Date().timeIntervalSince(startTime)
            if backingTrackCurrentTime >= backingTrackDuration {
                backingTrackCurrentTime = 0
            }
        }
        backingTrackStartTime = nil
    }

    func setBackingTrackVolume(_ volume: Float) {
        backingTrackVolume = volume
        backingTrackPlayer?.volume = volume
    }

    /// Toggle whether the backing track is routed through the full effects chain.
    /// When enabled, users hear exactly how their pedals/EQ affect real music.
    func toggleBackingTrackThroughEffects() {
        guard let engine = audioEngine,
              let player = backingTrackPlayer,
              let fxMixer = fxInputMixer,
              let mainMix = mainMixer,
              let format = processingFormat else { return }

        let wasPlaying = isBackingTrackPlaying
        let savedPosition = backingTrackCurrentTime

        if wasPlaying {
            player.stop()
            stopPlaybackTimer()
        }

        // Rewire player output
        if engine.attachedNodes.contains(player) {
            engine.disconnectNodeOutput(player)
        }

        backingTrackThroughEffects.toggle()

        if backingTrackThroughEffects {
            engine.connect(player, to: fxMixer, format: format)
            print("backingTrack: routed THROUGH effects chain")
        } else {
            engine.connect(player, to: mainMix, format: format)
            print("backingTrack: routed DRY (bypass effects)")
        }

        backingTrackCurrentTime = savedPosition

        if wasPlaying {
            playBackingTrack()
        }
    }

    func seekBackingTrack(to time: TimeInterval) {
        let wasPlaying = isBackingTrackPlaying

        // Stop current playback
        if wasPlaying {
            backingTrackPlayer?.stop()
            stopPlaybackTimer()
        }

        // Update position
        backingTrackCurrentTime = max(0, min(time, backingTrackDuration))

        // Resume if was playing
        if wasPlaying {
            playBackingTrack()
        }
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePlaybackPosition()
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackUpdateTimer?.invalidate()
        playbackUpdateTimer = nil
    }

    private func updatePlaybackPosition() {
        guard isBackingTrackPlaying, let startTime = backingTrackStartTime else { return }

        backingTrackCurrentTime = backingTrackStartPosition + Date().timeIntervalSince(startTime)

        // Check if playback completed
        if backingTrackCurrentTime >= backingTrackDuration {
            backingTrackCurrentTime = 0
            backingTrackStartPosition = 0
            backingTrackStartTime = Date()
        }
    }

    // MARK: - Private Helpers

    #if os(iOS) || targetEnvironment(macCatalyst)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)
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
        guard let units = effectUnits, let mixer = mainMixer, let fxMixer = fxInputMixer else { return }

        // Input -> Converter -> fxInputMixer -> effects chain -> mainMixer
        engine.connect(input, to: converter, format: inputFormat)
        engine.connect(converter, to: fxMixer, format: processingFormat)

        // fxInputMixer -> Compressor -> Distortion -> Chorus -> Delay -> Reverb -> Mixer
        engine.connect(fxMixer, to: units.compressor, format: processingFormat)
        engine.connect(units.compressor, to: units.distortion, format: processingFormat)
        engine.connect(units.distortion, to: units.chorus, format: processingFormat)
        engine.connect(units.chorus, to: units.delay, format: processingFormat)
        engine.connect(units.delay, to: units.reverb, format: processingFormat)
        engine.connect(units.reverb, to: mixer, format: processingFormat)

        print("connectSignalChain: Signal chain connected via fxInputMixer")
    }

    private func rebuildAudioChain() {
        guard let engine = audioEngine,
              let mixer = mainMixer,
              let input = inputNode,
              let converter = formatConverterMixer,
              let units = effectUnits else {
            print("rebuildAudioChain: Missing required components, skipping")
            return
        }

        let wasRunning = engine.isRunning
        print("rebuildAudioChain: Starting rebuild, wasRunning=\(wasRunning)")

        if wasRunning {
            engine.stop()
        }

        // Remove visualization tap if installed
        if tapInstalled {
            mixer.removeTap(onBus: 0)
            tapInstalled = false
        }

        // Safely disconnect nodes
        disconnectAllEffects(engine: engine, converter: converter, units: units)

        // Get formats
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("rebuildAudioChain: Invalid input format, skipping")
            return
        }
        
        let format = processingFormat ?? AVAudioFormat(
            standardFormatWithSampleRate: inputFormat.sampleRate,
            channels: 2
        ) ?? inputFormat

        // Reconnect: Input -> Converter
        engine.connect(input, to: converter, format: inputFormat)

        // Build chain based on enabled effects
        var currentNode: AVAudioNode = converter
        var enabledEffectCount = 0

        for effectNode in effectsChain where effectNode.isEnabled {
            guard let unit = units.audioUnit(for: effectNode.type) else { continue }
            engine.connect(currentNode, to: unit, format: format)
            currentNode = unit
            enabledEffectCount += 1
            applyEffectParameters(effectNode)
        }

        // Connect final node to mixer
        engine.connect(currentNode, to: mixer, format: format)

        print("rebuildAudioChain: Rebuilt with \(enabledEffectCount) enabled effects")

        if wasRunning {
            engine.prepare()
            do {
                try engine.start()
                print("rebuildAudioChain: Engine restarted successfully")
            } catch {
                print("rebuildAudioChain: Failed to restart engine: \(error)")
            }
        }
    }
    
    private func disconnectAllEffects(engine: AVAudioEngine, converter: AVAudioMixerNode, units: EffectUnitsContainer) {
        // Disconnect format converter
        if engine.attachedNodes.contains(converter) {
            engine.disconnectNodeOutput(converter)
        }
        engine.disconnectNodeInput(converter)
        
        // Disconnect all effect units
        let allUnits: [AVAudioUnit] = [
            units.compressor,
            units.overdrive,
            units.distortion,
            units.fuzz,
            units.chorus,
            units.phaser,
            units.flanger,
            units.tremolo,
            units.delay,
            units.reverb
        ]
        
        for unit in allUnits {
            if engine.attachedNodes.contains(unit) {
                engine.disconnectNodeOutput(unit)
            }
        }
        
        if let eq = units.equalizer, engine.attachedNodes.contains(eq) {
            engine.disconnectNodeOutput(eq)
        }
    }

    private func applyEffectParameters(_ effect: EffectNode) {
        guard let units = effectUnits else { return }

        switch effect.type {
        case .compressor:
            // AVAudioUnitDistortion used as compressor simulation
            // (AVFoundation doesn't have a native compressor, using distortion with low settings)
            break
            
        case .equalizer:
            if let eq = units.equalizer {
                eq.bands[0].gain = effect.parameters["bass"] ?? 0
                eq.bands[1].gain = effect.parameters["mid"] ?? 0
                eq.bands[2].gain = effect.parameters["treble"] ?? 0
            }
            
        case .overdrive:
            units.overdrive.wetDryMix = effect.parameters["level"] ?? 50
            
        case .distortion:
            units.distortion.wetDryMix = effect.parameters["level"] ?? 50
            
        case .fuzz:
            units.fuzz.wetDryMix = effect.parameters["level"] ?? 50
            
        case .chorus:
            // Using delay with short time to simulate chorus
            break
            
        case .phaser:
            // Simulated through distortion preset
            break
            
        case .flanger:
            // Simulated through delay with feedback
            break
            
        case .tremolo:
            // Simulated through volume modulation
            break

        case .delay:
            units.delay.delayTime = TimeInterval(effect.parameters["time"] ?? 0.3)
            units.delay.feedback = effect.parameters["feedback"] ?? 40
            units.delay.wetDryMix = effect.parameters["mix"] ?? 30

        case .reverb:
            units.reverb.wetDryMix = effect.parameters["wetDryMix"] ?? 40
        }
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
        units.overdrive.bypass = !enabledTypes.contains(.overdrive)
        units.distortion.bypass = !enabledTypes.contains(.distortion)
        units.fuzz.bypass = !enabledTypes.contains(.fuzz)
        units.chorus.bypass = !enabledTypes.contains(.chorus)
        units.phaser.bypass = !enabledTypes.contains(.phaser)
        units.flanger.bypass = !enabledTypes.contains(.flanger)
        units.tremolo.bypass = !enabledTypes.contains(.tremolo)
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
            outputLevel = inputLevel * 0.9
            waveformSamples = data.waveform

            // Feed audio samples to analyzers every 3rd frame (~10 Hz for FFT)
            // This reduces CPU load while still providing responsive analysis
            frameCounter += 1
            if frameCounter >= 3 && !data.samples.isEmpty && data.samples.count >= 2048 {
                frameCounter = 0
                latestAudioSamples = data.samples

                if let callback = onAudioSamplesAvailable {
                    callback(data.samples)
                }
            }

            // 16ms = ~60fps for smooth waveform visualization
            try? await Task.sleep(for: .milliseconds(16))
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

// MARK: - Effect Units Container
// Following Clean Architecture: Infrastructure Layer
// Following Single Responsibility: Only manages audio unit instances

private final class EffectUnitsContainer {
    // Dynamics
    let compressor: AVAudioUnitDistortion
    
    // Filter & Pitch
    let equalizer: AVAudioUnitEQ?
    
    // Gain / Dirt (using different distortion presets)
    let overdrive: AVAudioUnitDistortion
    let distortion: AVAudioUnitDistortion
    let fuzz: AVAudioUnitDistortion
    
    // Modulation (simulated using available units)
    let chorus: AVAudioUnitDelay
    let phaser: AVAudioUnitDistortion
    let flanger: AVAudioUnitDelay
    let tremolo: AVAudioUnitDistortion
    
    // Time & Ambience
    let delay: AVAudioUnitDelay
    let reverb: AVAudioUnitReverb

    init() {
        // Dynamics - Compressor (simulated with low distortion)
        compressor = AVAudioUnitDistortion()
        compressor.loadFactoryPreset(.speechWaves)
        compressor.wetDryMix = 30
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
        
        // Overdrive - soft clipping
        overdrive = AVAudioUnitDistortion()
        overdrive.loadFactoryPreset(.drumsLoFi)
        overdrive.wetDryMix = 30
        overdrive.bypass = true
        
        // Distortion - hard clipping
        distortion = AVAudioUnitDistortion()
        distortion.loadFactoryPreset(.drumsBitBrush)
        distortion.wetDryMix = 50
        distortion.bypass = true
        
        // Fuzz - heavy saturation
        fuzz = AVAudioUnitDistortion()
        fuzz.loadFactoryPreset(.multiDistortedFunk)
        fuzz.wetDryMix = 70
        fuzz.bypass = true
        
        // Chorus (simulated with short delay)
        chorus = AVAudioUnitDelay()
        chorus.delayTime = 0.02  // 20ms for chorus effect
        chorus.feedback = 20
        chorus.wetDryMix = 40
        chorus.bypass = true
        
        // Phaser (simulated)
        phaser = AVAudioUnitDistortion()
        phaser.loadFactoryPreset(.speechCosmicInterference)
        phaser.wetDryMix = 50
        phaser.bypass = true
        
        // Flanger (simulated with very short delay and high feedback)
        flanger = AVAudioUnitDelay()
        flanger.delayTime = 0.005  // 5ms for flanger
        flanger.feedback = 60
        flanger.wetDryMix = 50
        flanger.bypass = true
        
        // Tremolo (simulated)
        tremolo = AVAudioUnitDistortion()
        tremolo.loadFactoryPreset(.speechGoldenPi)
        tremolo.wetDryMix = 50
        tremolo.bypass = true

        // Delay
        delay = AVAudioUnitDelay()
        delay.delayTime = 0.3
        delay.feedback = 40
        delay.wetDryMix = 30
        delay.bypass = true

        // Reverb
        reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 40
        reverb.bypass = true
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
    
    /// Set bypass state for a specific effect type
    /// AVAudioUnit base class doesn't have bypass, so we access concrete types directly
    func setBypass(for type: EffectType, bypassed: Bool) {
        switch type {
        case .compressor:
            compressor.bypass = bypassed
        case .equalizer:
            equalizer?.bypass = bypassed
        case .overdrive:
            overdrive.bypass = bypassed
        case .distortion:
            distortion.bypass = bypassed
        case .fuzz:
            fuzz.bypass = bypassed
        case .chorus:
            chorus.bypass = bypassed
        case .phaser:
            phaser.bypass = bypassed
        case .flanger:
            flanger.bypass = bypassed
        case .tremolo:
            tremolo.bypass = bypassed
        case .delay:
            delay.bypass = bypassed
        case .reverb:
            reverb.bypass = bypassed
        }
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

// MARK: - Audio Input Device Model

struct AudioInputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let type: AudioInputDeviceType
}

// MARK: - Audio Input Device Type

enum AudioInputDeviceType: String {
    case none = "No Input"
    case builtInMicrophone = "Built-in Mic"
    case usbAudioInterface = "USB Interface"
    case headset = "Headset"
    case bluetooth = "Bluetooth"
    case external = "External"

    var icon: String {
        switch self {
        case .none: return "mic.slash"
        case .builtInMicrophone: return "laptopcomputer"
        case .usbAudioInterface: return "cable.connector"
        case .headset: return "headphones"
        case .bluetooth: return "wave.3.right"
        case .external: return "mic"
        }
    }

    var color: SwiftUI.Color {
        switch self {
        case .none: return .gray
        case .builtInMicrophone: return .blue
        case .usbAudioInterface: return .green
        case .headset: return .orange
        case .bluetooth: return .purple
        case .external: return .cyan
        }
    }
}

// MARK: - Audio Tap Callback (Nonisolated - Critical for Swift 6 Concurrency)
// This function MUST be a global/free function, NOT a method or closure.
// When passed to installTap, it has NO actor isolation, preventing MainActor crashes.

private func audioTapCallback(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
    // ✅ SAFE: This is a nonisolated global function.
    // It runs on the audio thread with no MainActor association.

    guard let channelData = buffer.floatChannelData else { return }
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return }

    let channelCount = Int(buffer.format.channelCount)

    // Get FULL samples for FFT analysis (no downsampling)
    var fullSamples = [Float](repeating: 0, count: frameLength)

    for i in 0..<frameLength {
        var maxSample: Float = 0
        // Check all channels and take the maximum (handles mono/stereo and different input configs)
        for ch in 0..<channelCount {
            let sample = channelData[ch][i]
            if abs(sample) > abs(maxSample) {
                maxSample = sample
            }
        }
        fullSamples[i] = maxSample
    }

    // Use free functions to avoid any MainActor association
    let rms = audioCalculateRMS(fullSamples)
    let waveform = audioDownsampleForDisplay(fullSamples, targetCount: 128)

    // DEBUG: Print RMS every ~1 second (every ~43 callbacks at 44100Hz/1024 buffer)
    audioTapDebugCounter += 1
    if audioTapDebugCounter % 43 == 0 {
        print("🎸 Audio tap: channels=\(channelCount), frames=\(frameLength), rms=\(rms), maxSample=\(fullSamples.max() ?? 0)")
    }

    // Write to thread-safe buffer (no MainActor dependency)
    // Full samples will be accumulated in the buffer for FFT analysis
    AudioSampleBuffer.shared.write(samples: fullSamples, waveform: waveform, rms: rms)
}

// Debug counter for tap callback (nonisolated(unsafe) required for Swift 6 strict concurrency)
nonisolated(unsafe) private var audioTapDebugCounter: Int = 0

// MARK: - Free Functions for Audio Processing (Thread-Safe)
// These are NOT associated with any actor - safe to call from any thread

func audioDownsampleForDisplay(_ samples: [Float], targetCount: Int) -> [Float] {
    guard samples.count > 0 else { return Array(repeating: 0, count: targetCount) }

    var result = [Float](repeating: 0, count: targetCount)
    let chunkSize = max(1, samples.count / targetCount)

    for i in 0..<targetCount {
        let start = i * chunkSize
        let end = min(start + chunkSize, samples.count)
        var maxVal: Float = 0
        for j in start..<end {
            maxVal = max(maxVal, abs(samples[j]))
        }
        result[i] = maxVal
    }
    return result
}

func audioCalculateRMS(_ samples: [Float]) -> Float {
    guard samples.count > 0 else { return 0 }
    var sum: Float = 0
    for sample in samples {
        sum += sample * sample
    }
    return sqrt(sum / Float(samples.count))
}

// MARK: - Thread-Safe Audio Sample Buffer
// Allows audio thread to write samples without MainActor dependency
// Main thread polls this buffer to update UI

final class AudioSampleBuffer: @unchecked Sendable {
    static let shared = AudioSampleBuffer()

    // OSAllocatedUnfairLock is ~2-4x faster than NSLock for uncontended cases
    // Better for real-time audio where low latency is critical
    private let lock = OSAllocatedUnfairLock<AudioBufferState>(initialState: AudioBufferState())

    // Target buffer size for FFT analysis (needs 2048+ samples)
    private let analysisBufferSize = 4096

    private struct AudioBufferState {
        var samples: [Float] = []
        var waveform: [Float] = Array(repeating: 0, count: 128)
        var rms: Float = 0
        // Accumulating buffer for FFT analysis
        var analysisBuffer: [Float] = []
    }

    private init() {}

    /// Write audio data from audio thread (thread-safe, lock-free optimized)
    func write(samples: [Float], waveform: [Float], rms: Float) {
        lock.withLock { state in
            state.samples = samples
            state.waveform = waveform
            state.rms = rms

            // Accumulate samples for FFT analysis
            state.analysisBuffer.append(contentsOf: samples)

            // Keep buffer at target size (sliding window)
            if state.analysisBuffer.count > analysisBufferSize {
                state.analysisBuffer.removeFirst(state.analysisBuffer.count - analysisBufferSize)
            }
        }
    }

    /// Read audio data from main thread (thread-safe, lock-free optimized)
    func read() -> AudioData {
        lock.withLock { state in
            // Return the accumulated analysis buffer for FFT
            AudioData(samples: state.analysisBuffer, waveform: state.waveform, rms: state.rms)
        }
    }
}
