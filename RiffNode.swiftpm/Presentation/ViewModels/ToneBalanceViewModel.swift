import Foundation
import Observation

// MARK: - Tone Balance View Model
// Decides which part of the spectrum your sound sits in – held steady with hysteresis so the
// advice doesn't flicker between neighbouring ranges – and applies the suggested EQ move.

@Observable
@MainActor
final class ToneBalanceViewModel {

    let engine: any ToneBalanceEngine
    let analyzer: any SpectrumProviding

    private(set) var region: FrequencyRegion?
    /// The region whose suggestion was just applied (the button shows "Applied").
    private(set) var appliedRegion: FrequencyRegion?
    @ObservationIgnored private var candidate: (region: FrequencyRegion, since: Date)?

    init(engine: any ToneBalanceEngine, analyzer: any SpectrumProviding) {
        self.engine = engine
        self.analyzer = analyzer
    }

    var isHearingSound: Bool { engine.inputLevel > 0.002 }
    var canOfferDemo: Bool { engine.canPlayDemoRiff && !engine.isDemoRiffPlaying }

    func playDemo() { engine.startDemoRiff() }

    func applySuggestion() {
        guard let region else { return }
        engine.applyToneSuggestion(region.suggestion)
        appliedRegion = region
    }

    /// Call when the spectrum updates. Switches only when another region is clearly louder
    /// (+0.03) for at least 0.6 s.
    func spectrumDidUpdate() {
        guard isHearingSound else {
            setRegion(nil)
            candidate = nil
            return
        }
        guard let loudest = FrequencyRegion.dominant(in: analyzer) else { return }
        guard let current = region else {
            setRegion(loudest)
            return
        }
        guard loudest != current,
              loudest.level(in: analyzer) > current.level(in: analyzer) + 0.03 else {
            candidate = nil
            return
        }
        if let candidate, candidate.region == loudest {
            if Date().timeIntervalSince(candidate.since) > 0.6 {
                setRegion(loudest)
                self.candidate = nil
            }
        } else {
            candidate = (loudest, Date())
        }
    }

    private func setRegion(_ newRegion: FrequencyRegion?) {
        guard newRegion != region else { return }
        region = newRegion
        appliedRegion = nil
    }
}
