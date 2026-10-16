import Foundation

// MARK: - Amp & Cabinet
// Every real pedalboard plays into an amplifier and a speaker cabinet, and they shape the
// sound as much as any pedal: the preamp adds warmth and grit, the tone stack sets the
// EQ, and the speaker rolls off the harsh fizz above about 5 kHz that makes digital
// distortion sound "fake". RiffNode puts an amp at the end of the chain, like a real rig.

struct AmpSettings: Equatable, Sendable {
    var isEnabled = true
    var model: AmpModel = .clean
    var cabinet: CabinetType = .twoByTwelve
    /// 0…1 for every knob, like the panel of a real amp.
    var gain: Float = 0.35
    var bass: Float = 0.5
    var mid: Float = 0.5
    var treble: Float = 0.55
    var master: Float = 0.5
}

/// Three classic amp voicings – described by how they behave, not by brand.
enum AmpModel: String, CaseIterable, Identifiable, Sendable {
    /// American clean: lots of headroom, scooped mids, sparkly highs
    case clean = "Clean"
    /// British crunch: breaks up early, pushy upper mids
    case crunch = "Crunch"
    /// Modern high gain: tight lows, heavy saturation
    case lead = "Lead"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .clean: "Lots of headroom and sparkle – pedals sound like themselves."
        case .crunch: "Breaks up as you dig in, with pushy upper mids."
        case .lead: "Tight lows and thick saturation for solos and riffs."
        }
    }
}

/// The speaker cabinet – the biggest single difference between "direct" and "real".
enum CabinetType: String, CaseIterable, Identifiable, Sendable {
    /// No speaker: what a pedal sounds like straight into a mixer (harsh, fizzy)
    case direct = "Direct"
    /// Open-back 1×12: airy, light low end
    case oneByTwelve = "1×12"
    /// Open 2×12: balanced
    case twoByTwelve = "2×12"
    /// Closed 4×12: big thump, rolled-off top
    case fourByTwelve = "4×12"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .direct: "No speaker – hear how harsh raw distortion is."
        case .oneByTwelve: "Open-back combo: airy, light lows."
        case .twoByTwelve: "Balanced, the classic combo amp."
        case .fourByTwelve: "Closed stack: deep thump, smooth top."
        }
    }
}

// MARK: - Pedal Order

/// A placement on the pedalboard that real players would avoid – and why.
struct PedalOrderIssue: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
}

/// Checks a chain against the order most guitarists use – dynamics, then drive, then
/// modulation, then time effects – and explains what each misplacement does to the sound.
enum PedalOrderAdvisor {

    static func issues(for chain: [EffectType]) -> [PedalOrderIssue] {
        var issues: [PedalOrderIssue] = []
        func index(_ type: EffectType) -> Int? { chain.firstIndex(of: type) }
        let drives: [EffectType] = [.overdrive, .distortion, .fuzz]
        let firstDrive = drives.compactMap(index).min()
        let lastDrive = drives.compactMap(index).max()

        for time in [EffectType.delay, .reverb] {
            if let t = index(time), let d = lastDrive, t < d {
                issues.append(PedalOrderIssue(
                    id: "\(time.rawValue)-before-drive",
                    title: "\(time.rawValue) before drive",
                    detail: "The echoes and tails get distorted too, so every note smears into a muddy wash. Time effects usually go last."))
            }
        }
        if let r = index(.reverb), let d = index(.delay), r < d {
            issues.append(PedalOrderIssue(
                id: "reverb-before-delay",
                title: "Reverb before Delay",
                detail: "Each echo repeats the whole reverb tail, which blurs quickly. Delay into reverb sounds like echoes in a room."))
        }
        for mod in [EffectType.chorus, .phaser, .flanger, .tremolo] {
            if let m = index(mod), let d = lastDrive, m < d {
                issues.append(PedalOrderIssue(
                    id: "\(mod.rawValue)-before-drive",
                    title: "\(mod.rawValue) before drive",
                    detail: mod == .tremolo
                        ? "The drive pedal flattens the volume pulses, so the tremolo almost disappears."
                        : "The drive squashes the sweep into a harsher, less obvious movement. Most boards put modulation after drive."))
            }
        }
        if let c = index(.compressor), let d = firstDrive, c > d {
            issues.append(PedalOrderIssue(
                id: "compressor-after-drive",
                title: "Compressor after drive",
                detail: "It squeezes the drive's noise and hiss up along with the notes. Before the drive, it evens out your picking instead."))
        }
        if let f = index(.fuzz), f > 0, chain[..<f].contains(where: { $0 != .equalizer }) {
            issues.append(PedalOrderIssue(
                id: "fuzz-not-first",
                title: "Fuzz isn't first",
                detail: "Vintage fuzz circuits react to the guitar's pickups directly; after other pedals they lose their warmth. Players put fuzz first."))
        }
        return issues
    }

    /// The chain sorted into the usual order, keeping each pedal's settings.
    static func standardOrder<T>(_ chain: [T], type: (T) -> EffectType) -> [T] {
        chain.sorted { type($0).recommendedOrder < type($1).recommendedOrder }
    }
}
