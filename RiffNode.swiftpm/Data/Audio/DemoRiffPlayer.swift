import AVFoundation
import Observation

// MARK: - Demo Riff Player
// Loops the original synthesized arpeggio, or a clean recording the player imported, into
// the pedal input. Imported recordings are kept in Application Support, never bundled.

@Observable
@MainActor
final class DemoRiffPlayer {

    private(set) var isPlaying = false
    var riff: DemoRiff = .originalArpeggio {
        didSet { if riff != oldValue { buffer = nil } }
    }
    /// The imported clean recording, if any.
    private(set) var recordingURL: URL?

    private let player = AVAudioPlayerNode()
    @ObservationIgnored private var buffer: AVAudioPCMBuffer?
    private var format: AVAudioFormat?

    init(recordingURL: URL? = DemoRiffPlayer.storedRecordingURL()) {
        self.recordingURL = recordingURL
    }

    /// Where an imported recording is kept between launches.
    nonisolated static func recordingsFolder() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("DemoRecording", isDirectory: true)
    }

    nonisolated static func storedRecordingURL() -> URL? {
        guard let folder = recordingsFolder(),
              let name = try? FileManager.default.contentsOfDirectory(atPath: folder.path).first else { return nil }
        return folder.appendingPathComponent(name)
    }

    /// Copies a recording the player chose into the app's own storage and selects it.
    func importRecording(from url: URL) throws {
        guard let folder = Self.recordingsFolder() else { throw AudioEngineError.bufferCreationFailed }
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        _ = try AVAudioFile(forReading: destination)   // reject files that aren't audio
        recordingURL = destination
        buffer = nil
        riff = .recording
    }

    /// The imported recording's name, for the menu.
    var recordingName: String? { recordingURL?.deletingPathExtension().lastPathComponent }

    /// True once attached to the engine.
    var isReady: Bool { format != nil }

    func attach(to engine: AVAudioEngine, output: AVAudioNode, format: AVAudioFormat) {
        if self.format != format { buffer = nil }
        self.format = format
        if !engine.attachedNodes.contains(player) { engine.attach(player) }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: output, format: format)
    }

    func detach(from engine: AVAudioEngine) {
        stop()
        if engine.attachedNodes.contains(player) { engine.detach(player) }
        format = nil
        buffer = nil
    }

    /// Starts the loop. `analysisTap` receives the riff so the tuner, spectrum and chord
    /// detector follow it instead of the microphone.
    func play(analysisTap: @escaping AVAudioNodeTapBlock) throws {
        guard !isPlaying, let format else { return }
        guard let buffer = try buffer ?? makeBuffer(format: format) else {
            throw AudioEngineError.bufferCreationFailed
        }
        self.buffer = buffer
        player.removeTap(onBus: 0)
        player.installTap(onBus: 0, bufferSize: 1024, format: format, block: analysisTap)
        player.scheduleBuffer(buffer, at: nil, options: [.loops])
        player.play()
        isPlaying = true
    }

    func stop() {
        guard isPlaying else { return }
        player.stop()
        player.removeTap(onBus: 0)
        isPlaying = false
    }

    /// Stopping the engine halts player nodes; this picks the loop back up after a rewire.
    func resumeAfterEngineRestart() {
        guard isPlaying, let buffer else { return }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [.loops])
        player.play()
    }

    private func makeBuffer(format: AVAudioFormat) throws -> AVAudioPCMBuffer? {
        if riff == .recording {
            guard let url = recordingURL else {
                throw AudioEngineError.bufferCreationFailed
            }
            let file = try AVAudioFile(forReading: url)
            guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
                throw AudioEngineError.bufferCreationFailed
            }
            try file.read(into: source)
            let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * format.sampleRate / source.format.sampleRate)) + 1024
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw AudioEngineError.bufferCreationFailed
            }
            nonisolated(unsafe) var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .endOfStream; return nil }
                supplied = true
                status.pointee = .haveData
                return source
            }
            if let error { throw error }
            guard converted.frameLength > 0 else { throw AudioEngineError.bufferCreationFailed }
            return converted
        }
        let samples = DemoRiffSynthesizer.render(sampleRate: format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for channel in 0..<Int(format.channelCount) {
            samples.withUnsafeBufferPointer { source in
                channels[channel].update(from: source.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}
