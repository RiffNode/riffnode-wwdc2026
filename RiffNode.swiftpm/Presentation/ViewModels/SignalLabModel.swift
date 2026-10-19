import Foundation
import Observation

// MARK: - Signal Lab Model
// Holds what the Signal Lab draws for the probed pedal. The analysis itself (alignment, FFT,
// measurements) happens in the Data layer; this view model keeps the latest frame and smooths
// the numbers so they're legible.

@Observable
@MainActor
final class SignalLabModel {
    typealias Measurements = SignalMeasurements

    private(set) var waveBefore: [Float] = []
    private(set) var waveAfter: [Float] = []
    private(set) var envelopeBefore: [Float] = []
    private(set) var envelopeAfter: [Float] = []
    private(set) var spectrumBefore: [Float] = []
    private(set) var spectrumAfter: [Float] = []
    private(set) var measurements = Measurements()
    /// True when nothing is coming into the pedal.
    private(set) var isSilent = true

    static let spectrumBands = SignalAnalysis.spectrumBands
    static let spectrumRange = SignalAnalysis.spectrumRange
    static let waveLength = SignalAnalysis.waveLength

    func update(from analysis: SignalAnalysis) {
        isSilent = analysis.isSilent
        guard !analysis.isSilent, !analysis.waveBefore.isEmpty else { return }
        waveBefore = analysis.waveBefore
        waveAfter = analysis.waveAfter
        envelopeBefore = analysis.envelopeBefore
        envelopeAfter = analysis.envelopeAfter
        spectrumBefore = analysis.spectrumBefore
        spectrumAfter = analysis.spectrumAfter
        // Smooth the readouts so they're legible (jump straight there the first time)
        measurements = measurements.blended(toward: analysis.measurements,
                                            amount: measurements.levelBefore < -100 ? 1 : 0.25)
    }

    func clear() {
        waveBefore = []; waveAfter = []
        envelopeBefore = []; envelopeAfter = []
        spectrumBefore = []; spectrumAfter = []
        measurements = Measurements()
        isSilent = true
    }
}
