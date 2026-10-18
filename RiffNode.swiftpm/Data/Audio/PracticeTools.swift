import AVFoundation
import Observation
import os

// MARK: - Metronome
// A synthesized click – accented on beat one – looped one bar at a time. Plays straight into
// the main mixer, so your pedals never colour it.

@Observable
@MainActor
final class MetronomePlayer: MetronomeControlling {

    private(set) var isPlaying = false
    private(set) var beatsPerMinute: Double = 100
    static let tempoRange: ClosedRange<Double> = 40...240
    var volume: Float = 0.6 { didSet { player.volume = volume } }

    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private weak var engine: AVAudioEngine?
    @ObservationIgnored private var format: AVAudioFormat?
    @ObservationIgnored var startEngineIfNeeded: (@MainActor () -> Void)?

    var isReady: Bool { format != nil }

    func attach(to engine: AVAudioEngine, output: AVAudioNode, format: AVAudioFormat) {
        self.engine = engine
        self.format = format
        if !engine.attachedNodes.contains(player) { engine.attach(player) }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: output, format: format)
        player.volume = volume
    }

    func toggle() { isPlaying ? stop() : start() }

    func start() {
        startEngineIfNeeded?()
        guard let format, engine?.isRunning == true, let bar = makeBar(format: format) else { return }
        player.stop()
        player.scheduleBuffer(bar, at: nil, options: [.loops])
        player.play()
        isPlaying = true
    }

    func stop() {
        player.stop()
        isPlaying = false
    }

    func setTempo(_ bpm: Double) {
        beatsPerMinute = min(max(bpm, Self.tempoRange.lowerBound), Self.tempoRange.upperBound)
        if isPlaying { start() }
    }

    /// Resumes after the engine was restarted for a rewire.
    func resumeAfterEngineRestart() { if isPlaying { start() } }

    /// One bar of 4/4: a short decaying sine per beat, higher and louder on beat one.
    private func makeBar(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let beatFrames = Int(60 / beatsPerMinute * rate)
        let frames = beatFrames * 4
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<Int(format.channelCount) { channels[channel].update(repeating: 0, count: frames) }
        let clickFrames = Int(0.03 * rate)
        for beat in 0..<4 {
            let frequency = beat == 0 ? 1_760.0 : 1_175.0
            let gain: Float = beat == 0 ? 0.6 : 0.38
            for i in 0..<clickFrames {
                let t = Double(i) / rate
                let sample = Float(sin(2 * .pi * frequency * t) * exp(-t * 120)) * gain
                for channel in 0..<Int(format.channelCount) { channels[channel][beat * beatFrames + i] = sample }
            }
        }
        return buffer
    }
}

// MARK: - Looper
// One-footswitch looper: Record → Play → Overdub → Play… It records what comes out of the
// amp – your guitar through the pedals – not the backing track or the loop itself, so
// layers stack cleanly. Up to 60 seconds.

/// Shared with the tap thread: the samples being recorded or overdubbed.
final class LoopTape: @unchecked Sendable {
    struct State {
        var isRecording = false
        var isOverdubbing = false
        var left: [Float] = []
        var right: [Float] = []
        /// The playing loop's memory, for overdubs (summed in place)
        var loopLeft: UnsafeMutablePointer<Float>?
        var loopRight: UnsafeMutablePointer<Float>?
        var loopLength = 0
        var overdubPosition = 0
    }
    let state = OSAllocatedUnfairLock(uncheckedState: State())
    static let maxFrames = 48_000 * 60

    /// Tap block: runs on the tap's thread, never the render thread.
    nonisolated static func tapBlock(for tape: LoopTape) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let left = data[0]
            let right = buffer.format.channelCount > 1 ? data[1] : data[0]
            tape.state.withLockUnchecked { s in
                if s.isRecording, s.left.count < maxFrames {
                    s.left.append(contentsOf: UnsafeBufferPointer(start: left, count: frames))
                    s.right.append(contentsOf: UnsafeBufferPointer(start: right, count: frames))
                } else if s.isOverdubbing, let loopLeft = s.loopLeft, let loopRight = s.loopRight, s.loopLength > 0 {
                    for i in 0..<frames {
                        let position = (s.overdubPosition + i) % s.loopLength
                        loopLeft[position] += left[i]
                        loopRight[position] += right[i]
                    }
                    s.overdubPosition = (s.overdubPosition + frames) % s.loopLength
                }
            }
        }
    }
}

@Observable
@MainActor
final class Looper: LooperControlling {

    private(set) var state: LooperState = .empty
    private(set) var loopDuration: TimeInterval = 0
    private(set) var canUndo = false
    var volume: Float = 0.9 { didSet { player.volume = volume } }

