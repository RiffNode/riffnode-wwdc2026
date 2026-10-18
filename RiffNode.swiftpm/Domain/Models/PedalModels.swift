import Foundation

// MARK: - Pedal Models
// Twenty classic stompboxes, voiced after how their circuits work. Every name and every
// enclosure here is RiffNode's own: the colours and shapes nod to the originals, but there
// are no logos, trade names or copied graphics. `inspiredBy` names the original only to
// describe the sound (all trademarks belong to their owners; RiffNode is not affiliated).

struct PedalModel: Identifiable, Equatable, Sendable {
    let id: String
    /// RiffNode's own name, printed on the pedal.
    let name: String
    /// The classic circuit this one is voiced after – for the Learn text, never on the pedal.
    let inspiredBy: String
    let year: Int
    let type: EffectType
    let look: PedalLook
    let voicing: PedalVoicing
    /// How the original circuit makes its sound, in plain words.
    let about: String
    /// Starting knob positions; nil keeps the effect type's defaults.
    var defaultParameters: [String: Float]? = nil
}

// MARK: - Look

struct PedalLook: Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        /// Tall die-cast box with a wide rectangular footswitch along the bottom.
        case slantSwitch
        /// Compact box whose lower half is a ribbed treadle plate.
        case treadlePlate
        /// Small box, one or two knobs and a round metal footswitch.
        case mini
        /// Wide, flat sheet-metal box with three knobs in a row.
        case wide
        /// A round dome, knobs on top.
        case dome
        /// The Pedalboard's original stompbox.
        case classic
    }
    enum Knob: Equatable, Sendable { case black, cream, chrome, red }

    let shape: Shape
    /// Enclosure paint, 0xRRGGBB.
    let body: UInt32
    /// Lettering and graphics, 0xRRGGBB.
    let ink: UInt32
    let knob: Knob
    /// The labels printed under the knobs, left to right.
    let knobLabels: [String]
}

// MARK: - Voicing

/// What the DSP needs to sound like the circuit. Only the fields of a pedal's own
/// family are used.
enum PedalVoicing: Equatable, Sendable {
    case drive(Drive)
    case modulation(Modulation)
    case echo(Echo)
    /// Uses the effect type's own processing (compressor, reverb, EQ).
    case standard

    struct Drive: Equatable, Sendable {
        enum Clipping: Int, Sendable {
            /// Diodes in the op-amp's feedback loop: smooth, compressed (Tube Screamer)
            case softFeedback
            /// Diodes to ground after high gain: flat-topped, buzzy (RAT, DS-1)
            case hardToGround
            /// Two transistors, different headroom on each half (Fuzz Face)
            case asymmetricFuzz
            /// MOSFET-style: soft knee that keeps more dynamics (OCD)
            case mosfet
            /// Germanium diodes to ground: low threshold, soft (Klon, Distortion+)
            case germanium
            /// Two clipping stages in a row: thick, endless sustain (Big Muff)
            case cascaded
            /// Asymmetric diodes in the feedback loop: fuller even harmonics (SD-1)
            case asymmetricSoft
        }
        enum Tone: Int, Sendable {
            /// A low-pass that opens with the knob
            case lowPass
            /// A low-pass and a high-pass blended – scoops the mids in the middle (Big Muff, DS-1)
            case midScoop
            /// No tone knob: a fixed low-pass (Distortion+)
            case fixed
        }
        var gainDB: ClosedRange<Float>
        /// Bass below this is kept out of the clipper.
        var preHighPassHz: Float
        var clipping: Clipping
        /// How much clean signal is mixed back in (1 = Tube Screamer, ~0.7 = Klon).
        var cleanBlend: Float = 0
        var tone: Tone = .lowPass
        var toneRangeHz: ClosedRange<Float> = 1_200...9_000
        /// Output level trim to keep pedals roughly level-matched.
        var outputTrim: Float = 1
    }

