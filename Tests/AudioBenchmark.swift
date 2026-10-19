import AVFoundation
import Foundation

// MARK: - Audio Benchmark
// How much of the real-time budget RiffNode's DSP uses. Renders a busy board offline in
// 128-frame buffers (2.7 ms at 48 kHz, the size live playing uses) and times it. Pass a
// .nam capture to also time the neural amp on its own.

@main
struct AudioBenchmark {
    static let rate = 48_000.0
    static let frames: AVAudioFrameCount = 128
    static let seconds = 20.0

    nonisolated static func discardTap(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {}

    @MainActor static func main() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let budget = Double(frames) / rate * 1000

        // Every pedal RiffNode builds itself, plus the input stage and the amp, in one chain
        let modes: [ModulationKernel.Mode] = [.input, .wah, .overdrive, .distortion, .fuzz, .chorus,
                                              .phaser, .flanger, .tremolo, .analogDelay, .amp]
        let engine = AVAudioEngine()
        var units: [AVAudioUnit] = []
        for mode in modes {
            let (unit, kernel) = try await ModulationAudioUnit.make(mode)
            kernel.isBypassed = false
            engine.attach(unit)
            units.append(unit)
        }
        for (a, b) in zip(units, units.dropFirst()) { engine.connect(a, to: b, format: format) }
        engine.connect(units.last!, to: engine.mainMixerNode, format: format)

        let player = DemoRiffPlayer(recordingURL: nil)
        player.attach(to: engine, output: units[0], format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: frames)
        try engine.start()
        try player.play(analysisTap: discardTap)

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        let total = Int(seconds * rate / Double(frames))
        var times: [Double] = []
        var peak: Float = 0
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<total {
            let t0 = clock.now
            _ = try engine.renderOffline(frames, to: buffer)
            times.append((clock.now - t0).milliseconds)
            if let data = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
            }
        }
        guard peak > 0.001 else { print("No audio came out of the board"); exit(1) }
        let elapsed = (clock.now - start).milliseconds
        player.stop(); engine.stop()
        report("Board: \(modes.count) DSP stages", elapsed: elapsed, times: times, budget: budget)

        // The neural amp on its own, mono, as the amp unit runs it
        if let path = CommandLine.arguments.dropFirst().first {
            let model = try NeuralAmpModel(data: Data(contentsOf: URL(fileURLWithPath: path)),
                                           name: URL(fileURLWithPath: path).lastPathComponent)
            let block = UnsafeMutablePointer<Float>.allocate(capacity: Int(frames))
            defer { block.deallocate() }
            var phase: Float = 0
            var times: [Double] = []
            let start = clock.now
            for _ in 0..<total {
                for i in 0..<Int(frames) {
                    block[i] = 0.3 * sin(phase); phase += 2 * .pi * 110 / Float(rate)
                }
                let t0 = clock.now
                model.process(block, count: Int(frames))
                times.append((clock.now - t0).milliseconds)
            }
            report("Neural amp: \(model.name)", elapsed: (clock.now - start).milliseconds, times: times, budget: budget)
        }
    }

    /// `times` per buffer; the first second is warm-up. The 99.9th percentile rather than the
    /// maximum: this runs on an ordinary thread, so one preemption by the OS would dominate a max.
    static func report(_ title: String, elapsed: Double, times: [Double], budget: Double) {
        let audio = seconds * 1000
        let steady = times.dropFirst(Int(rate) / Int(frames)).sorted()
        let p999 = steady[min(steady.count - 1, Int(Double(steady.count) * 0.999))]
        print(title)
        print(String(format: "  %.0f× real time · %.1f%% of one core · average %.3f ms, 99.9th percentile %.3f ms per %.2f ms buffer",
                     audio / elapsed, elapsed / audio * 100, elapsed / Double(times.count), p999, budget))
    }
}

extension Duration {
    var milliseconds: Double {
        let (s, attoseconds) = components
        return Double(s) * 1000 + Double(attoseconds) / 1e15
    }
}
