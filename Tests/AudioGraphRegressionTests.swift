import AVFoundation
import Foundation
import Synchronization


@main
struct AudioGraphRegressionTests {
    nonisolated static func discardTap(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {}

    /// A synthetic clean "recording" (decaying plucked notes, 44.1 kHz mono) written to a temp
    /// file, standing in for a player's imported recording – the tests need no bundled audio.
    /// Set RIFFNODE_TEST_RECORDING to a WAV of your own (e.g. in the gitignored demo-riffs/)
    /// to run the same checks on a real recording.
    static func makeTestRecording() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["RIFFNODE_TEST_RECORDING"] {
            return URL(fileURLWithPath: path)
        }
        let rate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let note = [82.41, 110.0, 146.83, 196.0][Int(t * 2) % 4]
            data[i] = Float(0.3 * sin(2 * .pi * note * t) * exp(-(t.truncatingRemainder(dividingBy: 0.5)) * 4))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("riffnode-test-recording.wav")
        try? FileManager.default.removeItem(at: url)
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        return url
    }

    @MainActor static func render(rate: Double, bypassed: Bool, riff: DemoRiff = .recording) async throws -> [Float] {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let (distortion, kernel) = try await ModulationAudioUnit.make(.distortion)
        kernel.depth = 0.65
        kernel.level = 0.5
        kernel.isBypassed = bypassed
        engine.attach(distortion)
        engine.connect(distortion, to: engine.mainMixerNode, format: format)
        let player = DemoRiffPlayer(recordingURL: try makeTestRecording())
        player.riff = riff
        player.attach(to: engine, output: distortion, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        try player.play(analysisTap: discardTap)
        defer { player.stop(); engine.stop() }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var samples: [Float] = []
        let target = Int(rate)
        var attempts = 0
        while samples.count < target && attempts < 100 {
            attempts += 1
            let count = AVAudioFrameCount(min(4096, target - samples.count))
            let status = try engine.renderOffline(count, to: buffer)
            if status == .success, let data = buffer.floatChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
                // Mono source must reach both stereo output channels.
                for i in 0..<Int(buffer.frameLength) {
                    guard abs(data[0][i] - data[1][i]) < 0.0001 else { throw Failure.stereoMismatch }
                }
            }
        }
        guard samples.count == target, samples.allSatisfy(\.isFinite), samples.contains(where: { abs($0) > 0.001 }) else {
            throw Failure.missingAudio
        }
        return samples
    }

    enum Failure: Error { case missingAudio, stereoMismatch, noPedalDifference, tornBank }

    /// A writer rewriting banks as fast as it can while a reader copies them: every copy the
    /// reader takes must be whole (all slots from one write), never half old, half new.
    final class HandshakeRig: @unchecked Sendable {
        let handshake = BankHandshake()
        let banks = UnsafeMutablePointer<Int>.allocate(capacity: 2 * 64)
        init() { banks.initialize(repeating: 0, count: 128) }
    }

    static func checkBankHandshake() throws {
        let rig = HandshakeRig()
        let done = Atomic<Bool>(false)
        let torn = Atomic<Int>(0)
        let reader = Thread {
            while !done.load(ordering: .relaxed) {
                let bank = rig.handshake.beginRead()
                let base = rig.banks + bank * 64
                let first = base[0]
                for i in 1..<64 where base[i] != first { torn.add(1, ordering: .relaxed); break }
                rig.handshake.endRead()
            }
        }
        reader.start()
        for value in 1...200_000 {
            let bank = rig.handshake.writableBank()
            let base = rig.banks + bank * 64
            for i in 0..<64 { base[i] = value }
            rig.handshake.publish(bank)
        }
        done.store(true, ordering: .relaxed)
        Thread.sleep(forTimeInterval: 0.05)
        guard torn.load(ordering: .relaxed) == 0 else { throw Failure.tornBank }
    }

    @MainActor static func main() async throws {
        var count = 0
        for rate in [44100.0, 48000.0] {
            for riff in [DemoRiff.recording] {
            let clean = try await render(rate: rate, bypassed: true, riff: riff)
            let processed = try await render(rate: rate, bypassed: false, riff: riff)
            let difference = zip(clean, processed).reduce(Float(0)) { $0 + abs($1.0 - $1.1) } / Float(clean.count)
            guard difference > 0.001 else { throw Failure.noPedalDifference }
            count += 1
            print("PASS \(riff.title) -> stereo at \(Int(rate)) Hz; distortion mean difference \(difference)")
            }
        }
        // Every classic drive voicing renders a finite, audible signal through the shared processor
        for model in PedalModel.all {
            guard case .drive = model.voicing else { continue }
            let engine = AVAudioEngine()
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
            let (unit, kernel) = try await ModulationAudioUnit.make(.distortion)
            kernel.setVoicing(model.voicing)
            kernel.depth = 0.6; kernel.tone = 0.5; kernel.level = 0.6
            engine.attach(unit)
            engine.connect(unit, to: engine.mainMixerNode, format: format)
            let player = DemoRiffPlayer()
            player.riff = .originalArpeggio
            player.attach(to: engine, output: unit, format: format)
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            try engine.start()
            try player.play(analysisTap: discardTap)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
            var peak: Float = 0
            for _ in 0..<12 {
                _ = try engine.renderOffline(4096, to: buffer)
                let data = buffer.floatChannelData![0]
                for i in 0..<Int(buffer.frameLength) {
                    guard data[i].isFinite else { throw Failure.missingAudio }
                    peak = max(peak, abs(data[i]))
                }
            }
            player.stop(); engine.stop()
            guard peak > 0.01, peak < 8 else { throw Failure.missingAudio }
        }
        count += 1
        print("PASS all \(PedalModel.all.filter { if case .drive = $0.voicing { true } else { false } }.count) classic drive voicings render cleanly")

        try checkBankHandshake()
        count += 1
        print("PASS coefficient banks are never read half-written (200 000 swaps)")
        _ = try await render(rate: 48000, bypassed: true, riff: .originalArpeggio)
        count += 1
        print("PASS original synthesized riff remains playable")
        print("\(count)/\(count) offline audio graph checks passed")
    }
}