    struct Modulation: Equatable, Sendable {
        /// Chorus / flanger: shortest delay and how far the LFO sweeps it, in ms.
        var baseDelayMs: Float = 12
        var sweepMs: Float = 12
        /// Phaser: all-pass stages (≤ 6), lowest notch and sweep width in decades.
        var stages: Int = 6
        var sweepLowHz: Float = 300
        var sweepDecades: Float = 1
        /// Phaser: spreads the stages apart, like the mismatched photocells of a vibe.
        var stageSpread: Float = 1
        /// 0 = smooth sine LFO … 1 = choppy, square-ish (tremolo) or throbbing (vibe).
        var shape: Float = 0
    }

    struct Echo: Equatable, Sendable {
        /// Each repeat is low-passed here (0 = clean digital repeats).
        var darkenHz: Float
        /// Tape / BBD wobble depth in ms (0 = rock steady).
        var wowMs: Float
        /// 0 = clean repeats … 1 = saturated, warm repeats.
        var saturation: Float
    }
}

// MARK: - Catalog

extension PedalModel {

    static let all: [PedalModel] = [
        // ── Overdrive ──────────────────────────────────────────────────────
        PedalModel(
            id: "tube-steamer", name: "Tube Steamer", inspiredBy: "Ibanez TS808 Tube Screamer", year: 1979,
            type: .overdrive,
            look: PedalLook(shape: .slantSwitch, body: 0x2E8B57, ink: 0xF2F2E6, knob: .black, knobLabels: ["DRIVE", "TONE", "LEVEL"]),
            voicing: .drive(.init(gainDB: 21.5...41.5, preHighPassHz: 720, clipping: .softFeedback, cleanBlend: 1,
                                  toneRangeHz: 1_200...9_000)),
            about: "An op-amp with two diodes in its feedback loop, boosting only what's above ~720 Hz. The clean signal passes alongside, so the bass stays tight and the mids hump forward – the reason it's the classic push for a tube amp."
        ),
        PedalModel(
            id: "blue-diver", name: "Blue Diver", inspiredBy: "Boss BD-2 Blues Driver", year: 1995,
            type: .overdrive,
            look: PedalLook(shape: .treadlePlate, body: 0x1F5FBF, ink: 0xFFFFFF, knob: .black, knobLabels: ["LEVEL", "TONE", "GAIN"]),
            voicing: .drive(.init(gainDB: 12...44, preHighPassHz: 160, clipping: .asymmetricSoft,
                                  toneRangeHz: 1_800...11_000, outputTrim: 0.9)),
            about: "Discrete op-amp stages that clip on both sides unevenly, with a much lower bass cut than a Tube Screamer – a wide, transparent drive that cleans up with your picking like a small amp."
        ),
        PedalModel(
            id: "copper-pegasus", name: "Copper Pegasus", inspiredBy: "Klon Centaur", year: 1994,
            type: .overdrive,
            look: PedalLook(shape: .slantSwitch, body: 0xB8733D, ink: 0x2B1A0E, knob: .cream, knobLabels: ["GAIN", "TREBLE", "OUTPUT"]),
            voicing: .drive(.init(gainDB: 8...36, preHighPassHz: 400, clipping: .germanium, cleanBlend: 0.7,
                                  toneRangeHz: 2_000...10_000, outputTrim: 1.2)),
            about: "A clean path and a germanium-clipped path mixed together, with lots of headroom from an internal voltage doubler. Low settings are a transparent boost; turned up, the clipped side takes over."
        ),
        PedalModel(
            id: "compulsive-drive", name: "Compulsive Drive", inspiredBy: "Fulltone OCD", year: 2004,
            type: .overdrive,
            look: PedalLook(shape: .mini, body: 0xEFE9DC, ink: 0x1C1C1C, knob: .chrome, knobLabels: ["VOLUME", "DRIVE", "TONE"]),
            voicing: .drive(.init(gainDB: 14...48, preHighPassHz: 220, clipping: .mosfet,
                                  toneRangeHz: 1_500...8_000)),
            about: "MOSFET clipping instead of diodes: a softer, amp-like knee that keeps the attack of each note – from a light crunch to a near-distortion."
        ),
        PedalModel(
            id: "sunny-drive", name: "Sunny Drive", inspiredBy: "Boss SD-1 Super OverDrive", year: 1981,
            type: .overdrive,
            look: PedalLook(shape: .treadlePlate, body: 0xF2C230, ink: 0x1C1C1C, knob: .black, knobLabels: ["LEVEL", "TONE", "DRIVE"]),
            voicing: .drive(.init(gainDB: 20...42, preHighPassHz: 720, clipping: .asymmetricSoft, cleanBlend: 1,
                                  toneRangeHz: 1_400...9_500)),
            about: "A Tube Screamer cousin with three diodes instead of two – one side clips later than the other, adding even harmonics for a slightly brighter, fuller grind."
        ),
        // ── Distortion ─────────────────────────────────────────────────────
        PedalModel(
            id: "the-mouse", name: "The Mouse", inspiredBy: "ProCo RAT", year: 1978,
            type: .distortion,
            look: PedalLook(shape: .wide, body: 0x1B1B1B, ink: 0xF2F2F2, knob: .black, knobLabels: ["DISTORTION", "FILTER", "VOLUME"]),
            voicing: .drive(.init(gainDB: 6...60, preHighPassHz: 60, clipping: .hardToGround, toneRangeHz: 1_200...9_000)),
            about: "Up to ~60 dB from a slow vintage op-amp, then diodes to ground clip the wave flat. The 'filter' is a low-pass that works backwards: turning it up makes it darker."
        ),
        PedalModel(
            id: "dirt-station", name: "Dirt Station", inspiredBy: "Boss DS-1 Distortion", year: 1978,
            type: .distortion,
            look: PedalLook(shape: .treadlePlate, body: 0xF07A1A, ink: 0x1C1C1C, knob: .black, knobLabels: ["TONE", "LEVEL", "DIST"]),
            voicing: .drive(.init(gainDB: 18...52, preHighPassHz: 100, clipping: .hardToGround, tone: .midScoop,
                                  toneRangeHz: 500...1_800, outputTrim: 1.1)),
            about: "A transistor booster into an op-amp, hard-clipped by diodes to ground, then a passive tone control that blends a low-pass and a high-pass – which carves a dip in the mids."
        ),
        PedalModel(
            id: "plus-sign", name: "Plus Sign", inspiredBy: "MXR Distortion+", year: 1973,
            type: .distortion,
            look: PedalLook(shape: .mini, body: 0xF4D03F, ink: 0x1C1C1C, knob: .black, knobLabels: ["OUTPUT", "DIST"]),
            voicing: .drive(.init(gainDB: 6...46, preHighPassHz: 300, clipping: .germanium, tone: .fixed,
                                  toneRangeHz: 4_500...4_500, outputTrim: 1.3)),
            about: "One op-amp stage and two germanium diodes to ground, with no tone knob at all – a raw, vintage crunch that sits between overdrive and distortion."
        ),
        PedalModel(
            id: "heavy-mettle", name: "Heavy Mettle", inspiredBy: "Boss HM-2 Heavy Metal", year: 1983,
            type: .distortion,
            look: PedalLook(shape: .treadlePlate, body: 0x232323, ink: 0xF07A1A, knob: .black, knobLabels: ["LEVEL", "LOW", "HIGH", "DIST"]),
            voicing: .drive(.init(gainDB: 24...58, preHighPassHz: 40, clipping: .cascaded, tone: .midScoop,
                                  toneRangeHz: 300...2_200, outputTrim: 0.9)),
            about: "Two gain stages and an EQ that boosts the lows and highs around a scooped middle – the 'chainsaw' sound of Swedish death metal when everything is turned up."
        ),
        // ── Fuzz ───────────────────────────────────────────────────────────
        PedalModel(
            id: "fuzz-grin", name: "Fuzz Grin", inspiredBy: "Arbiter Fuzz Face", year: 1966,
            type: .fuzz,
            look: PedalLook(shape: .dome, body: 0xC8102E, ink: 0xF2F2F2, knob: .black, knobLabels: ["VOLUME", "FUZZ"]),
            voicing: .drive(.init(gainDB: 20...54, preHighPassHz: 20, clipping: .asymmetricFuzz, toneRangeHz: 2_500...9_000)),
            about: "Just two transistors, four resistors and three capacitors. The halves of the wave clip differently, and it cleans up when you turn the guitar down."
        ),
        PedalModel(
            id: "big-fluff", name: "Big Fluff", inspiredBy: "Electro-Harmonix Big Muff Pi", year: 1969,
            type: .fuzz,
            look: PedalLook(shape: .wide, body: 0xE9E7E2, ink: 0xC8102E, knob: .black, knobLabels: ["VOLUME", "TONE", "SUSTAIN"]),
            voicing: .drive(.init(gainDB: 24...56, preHighPassHz: 80, clipping: .cascaded, tone: .midScoop,
                                  toneRangeHz: 400...1_200, outputTrim: 1.1)),
            about: "Two clipping stages in a row give endless sustain; the tone knob blends a low-pass and a high-pass, scooping the mids into a huge, smooth wall of fuzz."
        ),
        // ── Dynamics ───────────────────────────────────────────────────────
        PedalModel(
            id: "dino-comp", name: "Dino Comp", inspiredBy: "MXR Dyna Comp", year: 1972,
            type: .compressor,
            look: PedalLook(shape: .mini, body: 0xC8102E, ink: 0xF2F2F2, knob: .black, knobLabels: ["OUTPUT", "SENSITIVITY"]),
            voicing: .standard,
            about: "A transconductance-amplifier compressor with a fast attack that squashes each pick and lets the note bloom – the 'chicken pickin' country squish.",
            defaultParameters: ["threshold": -30, "ratio": 8, "attack": 2, "release": 150]
        ),
        // ── Modulation ─────────────────────────────────────────────────────
        PedalModel(
            id: "cloud-ensemble", name: "Cloud Ensemble", inspiredBy: "Boss CE-2 Chorus", year: 1979,
            type: .chorus,
            look: PedalLook(shape: .treadlePlate, body: 0x7CC4E8, ink: 0x1C1C1C, knob: .black, knobLabels: ["RATE", "DEPTH"]),
            voicing: .modulation(.init(baseDelayMs: 4, sweepMs: 6)),
            about: "A bucket-brigade chip delays a copy by a few milliseconds and an LFO wobbles that delay, so the copy drifts slightly in pitch – the shimmer of 80s clean guitars."
        ),
        PedalModel(
            id: "orange-ninety", name: "Orange Ninety", inspiredBy: "MXR Phase 90", year: 1974,
            type: .phaser,
            look: PedalLook(shape: .mini, body: 0xF26B1D, ink: 0x1C1C1C, knob: .black, knobLabels: ["SPEED"]),
            voicing: .modulation(.init(stages: 4, sweepLowHz: 200, sweepDecades: 1.2)),
            about: "Four all-pass stages swept by one LFO, with a touch of feedback – two notches that glide through the spectrum. One knob: speed."
        ),
        PedalModel(
            id: "uni-wave", name: "Uni-Wave", inspiredBy: "Shin-ei Uni-Vibe", year: 1968,
            type: .phaser,
            look: PedalLook(shape: .wide, body: 0x3B4A3F, ink: 0xE8E2C8, knob: .chrome, knobLabels: ["VOLUME", "INTENSITY", "SPEED"]),
            voicing: .modulation(.init(stages: 4, sweepLowHz: 120, sweepDecades: 1.1, stageSpread: 2.2, shape: 0.6)),
            about: "Built to imitate a rotating speaker: four phase stages driven by a lamp and mismatched photocells, so the notches are spread unevenly and the sweep throbs."
        ),
        PedalModel(
            id: "electric-mystery", name: "Electric Mystery", inspiredBy: "Electro-Harmonix Electric Mistress", year: 1976,
            type: .flanger,
            look: PedalLook(shape: .wide, body: 0xC9CDD2, ink: 0x1F3A93, knob: .black, knobLabels: ["RATE", "RANGE", "COLOR"]),
            voicing: .modulation(.init(baseDelayMs: 0.5, sweepMs: 6)),
            about: "A very short bucket-brigade delay swept slowly, with feedback for the 'color' – the jet-plane whoosh, gentle enough to sound like a chorus at low settings."
        ),
        PedalModel(
            id: "tremor-two", name: "Tremor Two", inspiredBy: "Boss TR-2 Tremolo", year: 1997,
            type: .tremolo,
            look: PedalLook(shape: .treadlePlate, body: 0x2E5E3E, ink: 0xF2F2F2, knob: .black, knobLabels: ["RATE", "DEPTH"]),
            voicing: .modulation(.init(shape: 0.35)),
            about: "An LFO turns the volume up and down; a wave control moves it from a smooth sine to a choppy square, like the bias tremolo of vintage amps."
        ),
        // ── Time & Ambience ────────────────────────────────────────────────
        PedalModel(
            id: "carbon-paper", name: "Carbon Paper", inspiredBy: "MXR Carbon Copy", year: 2008,
            type: .delay,
            look: PedalLook(shape: .mini, body: 0x2F6F5E, ink: 0xF2F2F2, knob: .chrome, knobLabels: ["REGEN", "MIX", "DELAY"]),
            voicing: .echo(.init(darkenHz: 2_400, wowMs: 0.9, saturation: 1)),
            about: "Bucket-brigade analog delay: each repeat passes through a low-pass and gentle saturation, so echoes get darker and warmer as they fade."
        ),
        PedalModel(
            id: "digital-dee", name: "Digital Dee", inspiredBy: "Boss DD-3 Digital Delay", year: 1986,
            type: .delay,
            look: PedalLook(shape: .treadlePlate, body: 0xF2F2F2, ink: 0x1C1C1C, knob: .black, knobLabels: ["LEVEL", "FEEDBACK", "TIME"]),
            voicing: .echo(.init(darkenHz: 0, wowMs: 0, saturation: 0)),
            about: "A digital delay: every repeat is an exact copy, rock steady and bright – the clean slapbacks and rhythmic echoes of 80s and 90s rock."
        ),
        PedalModel(
            id: "holy-pail", name: "Holy Pail", inspiredBy: "Electro-Harmonix Holy Grail", year: 2003,
            type: .reverb,
            look: PedalLook(shape: .mini, body: 0xBFC4C9, ink: 0xB22222, knob: .black, knobLabels: ["REVERB"]),
            voicing: .standard,
            about: "A digital reverb in a small box – one knob for how much room you hear, from a little air to a big hall."
        ),
    ]

    /// The model a new pedal of this type starts as.
    static func standard(for type: EffectType) -> PedalModel? {
        all.first { $0.type == type }
    }

    /// The models a pedal of this type can be. Gain pedals share one processor, so any of
    /// the three drive slots can hold any drive – two overdrives stacked, like on real boards.
    static func models(for type: EffectType) -> [PedalModel] {
        all.filter { $0.fits(type) }
    }

    /// True when this model can sit in a slot of the given type.
    func fits(_ slot: EffectType) -> Bool {
        type == slot || (type.category == .gainDirt && slot.category == .gainDirt)
    }

    static func model(id: String?) -> PedalModel? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
