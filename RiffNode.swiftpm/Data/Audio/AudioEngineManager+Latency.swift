import AVFoundation
import Foundation

// MARK: - AudioEngineManager · Latency

extension AudioEngineManager {

    // MARK: - Latency

    func refreshLatency() {
        #if os(iOS) || targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        bufferDurationMs = session.ioBufferDuration * 1000
        roundTripLatencyMs = (session.inputLatency + session.outputLatency + 2 * session.ioBufferDuration) * 1000
        let bluetooth: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        isBluetoothOutput = session.currentRoute.outputs.contains { bluetooth.contains($0.portType) }
        #endif
    }
}
