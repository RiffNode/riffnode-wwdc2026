import AVFoundation
import Foundation

// MARK: - AudioEngineManager · DemoRiff

extension AudioEngineManager {

    // MARK: - Demo Riff

    var isDemoRiffPlaying: Bool { demoRiff.isPlaying }

    var selectedDemoRiff: DemoRiff {
        get { demoRiff.riff }
        set {
            guard newValue != demoRiff.riff else { return }
            let wasPlaying = isDemoRiffPlaying
            if wasPlaying { stopDemoRiff() }
            demoRiff.riff = newValue
            if wasPlaying { startDemoRiff() }
        }
    }

    var demoRecordings: [String] { demoRiff.recordings.map(Self.recordingName) }
    var selectedDemoRecording: String? { demoRiff.selectedRecording.map(Self.recordingName) }

    private nonisolated static func recordingName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Imports clean recordings (the player's own) and plays the first through the pedals.
    func importDemoRecordings(from urls: [URL]) throws {
        stopDemoRiff()
        try demoRiff.importRecordings(from: urls) { url, copy in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            try copy()
        }
        errorMessage = nil
        startDemoRiff()
    }

    func playDemoRecording(named name: String) {
        guard let url = demoRiff.recordings.first(where: { Self.recordingName($0) == name }) else { return }
        stopDemoRiff()
        demoRiff.select(url)
        startDemoRiff()
    }

    func removeDemoRecording(named name: String) {
        guard let url = demoRiff.recordings.first(where: { Self.recordingName($0) == name }) else { return }
        let wasPlaying = isDemoRiffPlaying && demoRiff.selectedRecording == url
        if wasPlaying { stopDemoRiff() }
        demoRiff.removeRecording(url)
        if wasPlaying { startDemoRiff() }
    }

    /// True once the effects chain exists, i.e. there is somewhere to send the riff.
    var canPlayDemoRiff: Bool { demoRiff.isReady }

    func toggleDemoRiff() {
        isDemoRiffPlaying ? stopDemoRiff() : startDemoRiff()
    }

    /// Loops the demo riff into the effects chain; the tuner, spectrum and chord detector follow it.
    func startDemoRiff() {
        guard !isDemoRiffPlaying, demoRiff.isReady else { return }
        if !isRunning { try? start() }
        guard isRunning else { return }
        inputNode?.removeTap(onBus: 0)   // the analysis tap moves from the mic to the riff
        tapInstalled = false
        formatConverterMixer?.outputVolume = 0
        AudioSampleBuffer.shared.reset()
        do {
            try demoRiff.play(analysisTap: audioTapCallback)
        } catch {
            errorMessage = "Couldn't load the demo riff: \(error.localizedDescription)"
            if demoRiff.riff == .recording {
                // A missing or unreadable recording: fall back to the original riff
                demoRiff.riff = .originalArpeggio
                try? demoRiff.play(analysisTap: audioTapCallback)
            }
            if !demoRiff.isPlaying {
                formatConverterMixer?.outputVolume = 1
                startRealAudioVisualization()
            }
        }
        startVisualizationPolling()
    }

    func stopDemoRiff() {
        guard isDemoRiffPlaying else { return }
        demoRiff.stop()
        formatConverterMixer?.outputVolume = 1
        AudioSampleBuffer.shared.reset()
        // Hand the analysis tap back to the microphone
        if isRunning { startRealAudioVisualization() }
    }
}
