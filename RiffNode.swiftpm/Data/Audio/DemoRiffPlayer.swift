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
    /// Clean recordings the player imported, by name.
    private(set) var recordings: [URL] = []
    /// The recording that plays when `riff` is `.recording`.
    private(set) var selectedRecording: URL?

    private let player = AVAudioPlayerNode()
    @ObservationIgnored private var buffer: AVAudioPCMBuffer?
    private var format: AVAudioFormat?

    /// `recordingURL` plays a specific file (the tests); otherwise the imported ones are listed.
    init(recordingURL: URL? = nil) {
        if let recordingURL {
            recordings = [recordingURL]
        } else {
            reloadRecordings()
        }
        selectedRecording = recordings.first
    }

    /// Where imported recordings are kept between launches.
    nonisolated static func recordingsFolder() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("DemoRecording", isDirectory: true)
    }

    private func reloadRecordings() {
        guard let folder = Self.recordingsFolder(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            recordings = []
            return
        }
        recordings = names.filter { !$0.hasPrefix(".") }.sorted()
            .map { folder.appendingPathComponent($0) }
    }

    /// Copies recordings the player chose into the app's own storage and selects the first.
    /// Files that aren't audio are skipped; throws only if none could be used.
    func importRecordings(from urls: [URL], access: (URL, () throws -> Void) throws -> Void) throws {
        guard let folder = Self.recordingsFolder() else { throw AudioEngineError.bufferCreationFailed }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var imported: [URL] = []
        for url in urls {
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            do {
                try access(url) {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: url, to: destination)
                }
                _ = try AVAudioFile(forReading: destination)   // reject files that aren't audio
                imported.append(destination)
            } catch {
                try? FileManager.default.removeItem(at: destination)
            }
        }
        reloadRecordings()
        guard let first = imported.first else { throw AudioEngineError.bufferCreationFailed }
        select(first)
    }

    /// Plays this recording next.
    func select(_ url: URL) {
        selectedRecording = url
        buffer = nil
        riff = .recording
    }

    func removeRecording(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reloadRecordings()
        if selectedRecording == url {
            selectedRecording = recordings.first
            buffer = nil
            if selectedRecording == nil { riff = .originalArpeggio }
        }
    }

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
            guard let url = selectedRecording else {
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
