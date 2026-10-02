import SwiftUI
import AVFoundation

// MARK: - EQ Band Model

struct EQBand: Identifiable, Equatable {
    let id: Int
    var frequency: Float      // 20 - 20000 Hz
    var gain: Float           // -24 to +24 dB
    var q: Float              // 0.1 to 10
    var type: BandType
    var isEnabled: Bool

    enum BandType: String, CaseIterable {
        case highPass = "High Pass"
        case lowShelf = "Low Shelf"
        case peak = "Peak"
        case highShelf = "High Shelf"
        case lowPass = "Low Pass"

        var icon: String {
            switch self {
            case .highPass: return "line.diagonal"
            case .lowShelf: return "arrow.down.left"
            case .peak: return "diamond"
            case .highShelf: return "arrow.up.right"
            case .lowPass: return "line.diagonal"
            }
        }

        var shortName: String {
            switch self {
            case .highPass: return "HP"
            case .lowShelf: return "LS"
            case .peak: return "PK"
            case .highShelf: return "HS"
            case .lowPass: return "LP"
            }
        }

        var audioUnitFilterType: AVAudioUnitEQFilterType {
            switch self {
            case .highPass: return .highPass
            case .lowShelf: return .lowShelf
            case .peak: return .parametric
            case .highShelf: return .highShelf
            case .lowPass: return .lowPass
            }
        }

        /// One accent for every filter type; the type is named in the band controls.
        var color: Color { .riffPrimary }
    }

    // 10-band frequencies: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k
    static let defaultBands: [EQBand] = [
        EQBand(id: 0, frequency: 32, gain: 0, q: 1.0, type: .lowShelf, isEnabled: true),
        EQBand(id: 1, frequency: 64, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 2, frequency: 125, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 3, frequency: 250, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 4, frequency: 500, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 5, frequency: 1000, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 6, frequency: 2000, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 7, frequency: 4000, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 8, frequency: 8000, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 9, frequency: 16000, gain: 0, q: 1.0, type: .highShelf, isEnabled: true)
    ]
}

// MARK: - EQ Presets

struct EQPreset: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let gains: [Float] // 10 values for 10 bands

    static let presets: [EQPreset] = [
        EQPreset(name: "Flat", icon: "equal", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Rock", icon: "guitars", gains: [5, 4, 3, 1, -1, 1, 3, 4, 5, 4]),
        EQPreset(name: "Pop", icon: "music.note", gains: [-2, -1, 0, 2, 4, 4, 2, 0, -1, -2]),
        EQPreset(name: "Jazz", icon: "music.quarternote.3", gains: [4, 3, 1, 2, -2, -2, 0, 1, 3, 4]),
        EQPreset(name: "Classical", icon: "waveform", gains: [5, 4, 3, 2, -1, -1, 0, 2, 3, 4]),
        EQPreset(name: "Hip-Hop", icon: "headphones", gains: [5, 5, 3, 1, -1, 0, 1, 0, 2, 3]),
        EQPreset(name: "Electronic", icon: "bolt.fill", gains: [4, 5, 3, 0, -2, 1, 3, 4, 4, 3]),
        EQPreset(name: "R&B", icon: "heart.fill", gains: [3, 6, 4, 1, -2, 0, 2, 3, 3, 2]),
        EQPreset(name: "Acoustic", icon: "guitars.fill", gains: [4, 3, 2, 1, 1, 1, 2, 3, 3, 2]),
        EQPreset(name: "Bass Boost", icon: "speaker.wave.3.fill", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Treble Boost", icon: "sparkles", gains: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6]),
        EQPreset(name: "Vocal", icon: "mic.fill", gains: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]),
        EQPreset(name: "Loudness", icon: "speaker.wave.2.fill", gains: [4, 3, 0, 0, -1, 0, -1, 0, 3, 4]),
        EQPreset(name: "Metal", icon: "flame.fill", gains: [4, 3, 0, 0, -3, 0, 0, 3, 4, 3])
    ]

    func applyTo(_ bands: inout [EQBand]) {
        for i in 0..<min(bands.count, gains.count) {
            bands[i].gain = gains[i]
        }
    }
}
