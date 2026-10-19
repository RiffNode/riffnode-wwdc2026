import AVFoundation
import Foundation

// MARK: - AudioEngineManager · Sharing

extension AudioEngineManager {

    // MARK: - Tone Sharing

    func makeToneDocument(named name: String) -> ToneDocument {
        ToneDocument(name: name, chain: effectsChain, amp: ampSettings, eqBands: parametricEQBands,
                     input: inputSettings)
    }

    func applyToneDocument(_ document: ToneDocument) {
        let nodes = document.effectNodes
        guard !nodes.isEmpty else { return }
        effectsChain = nodes
        var amp = document.ampSettings
        if amp.cabinet == .impulse && cabinetIRName == nil { amp.cabinet = .twoByTwelve }
        ampSettings = amp
        var bands = parametricEQBands
        for (index, gain) in document.eqGains.enumerated() where bands.indices.contains(index) {
            bands[index].gain = max(-24, min(24, gain))
        }
        parametricEQBands = bands
        inputSettings = document.inputSettings(over: inputSettings)
        rebuildEffectsChain()
    }
}
