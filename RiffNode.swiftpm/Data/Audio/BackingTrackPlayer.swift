import AVFoundation
import Observation

// MARK: - Backing Track Player
// Everything you play along with: the built-in groove and imported songs. Owns its own player
// node; the audio engine attaches it once and decides nothing else about playback.
// Plays dry into the main mixer by default, or through the pedals on request.

@Observable
@MainActor
final class BackingTrackPlayer: BackingTrackManaging {

    // MARK: - State

    private(set) var isBackingTrackPlaying = false
    private(set) var backingTrackVolume: Float = 0.5
    private(set) var backingTrackDuration: TimeInterval = 0
    private(set) var backingTrackCurrentTime: TimeInterval = 0
    /// Display name of the loaded track (nil when none is loaded).
    private(set) var backingTrackName: String?
    /// The loaded track is the synthesized groove rather than an imported song.
    private(set) var isBuiltInJamTrack = false
    /// The track runs through the effects chain instead of straight to the speakers.
    private(set) var backingTrackThroughEffects = false
    /// Key (semitones from E minor) and tempo of the built-in groove.
    private(set) var grooveTranspose = 0
    private(set) var grooveTempo = JamTrackSynthesizer.defaultTempo

    /// A copy of the imported song in the app's temporary folder, for analysis.
    private(set) var songFileURL: URL?

    /// True once attached to a running audio graph.
    var isReady: Bool { format != nil }

    /// Starts the audio engine if it's stopped – pressing play should just work.
    @ObservationIgnored var startEngineIfNeeded: (@MainActor () -> Void)?

    // MARK: - Audio

    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    @ObservationIgnored private weak var engine: AVAudioEngine?
    @ObservationIgnored private weak var dryOutput: AVAudioNode?
    @ObservationIgnored private weak var effectsInput: AVAudioNode?
    private var format: AVAudioFormat?

    // Playback clock: AVAudioPlayerNode has no "current time", so it's tracked from wall time
    @ObservationIgnored private var startTime: Date?
    @ObservationIgnored private var startPosition: TimeInterval = 0
    @ObservationIgnored private var positionTimer: Timer?

    // MARK: - Setup