    @ObservationIgnored let tape = LoopTape()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private weak var engine: AVAudioEngine?
    @ObservationIgnored private var format: AVAudioFormat?
    @ObservationIgnored private var loop: AVAudioPCMBuffer?
    @ObservationIgnored private var undoLeft: [Float] = []
    @ObservationIgnored private var undoRight: [Float] = []
    /// Asks the engine to tap the amp's output (true) or remove the tap (false).
    @ObservationIgnored var setRecordingTap: (@MainActor (Bool) -> Void)?
    @ObservationIgnored var startEngineIfNeeded: (@MainActor () -> Void)?

    var isReady: Bool { format != nil }

    func attach(to engine: AVAudioEngine, output: AVAudioNode, format: AVAudioFormat) {
        self.engine = engine
        self.format = format
        if !engine.attachedNodes.contains(player) { engine.attach(player) }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: output, format: format)
        player.volume = volume
    }

    /// The looper's one footswitch.
    func press() {
        switch state {
        case .empty: startRecording()
        case .stopped where loop == nil: startRecording()
        case .recording: finishRecording()
        case .playing: startOverdub()
        case .overdubbing: finishOverdub()
        case .stopped: play()
        }
    }

    func stop() {
        if state == .recording { finishRecording() }
        if state == .overdubbing { finishOverdub() }
        player.stop()
        if loop != nil { state = .stopped }
    }

    func clear() {
        player.stop()
        tape.state.withLockUnchecked { $0 = LoopTape.State() }
        setRecordingTap?(false)
        loop = nil
        loopDuration = 0
        canUndo = false
        state = .empty
    }

    func undo() {
        guard canUndo, let loop, let data = loop.floatChannelData else { return }
        let count = min(undoLeft.count, Int(loop.frameLength))
        undoLeft.withUnsafeBufferPointer { data[0].update(from: $0.baseAddress!, count: count) }
        if loop.format.channelCount > 1 {
            undoRight.withUnsafeBufferPointer { data[1].update(from: $0.baseAddress!, count: count) }
        }
        canUndo = false
    }

    // MARK: Steps

    private func startRecording() {
        startEngineIfNeeded?()
        guard engine?.isRunning == true else { return }
        tape.state.withLockUnchecked { s in
            s = LoopTape.State()
            s.isRecording = true
            s.left.reserveCapacity(LoopTape.maxFrames)
            s.right.reserveCapacity(LoopTape.maxFrames)
        }
        setRecordingTap?(true)
        state = .recording
    }

    private func finishRecording() {
        let (left, right) = tape.state.withLockUnchecked { s -> ([Float], [Float]) in
            s.isRecording = false
            return (s.left, s.right)
        }
        guard let format, left.count > Int(format.sampleRate * 0.25),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count)),
              let data = buffer.floatChannelData else {
            clear()
            return
        }
        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { data[0].update(from: $0.baseAddress!, count: left.count) }
        if format.channelCount > 1 {
            right.withUnsafeBufferPointer { data[1].update(from: $0.baseAddress!, count: right.count) }
        }
        loop = buffer
        loopDuration = Double(left.count) / format.sampleRate
        tape.state.withLockUnchecked { s in
            s.left = []; s.right = []
            s.loopLeft = data[0]
            s.loopRight = format.channelCount > 1 ? data[1] : data[0]
            s.loopLength = Int(buffer.frameLength)
        }
        play()
    }

    /// Picks the loop back up after the engine was restarted for a rewire.
    func resumeAfterEngineRestart() {
        if state == .playing || state == .overdubbing { play() }
    }

    private func play() {
        guard let loop else { return }
        player.stop()
        player.scheduleBuffer(loop, at: nil, options: [.loops])
        player.play()
        if state != .overdubbing { state = .playing }
    }

    private func startOverdub() {
        guard let loop, let data = loop.floatChannelData else { return }
        // Keep the loop as it was, for Undo
        let count = Int(loop.frameLength)
        undoLeft = Array(UnsafeBufferPointer(start: data[0], count: count))
        undoRight = loop.format.channelCount > 1 ? Array(UnsafeBufferPointer(start: data[1], count: count)) : undoLeft
        // Start writing where the loop is playing now
        var current = 0
        if let nodeTime = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: nodeTime) {
            current = Int(playerTime.sampleTime) % count
        }
        let phase = current
        tape.state.withLockUnchecked { s in
            s.overdubPosition = max(0, phase)
            s.isOverdubbing = true
        }
        setRecordingTap?(true)
        state = .overdubbing
    }

    private func finishOverdub() {
        tape.state.withLockUnchecked { $0.isOverdubbing = false }
        canUndo = true
        state = .playing
    }
}
