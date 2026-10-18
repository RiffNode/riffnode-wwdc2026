import Foundation

// MARK: - Amp & Cabinet
// Every real pedalboard plays into an amplifier and a speaker cabinet, and they shape the
// sound as much as any pedal: the preamp adds warmth and grit, the tone stack sets the
// EQ, and the speaker rolls off the harsh fizz above about 5 kHz that makes digital
// distortion sound "fake". RiffNode puts an amp at the end of the chain, like a real rig.

struct AmpSettings: Equatable, Sendable {
    var isEnabled = true
    var model: AmpModel = .twain
    var cabinet: CabinetType = .twoByTwelve
    /// 0…1 for every knob, like the panel of a real amp.
    var gain: Float = 0.35
    var bass: Float = 0.5
    var mid: Float = 0.5
    var treble: Float = 0.55
    var master: Float = 0.5
}

/// Classic amps, voiced after how their circuits behave. The names and panels are
/// RiffNode's own – no logos or copied graphics; `inspiredBy` names the original only to
/// describe the sound (all trademarks belong to their owners; no affiliation).
enum AmpModel: String, CaseIterable, Identifiable, Sendable {
    /// American blackface clean
    case twain = "Twain '65"
    /// American tweed
    case tweedle = "Tweedle '59"
    /// British class-A chime
    case topBoost = "Top Boost 30"
    /// British plexi-panel crunch
    case plexus = "Plexus 100"
    /// British master-volume rock
    case brit800 = "Brit 800"
    /// Modern high gain
    case modern = "Modern Lead"
    /// A Neural Amp Modeler capture: a neural network trained on a real amp
    case captured = "NAM"

    var id: String { rawValue }

    /// Tone files saved before the classic amps existed used three generic voicings.
    init?(legacy name: String) {
        switch name {
        case "Clean": self = .twain
        case "Crunch": self = .plexus
        case "Lead": self = .modern
        default: self.init(rawValue: name)
        }
    }

    var inspiredBy: String {
        switch self {
        case .twain: "Fender Twin Reverb (blackface)"
        case .tweedle: "Fender Bassman 5F6-A (tweed)"
        case .topBoost: "Vox AC30 Top Boost"
        case .plexus: "Marshall 1959 Super Lead (plexi)"
        case .brit800: "Marshall JCM800 2203"
        case .modern: "modern high-gain heads"
        case .captured: "any amp, captured by Neural Amp Modeler"
        }
    }

    var summary: String {
        switch self {
        case .twain: "Huge headroom, scooped mids, sparkly highs – pedals sound like themselves."
        case .tweedle: "Fat and mid-forward; breaks up early and sags when you dig in."
        case .topBoost: "Chimey class-A upper mids that compress sweetly as they crunch."
        case .plexus: "Bright, punchy crunch that roars as the gain goes up."
        case .brit800: "Cascaded preamp: the tight, aggressive rock rhythm of the 80s."
        case .modern: "Tight lows and thick saturation for solos and riffs."
        case .captured: "A neural network trained on recordings of a real amp (.nam capture)."
        }
    }

    /// How the circuit sounds, in plain words – for the Learn text.
    var about: String {
        switch self {
        case .twain: "Its tone controls sit before the tubes clip and scoop the mids around 400 Hz; a bright capacitor adds sparkle at low volume. It stays clean very loud."
        case .tweedle: "Two low-gain triode stages and a tone stack with less scoop than later amps: thick mids, a loose low end and early, singing breakup."
        case .topBoost: "No negative feedback and class-A power tubes: chimey upper mids around 1–2 kHz and a soft compression when pushed."
        case .plexus: "A tweed-style circuit with a hotter first tube; the tone stack comes after the preamp clips, so the mids push forward through the grit."
        case .brit800: "Three gain stages in a row and a master volume – the birth of high gain: tight, upper-mid aggression."
        case .modern: "Even more gain stages and a deep cut below the guitar's lowest notes, so palm mutes stay tight."
        case .captured: "A WaveNet trained on the real amp's input and output – it learns the whole circuit."
        }
    }

