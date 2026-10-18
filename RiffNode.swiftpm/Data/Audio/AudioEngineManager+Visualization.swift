import AVFoundation
import Foundation

// MARK: - AudioEngineManager · Visualization

extension AudioEngineManager {

    // MARK: - Audio Visualization

    func startRealAudioVisualization() {
        stopVisualization()
        AudioSampleBuffer.shared.reset()
        startVisualizationPolling()

        guard !isDemoRiffPlaying else { return }

        // Refresh device detection
        detectAudioInputDevices()

        guard let input = inputNode else {
            Log.audio.notice("No input node available - visualization disabled")
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
            Log.audio.notice("Invalid input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch")
            return
        }

        Log.audio.debug("Installing audio tap: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch")

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

        Log.audio.debug("Audio visualization started successfully")
    }

    func startVisualizationPolling() {
        visualizationTask?.cancel()
        // Use a simple async loop that's fully MainActor-isolated
        visualizationTask = Task {
            await runVisualizationLoop()
        }
    }

    private func runVisualizationLoop() async {
        var frameCounter = 0
        while !Task.isCancelled && isRunning {
            let data = AudioSampleBuffer.shared.read()

            inputLevel = data.rms
            outputLevel = outputLevelStore.rms
            waveformSamples = data.waveform

            // Feed audio samples to FFT/chord every 3rd frame (~10 Hz at 30fps base rate)
            // 10fps is more than enough for educational spectrum + pitch display
            frameCounter += 1
            if frameCounter >= 3 && !data.samples.isEmpty && data.samples.count >= 2048 {
                frameCounter = 0
                latestAudioSamples = data.samples

                if let callback = onAudioSamplesAvailable {
                    callback(data.samples)
                }
            }

            // 33ms = ~30fps — half the @Observable update rate vs 60fps, no perceptible difference
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    func stopVisualization() {
        visualizationTask?.cancel()
        visualizationTask = nil
        if tapInstalled {
            inputNode?.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioSampleBuffer.removeAll()
    }
}
