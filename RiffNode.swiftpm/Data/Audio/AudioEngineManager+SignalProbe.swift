import AVFoundation
import Foundation

// MARK: - AudioEngineManager · SignalProbe

extension AudioEngineManager {

    // MARK: - Signal Probe

    /// Starts watching the signal just before and just after one pedal.
    /// `owner` identifies the view asking: views are rebuilt when you switch pedals or a preset
    /// replaces the chain, and the old view's "stop" can arrive after the new view's "start".
    func probe(_ type: EffectType, owner: UUID) {
        probeOwner = owner
        guard type != probedEffectType else { return }
        probedEffectType = type
        installProbeTaps()
    }

    func probeSnapshot() -> (before: SignalCapture, after: SignalCapture) {
        signalProbe.snapshot()
    }

    /// Stops the probe – only if `owner` is still the view that started it.
    func stopProbe(owner: UUID) {
        guard probeOwner == owner else { return }
        probeOwner = nil
        probedEffectType = nil
        installProbeTaps()
    }

    /// Taps the node that feeds the probed pedal ("before") and the pedal itself ("after").
    /// Re-run after every rewire, since the node in front of a pedal can change.
    func installProbeTaps() {
        for node in probedNodes { node.removeTap(onBus: 0) }
        probedNodes = []
        signalProbe.reset()

        guard let type = probedEffectType,
              let units = effectUnits,
              let fxMixer = fxInputMixer,
              let order = connectedEffectOrder,
              let index = order.firstIndex(of: type),
              let after = units.audioUnit(for: type) else { return }
        let before: AVAudioNode = index == 0
            ? units.wah
            : units.audioUnit(for: order[index - 1]) ?? fxMixer

        before.installTap(onBus: 0, bufferSize: 1024, format: nil,
                          block: SignalProbeStore.tapBlock(for: signalProbe, side: .before))
        after.installTap(onBus: 0, bufferSize: 1024, format: nil,
                         block: SignalProbeStore.tapBlock(for: signalProbe, side: .after))
        probedNodes = [before, after]
    }
}