    var voice: AmpVoice {
        switch self {
        case .twain:
            AmpVoice(preampGainDB: 0...16, midHz: 420, midBiasDB: -5, midQ: 0.7, toneStackFirst: true,
                     tightHz: 40, brightDB: 4, defaultCabinet: .twoByTwelve,
                     look: AmpLook(style: .blackPanel, tolex: 0x161616, panel: 0x1C1C1C, grille: 0xB9BCC0, ink: 0xF2F2F2))
        case .tweedle:
            AmpVoice(preampGainDB: 8...34, midHz: 700, midBiasDB: 2, midQ: 0.6, toneStackFirst: false,
                     tightHz: 50, brightDB: 0, defaultCabinet: .oneByTwelve,
                     look: AmpLook(style: .tweed, tolex: 0xC9A66B, panel: 0x9C7A44, grille: 0x6B4A2B, ink: 0x2B1A0E))
        case .topBoost:
            AmpVoice(preampGainDB: 6...30, midHz: 1_400, midBiasDB: 3, midQ: 0.8, toneStackFirst: true,
                     tightHz: 80, brightDB: 2, defaultCabinet: .twoByTwelve,
                     look: AmpLook(style: .copperPanel, tolex: 0x1A1A1A, panel: 0x8C5A2B, grille: 0x5B2A1E, ink: 0xF2E6D0))
        case .plexus:
            AmpVoice(preampGainDB: 12...38, midHz: 650, midBiasDB: 3, midQ: 0.8, toneStackFirst: false,
                     tightHz: 90, brightDB: 1, defaultCabinet: .fourByTwelve,
                     look: AmpLook(style: .goldPanel, tolex: 0x141414, panel: 0xC9A646, grille: 0x3A3326, ink: 0x1A1A1A))
        case .brit800:
            AmpVoice(preampGainDB: 18...46, midHz: 750, midBiasDB: 4, midQ: 0.9, toneStackFirst: false,
                     tightHz: 120, brightDB: 0, defaultCabinet: .fourByTwelve,
                     look: AmpLook(style: .goldPanel, tolex: 0x101010, panel: 0xB8A15A, grille: 0x2A2A2A, ink: 0x101010))
        case .modern, .captured:
            AmpVoice(preampGainDB: 20...50, midHz: 650, midBiasDB: -2, midQ: 0.8, toneStackFirst: false,
                     tightHz: 160, brightDB: 0, defaultCabinet: .fourByTwelve,
                     look: AmpLook(style: .modern, tolex: 0x121212, panel: 0x2B2D30, grille: 0x1E1E1E, ink: 0xD0D4D8))
        }
    }
}

/// How an amp's circuit is voiced, for the DSP and the response plot.
struct AmpVoice: Equatable, Sendable {
    var preampGainDB: ClosedRange<Float>
    /// Where the mid knob works, and the circuit's own mid push (+) or scoop (−).
    var midHz: Float
    var midBiasDB: Float
    var midQ: Float
    /// Fender and Vox tone stacks sit before the tubes clip; Marshall's after the preamp.
    var toneStackFirst: Bool
    /// Bass cut before the preamp, so palm mutes stay tight.
    var tightHz: Float
    /// A bright capacitor's treble lift, strongest at low gain.
    var brightDB: Float
    var defaultCabinet: CabinetType
    var look: AmpLook
}

/// The amp's panel, drawn without logos.
struct AmpLook: Equatable, Sendable {
    enum Style: Equatable, Sendable { case blackPanel, tweed, copperPanel, goldPanel, modern }
    let style: Style
    /// 0xRRGGBB
    let tolex: UInt32
    let panel: UInt32
    let grille: UInt32
    let ink: UInt32
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
    /// A measured impulse response loaded from a file – a real speaker and microphone
    case impulse = "IR"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .direct: "No speaker – hear how harsh raw distortion is."
        case .oneByTwelve: "Open-back combo: airy, light lows."
        case .twoByTwelve: "Balanced, the classic combo amp."
        case .fourByTwelve: "Closed stack: deep thump, smooth top."
        case .impulse: "Your own impulse response: a real cabinet, measured with a microphone."
        }
    }
}

// MARK: - Input Stage
// What happens before the first pedal: the guitar's pickup and the cable form a filter,
// a buffer can protect the highs, a volume pedal swells, and a noise gate cuts hiss.

struct InputSettings: Equatable, Sendable {
    /// Total cable length from guitar to amp, in feet.
    var cableFeet: Float = 18
    /// A buffer at the start of the board drives the long cables, so only the guitar cable loads the pickup.
    var isBuffered = false
    /// Volume pedal position, 0…1.
    var volume: Float = 1
    var isGateOn = false
    /// Gate threshold in dBFS.
    var gateThresholdDB: Float = -54

    /// Cable capacitance per foot, picofarads (typical instrument cable)
    static let picofaradsPerFoot: Float = 30
    /// A buffer sits after the guitar cable; everything after it no longer loads the pickup.
    static let guitarCableFeet: Float = 10

    /// The cable the pickup actually "sees".
    var loadingFeet: Float { isBuffered ? min(cableFeet, Self.guitarCableFeet) : cableFeet }

    /// Resonant frequency of a single-coil pickup (≈2.5 H, 100 pF) with this cable, in Hz:
    /// f = 1 / (2π √(L·C)). Above it, highs roll off.
    var pickupResonanceHz: Float {
        let inductance: Float = 2.5
        let capacitance = (100 + loadingFeet * Self.picofaradsPerFoot) * 1e-12
        return 1 / (2 * Float.pi * (inductance * capacitance).squareRoot())
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
