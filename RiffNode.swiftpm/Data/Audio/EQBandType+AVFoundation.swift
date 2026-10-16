import AVFoundation

// MARK: - EQ Band → AVAudioUnitEQ
// Maps the domain's filter types onto AVFoundation's. Lives in Data, next to the audio engine.

extension EQBand.BandType {
    var audioUnitFilterType: AVAudioUnitEQFilterType {
        switch self {
        case .highPass: return .highPass
        case .lowShelf: return .lowShelf
        case .peak: return .parametric
        case .highShelf: return .highShelf
        case .lowPass: return .lowPass
        }
    }
}
