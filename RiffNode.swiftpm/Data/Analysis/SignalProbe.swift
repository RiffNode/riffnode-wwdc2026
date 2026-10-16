import AVFoundation
import os

// MARK: - Signal Probe
// Captures the signal on both sides of one pedal – what goes in and what comes out – so the
// Signal Lab can show what that pedal physically does: clipped peaks, a squeezed volume
// envelope, new harmonics, echoes. Written on the audio thread, read on the main thread.

final class SignalProbeStore: @unchecked Sendable {

    enum Side: Int, Sendable { case before = 0, after = 1 }


    static let sampleCount = 4096
    static let envelopeBlock = 512
    static let envelopeCount = 300

    private let state = OSAllocatedUnfairLock(initialState: [SignalCapture(), SignalCapture()])
    /// Leftover samples that didn't fill a whole envelope block yet, per side.
    private let pending = OSAllocatedUnfairLock(initialState: [[Float](), [Float]()])

    func reset() {
        state.withLock { $0 = [SignalCapture(), SignalCapture()] }
        pending.withLock { $0 = [[], []] }
    }

    func snapshot() -> (before: SignalCapture, after: SignalCapture) {
        state.withLock { ($0[0], $0[1]) }
    }

    func write(_ side: Side, buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return }

        // Mix to mono so stereo pedals (chorus) are measured as heard
        var mixed = [Float](repeating: 0, count: frames)
        let scale = 1 / Float(channelCount)
        for channel in 0..<channelCount {
            let data = channels[channel]
            for i in 0..<frames { mixed[i] += data[i] * scale }
        }
        let mono = mixed

        // Envelope blocks
        let blocks: [Float] = pending.withLock { pending in
            pending[side.rawValue].append(contentsOf: mono)
            var result: [Float] = []
            let block = Self.envelopeBlock
            while pending[side.rawValue].count >= block {
                let chunk = pending[side.rawValue].prefix(block)
                var sum: Float = 0
                for s in chunk { sum += s * s }
                result.append((sum / Float(block)).squareRoot())
                pending[side.rawValue].removeFirst(block)
            }
            return result
        }

        let endTime = time.isSampleTimeValid ? time.sampleTime + Int64(frames) : 0
        let sampleRate = buffer.format.sampleRate
        state.withLock { state in
            var capture = state[side.rawValue]
            capture.samples.append(contentsOf: mono)
            if capture.samples.count > Self.sampleCount {
                capture.samples.removeFirst(capture.samples.count - Self.sampleCount)
            }
            capture.envelope.append(contentsOf: blocks)
            if capture.envelope.count > Self.envelopeCount {
                capture.envelope.removeFirst(capture.envelope.count - Self.envelopeCount)
            }
            capture.endSampleTime = endTime
            capture.sampleRate = sampleRate
            state[side.rawValue] = capture
        }
    }

    /// Builds the tap block outside any actor, so it never inherits @MainActor isolation
    /// and can safely run on the audio thread.
    nonisolated static func tapBlock(for store: SignalProbeStore, side: Side) -> AVAudioNodeTapBlock {
        { buffer, time in store.write(side, buffer: buffer, time: time) }
    }
}

// MARK: - Output Level
// The real loudness at the main mixer, for the OUT meter.

final class OutputLevelStore: @unchecked Sendable {
    private let level = OSAllocatedUnfairLock(initialState: Float(0))

    var rms: Float { level.withLock { $0 } }

    func reset() { level.withLock { $0 = 0 } }

    nonisolated static func tapBlock(for store: OutputLevelStore) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            for i in 0..<frames { sum += data[i] * data[i] }
            let rms = (sum / Float(frames)).squareRoot()
            store.level.withLock { $0 = rms }
        }
    }
}
