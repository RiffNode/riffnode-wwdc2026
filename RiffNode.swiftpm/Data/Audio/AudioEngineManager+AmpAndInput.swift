import AVFoundation
import Foundation

// MARK: - AudioEngineManager · AmpAndInput

extension AudioEngineManager {

    // MARK: - Amp & Cabinet

    func applyAmpSettings() {
        guard let units = effectUnits else { return }
        if let format = processingFormat { units.ampKernel.amp.setSampleRate(Float(format.sampleRate)) }
        units.ampKernel.amp.apply(ampSettings)
        units.amp.auAudioUnit.shouldBypassEffect = !ampSettings.isEnabled
    }

    /// Tone stack + cabinet response in dB, for drawing the amp's curve.
    /// With an impulse response loaded, its measured response is added in.
    func ampResponse(at frequencies: [Float]) -> [Float] {
        var designed = ampSettings
        let usesIR = designed.cabinet == .impulse && !cabinetIR.isEmpty
        if designed.cabinet == .impulse { designed.cabinet = .direct }
        var response = AmpDesign.response(for: designed, at: frequencies)
        if usesIR, let rate = processingFormat?.sampleRate {
            let ir = cabinetIR
            for (index, f) in frequencies.enumerated() {
                let w = 2 * Double.pi * Double(f) / rate
                var re = 0.0, im = 0.0
                for (n, h) in ir.enumerated() { re += Double(h) * cos(w * Double(n)); im -= Double(h) * sin(w * Double(n)) }
                response[index] += Float(10 * log10(max(re * re + im * im, 1e-12)))
            }
        }
        return response
    }

    /// Loads a speaker-cabinet impulse response: first channel, resampled to the engine's
    /// rate, trimmed to 2048 taps and normalised so it doesn't change the overall level.
    func loadCabinetIR(from url: URL) async throws {
        guard let units = effectUnits, let format = processingFormat else { throw AudioEngineError.engineNotSetup }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: url)
        guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(min(file.length, 96_000))) else {
            throw AudioEngineError.bufferCreationFailed
        }
        try file.read(into: source, frameCount: source.frameCapacity)
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1),
              let converter = AVAudioConverter(from: source.format, to: mono),
              let resampled = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * format.sampleRate / source.format.sampleRate) + 64) else {
            throw AudioEngineError.bufferCreationFailed
        }
        nonisolated(unsafe) var consumed = false
        var conversionError: NSError?
        converter.convert(to: resampled, error: &conversionError) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return source
        }
        if let conversionError { throw conversionError }
        guard let data = resampled.floatChannelData?[0], resampled.frameLength > 0 else { throw AudioEngineError.bufferCreationFailed }
        var taps = Array(UnsafeBufferPointer(start: data, count: min(Int(resampled.frameLength), AmpProcessor.maxIRLength)))
        // Fade out the last 5% so the trim doesn't click; loudest frequency at unity gain
        let fade = max(1, taps.count / 20)
        for i in 0..<fade { taps[taps.count - 1 - i] *= Float(i) / Float(fade) }
        taps = AmpProcessor.normalizedIR(taps, sampleRate: Float(format.sampleRate))

        cabinetIR = taps
        units.ampKernel.amp.loadIR(taps)
        cabinetIRName = url.deletingPathExtension().lastPathComponent
        ampSettings.cabinet = .impulse
        applyAmpSettings()
    }

    /// Loads a Neural Amp Modeler capture (.nam, standard WaveNet) as the amp.
    func loadNeuralModel(from url: URL) async throws {
        guard let units = effectUnits else { throw AudioEngineError.engineNotSetup }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        // Parsing and pre-warming take a moment; keep it off the main thread
        let model = try await Task.detached(priority: .userInitiated) {
            try NeuralAmpModel(data: data, name: name)
        }.value
        neuralModels.append(model)
        units.ampKernel.amp.setNeuralModel(model)
        neuralModelName = name
        ampSettings.model = .captured
        applyAmpSettings()
    }

    // MARK: - Input Stage

    func applyInputSettings() {
        effectUnits?.inputKernel.input.apply(inputSettings)
    }

    func inputResponse(at frequencies: [Float]) -> [Float] {
        InputDesign.response(for: inputSettings, at: frequencies)
    }
}