    /// Attaches the player to the engine's graph, routed dry.
    func attach(to engine: AVAudioEngine, dryOutput: AVAudioNode, effectsInput: AVAudioNode, format: AVAudioFormat) {
        self.engine = engine
        self.dryOutput = dryOutput
        self.effectsInput = effectsInput
        self.format = format
        if !engine.attachedNodes.contains(player) { engine.attach(player) }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: backingTrackThroughEffects ? effectsInput : dryOutput, format: format)
    }

    // MARK: - Loading

    func loadBackingTrack(url: URL) async throws {
        let file = try AVAudioFile(forReading: url)
        let fileFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let fileBuffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: frameCount) else {
            throw AudioEngineError.bufferCreationFailed
        }
        try file.read(into: fileBuffer)

        stopBackingTrack()
        // Keep a private copy: the file picker's access ends once loading is done
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("song-" + url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        songFileURL = (try? FileManager.default.copyItem(at: url, to: copy)) != nil ? copy : nil
        // The player is wired at the engine's format and does not resample:
        // a 44.1 kHz song on a 48 kHz device must be converted first.
        buffer = try convertToProcessingFormat(fileBuffer)
        backingTrackName = url.deletingPathExtension().lastPathComponent
        backingTrackDuration = Double(frameCount) / fileFormat.sampleRate
        backingTrackCurrentTime = 0
        isBuiltInJamTrack = false
    }

    /// Loads the built-in drums-and-bass groove (see JamTrackSynthesizer).
    func loadBuiltInJamTrack(tempo: Double? = nil, transpose: Int? = nil) throws {
        guard let format else { throw AudioEngineError.engineNotSetup }
        if let tempo { grooveTempo = tempo }
        if let transpose { grooveTranspose = transpose }
        let samples = JamTrackSynthesizer.render(sampleRate: format.sampleRate, tempo: grooveTempo, transpose: grooveTranspose)
        guard let groove = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = groove.floatChannelData else { throw AudioEngineError.bufferCreationFailed }
        groove.frameLength = AVAudioFrameCount(samples.count)
        for channel in 0..<Int(format.channelCount) {
            samples.withUnsafeBufferPointer { source in
                channels[channel].update(from: source.baseAddress!, count: samples.count)
            }
        }
        stopBackingTrack()
        buffer = groove
        backingTrackDuration = Double(samples.count) / format.sampleRate
        backingTrackCurrentTime = 0
        isBuiltInJamTrack = true
        backingTrackName = JamTrackSynthesizer.title
    }

    /// Stops and forgets the track.
    func unloadBackingTrack() {
        stopBackingTrack()
        buffer = nil
        backingTrackName = nil
        backingTrackDuration = 0
        backingTrackCurrentTime = 0
        isBuiltInJamTrack = false
    }

    private func convertToProcessingFormat(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let target = format, source.format != target else { return source }
        guard let converter = AVAudioConverter(from: source.format, to: target) else {
            throw AudioEngineError.bufferCreationFailed
        }
        let ratio = target.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw AudioEngineError.bufferCreationFailed
        }
        nonisolated(unsafe) var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        if let conversionError { throw conversionError }
        return output
    }

    // MARK: - Transport

    func playBackingTrack() {
        startEngineIfNeeded?()
        guard let buffer, engine?.isRunning == true else { return }
        player.stop()

        // From the current position to the end, then the whole track on a loop – a jam never just stops
        let framePosition = AVAudioFramePosition(backingTrackCurrentTime * buffer.format.sampleRate)
        let frameCount = AVAudioFramePosition(buffer.frameLength)
        if framePosition > 0, framePosition < frameCount {
            let remaining = AVAudioFrameCount(frameCount - framePosition)
            if let segment = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: remaining),
               let source = buffer.floatChannelData, let destination = segment.floatChannelData {
                segment.frameLength = remaining
                for channel in 0..<Int(buffer.format.channelCount) {
                    destination[channel].update(from: source[channel].advanced(by: Int(framePosition)), count: Int(remaining))
                }
                player.scheduleBuffer(segment, at: nil, options: [])
            }
        }
        player.scheduleBuffer(buffer, at: nil, options: [.loops])

        player.volume = backingTrackVolume
        player.play()
        isBackingTrackPlaying = true
        startTime = Date()
        startPosition = backingTrackCurrentTime
        startPositionTimer()
    }

    func stopBackingTrack() {
        player.stop()
        isBackingTrackPlaying = false
        stopPositionTimer()
        if let startTime {
            backingTrackCurrentTime = startPosition + Date().timeIntervalSince(startTime)
            if backingTrackCurrentTime >= backingTrackDuration { backingTrackCurrentTime = 0 }
        }
        startTime = nil
    }

    func setBackingTrackVolume(_ volume: Float) {
        backingTrackVolume = volume
        player.volume = volume
    }

    func seekBackingTrack(to time: TimeInterval) {
        let wasPlaying = isBackingTrackPlaying
        if wasPlaying {
            player.stop()
            stopPositionTimer()
        }
        backingTrackCurrentTime = max(0, min(time, backingTrackDuration))
        if wasPlaying { playBackingTrack() }
    }

    /// Routes the track through the effects chain (hear your pedals on a real song) or dry.
    func toggleBackingTrackThroughEffects() {
        guard let engine, let dryOutput, let effectsInput, let format else { return }
        let wasPlaying = isBackingTrackPlaying
        let position = backingTrackCurrentTime
        if wasPlaying {
            player.stop()
            stopPositionTimer()
        }

        backingTrackThroughEffects.toggle()
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: backingTrackThroughEffects ? effectsInput : dryOutput, format: format)

        backingTrackCurrentTime = position
        if wasPlaying { playBackingTrack() }
    }

    // MARK: - Position Clock

    private func startPositionTimer() {
        stopPositionTimer()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updatePosition() }
        }
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func updatePosition() {
        guard isBackingTrackPlaying, let startTime else { return }
        backingTrackCurrentTime = startPosition + Date().timeIntervalSince(startTime)
        if backingTrackCurrentTime >= backingTrackDuration {
            backingTrackCurrentTime = 0
            startPosition = 0
            self.startTime = Date()
        }
    }
}
