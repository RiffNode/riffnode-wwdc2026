import AVFoundation
import Foundation

// MARK: - AudioEngineManager · Reverb

extension AudioEngineManager {

    // MARK: - Reverb Preset Selection

    /// Select an appropriate AVAudioUnitReverb preset based on decay time
    func selectReverbPreset(decaySeconds: Float, on reverb: AVAudioUnitReverb) {
        let preset: AVAudioUnitReverbPreset
        if decaySeconds < 0.8 {
            preset = .smallRoom
        } else if decaySeconds < 1.5 {
            preset = .mediumRoom
        } else if decaySeconds < 2.5 {
            preset = .mediumHall
        } else if decaySeconds < 4.0 {
            preset = .largeHall
        } else {
            preset = .cathedral
        }
        reverb.loadFactoryPreset(preset)
    }
}
