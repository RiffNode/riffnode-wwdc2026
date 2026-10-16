import AVFoundation
import Observation

// MARK: - Demo Riff Player
// Loops the synthesized guitar (DemoRiffSynthesizer) into the effects chain exactly where a
// real guitar would enter. The engine decides when; this owns the player node and the loop.

@Observable
@MainActor
final class DemoRiffPlayer {

    private(set) var isPlaying = false

    private let player = AVAudioPlayerNode()
    @ObservationIgnored private var buffer: AVAudioPCMBuffer?
    private var format: AVAudioFormat?

    /// True once attached to the engine.
    var isReady: Bool { format != nil }

    func attach(to engine: AVAudioEngine, output: AVAudioNode, format: AVAudioFormat) {
        self.format = format
        if !engine.attachedNodes.contains(player) { engine.attach(player) }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: output, format: format)
    }

    /// Starts the loop. `analysisTap` receives the riff so the tuner, spectrum and chord
    /// detector follow it instead of the microphone.
    func play(analysisTap: @escaping AVAudioNodeTapBlock) {
        guard !isPlaying, let format, let buffer = buffer ?? makeBuffer(format: format) else { return }
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

    private func makeBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
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
