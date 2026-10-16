import Foundation
import Synchronization

// MARK: - Input Stage
// Everything between the guitar and the first pedal:
//
//  • Pickup + cable – a guitar pickup is a big coil (≈2.5 H); every foot of cable adds
//    ≈30 pF. Together they form a resonant low-pass at f = 1/(2π√LC): a small bump, then
//    the highs roll off. Longer cable → lower corner → duller tone ("tone suck"). A buffer
//    early on the board drives the long cables, so only the guitar cable loads the pickup.
//  • Volume pedal – smoothed gain, for swells.
//  • Noise gate – an envelope follower that closes below a threshold (with hysteresis).

enum InputDesign {
    /// The pickup's resonance damping: a little peak at the corner, like a real single coil.
    static let resonanceQ: Float = 1.3

    static func response(for settings: InputSettings, at frequencies: [Float], sampleRate: Float = 48_000) -> [Float] {
        let c = Biquad.coefficients(.lowPass, frequency: settings.pickupResonanceHz, q: resonanceQ, gainDB: 0, sampleRate: sampleRate)
        return frequencies.map { Biquad.magnitudeDB(c, at: $0, sampleRate: sampleRate) }
    }
}

final class InputProcessor: @unchecked Sendable {

    private let cornerBits = Atomic<UInt32>(Float(5_000).bitPattern)
    private let volumeBits = Atomic<UInt32>(Float(1).bitPattern)
    private let gateThresholdBits = Atomic<UInt32>(Float(-54).bitPattern)
    private let gateOn = Atomic<Bool>(false)

    func apply(_ s: InputSettings) {
        cornerBits.store(s.pickupResonanceHz.bitPattern, ordering: .relaxed)
        volumeBits.store(s.volume.bitPattern, ordering: .relaxed)
        gateThresholdBits.store(s.gateThresholdDB.bitPattern, ordering: .relaxed)
        gateOn.store(s.isGateOn, ordering: .relaxed)
    }

    // Audio-thread state
    private var cable = Biquad()
    private var appliedCorner: Float = 0
    private var sampleRate: Float = 48_000
    private var smoothedVolume: Float = 1
    private var envelope: Float = 0
    private var gateGain: Float = 1
    private var gateOpen = true

    func prepare(sampleRate: Float) {
        self.sampleRate = sampleRate
        cable = Biquad()
        appliedCorner = 0
        envelope = 0
        gateGain = 1
        gateOpen = true
    }

    /// Processes one block in place (one or two channels; no allocation on the audio thread).
    func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>?, frames: Int) {
        let corner = Float(bitPattern: cornerBits.load(ordering: .relaxed))
        if corner != appliedCorner {
            cable.set(.lowPass, frequency: corner, q: InputDesign.resonanceQ, sampleRate: sampleRate)
            appliedCorner = corner
        }
        let targetVolume = Float(bitPattern: volumeBits.load(ordering: .relaxed))
        let useGate = gateOn.load(ordering: .relaxed)
        let threshold = pow(10, Float(bitPattern: gateThresholdBits.load(ordering: .relaxed)) / 20)
        let openThreshold = threshold * 1.6          // ≈4 dB hysteresis: opens louder than it closes
        let attack = 1 - exp(-1 / (0.001 * sampleRate))
        let release = 1 - exp(-1 / (0.08 * sampleRate))
        let gainGlide = 1 - exp(-1 / (0.004 * sampleRate))
        let volumeGlide = 1 - exp(-1 / (0.02 * sampleRate))

        for frame in 0..<frames {
            // Envelope of the loudest channel
            var level = abs(left[frame])
            if let right { level = max(level, abs(right[frame])) }
            envelope += (level - envelope) * (level > envelope ? attack : release)
            if useGate {
                if gateOpen && envelope < threshold { gateOpen = false }
                else if !gateOpen && envelope > openThreshold { gateOpen = true }
            } else {
                gateOpen = true
            }
            gateGain += ((gateOpen ? 1 : 0) - gateGain) * gainGlide
            smoothedVolume += (targetVolume - smoothedVolume) * volumeGlide
            let gain = gateGain * smoothedVolume

            left[frame] = cable.process(left[frame], channel: 0) * gain
            if let right { right[frame] = cable.process(right[frame], channel: 1) * gain }
        }
    }
}
