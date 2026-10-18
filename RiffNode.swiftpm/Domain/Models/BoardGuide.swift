import Foundation

// MARK: - Build a Board
// What goes into a real pedalboard besides the pedals: the cable, the tuner, a buffer,
// the order, the patch cables, the power and the amp. Each stop is short – one idea,
// a few facts and something to try – so it can be learned by poking at it.

struct BoardGuideStop: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case cable, tuner, buffer, order, patch, power, amp
    }
    let id: ID
    let title: String
    let icon: String
    /// The one idea, in a sentence.
    let headline: String
    /// Two to four short facts.
    let points: [String]
    /// What to try in RiffNode.
    let tryIt: String
}

extension BoardGuideStop {
    static let all: [BoardGuideStop] = [
        BoardGuideStop(
            id: .cable, title: "Guitar & Cable", icon: "cable.connector",
            headline: "The cable is part of the circuit: the longer it is, the darker the guitar sounds.",
            points: [
                "A pickup is a coil (≈ 2.5 H); every foot of cable adds about 30 pF. Together they make a low-pass filter: f = 1 / 2π√LC.",
                "3 ft lets through everything up to ~7 kHz; 60 ft starts cutting at ~2.3 kHz – the 'tone suck' of long runs.",
                "Only the cable before the first buffer counts: after it, the signal drives cable easily.",
            ],
            tryIt: "Drag the length below and watch the cutoff fall."
        ),
        BoardGuideStop(
            id: .tuner, title: "Tuner", icon: "tuningfork",
            headline: "The tuner goes first, where it hears the plain guitar.",
            points: [
                "Before any drive or modulation, the pitch is cleanest and easiest to read.",
                "Most tuner pedals mute the output while they're on, so you can tune silently between songs.",
                "Some players run it from a volume pedal's tuner output instead, so it never leaves the signal path.",
            ],
            tryIt: "In Stage Mode the tuner is the first pedal: stomp it to mute and tune."
        ),
        BoardGuideStop(
            id: .buffer, title: "Buffer", icon: "bolt.horizontal",
            headline: "A buffer turns the pickup's weak, high-impedance signal into one that drives long cables.",
            points: [
                "True-bypass pedals, when off, are just wire – so a board full of them adds every patch cable to the guitar cable.",
                "One good buffer near the start fixes it; very large boards often add a second near the end.",
                "Fuzz pedals like to see the pickup directly, so they usually go before the buffer.",
            ],
            tryIt: "On the Pedalboard, tap GUITAR and switch the buffer on with a long cable."
        ),
        BoardGuideStop(
            id: .order, title: "Pedal Order", icon: "arrow.right.arrow.left",
            headline: "Order changes the sound: each pedal processes everything before it.",
            points: [
                "A common start: tuner → dynamics & wah → drive (fuzz first) → modulation → delay → reverb.",
                "Drive before delay keeps the echoes clean; delay before drive smears the repeats into the distortion.",
                "Compressor before drive evens your picking; after it, it lifts the drive's noise too.",
                "These are starting points, not rules – plenty of great tones break them.",
            ],
            tryIt: "Drag pedals on the Pedalboard – RiffNode explains any unusual order."
        ),
        BoardGuideStop(
            id: .patch, title: "Patch Cables", icon: "point.topleft.down.to.point.bottomright.curvepath",
            headline: "Short, well-made patch cables between pedals – right-angle plugs save space.",
            points: [
                "Every patch cable adds capacitance; ten short ones can add up to another few feet of cable.",
                "Pedals take their input on the right and send it out on the left, so boards are wired right to left.",
                "Most crackles on a board are a tired patch cable or plug – they're the first thing to check.",
            ],
            tryIt: "Stage Mode wires the board like this: guitar in on the right, amp out on the left."
        ),
        BoardGuideStop(
            id: .power, title: "Power", icon: "powerplug",
            headline: "Isolated outputs keep the board quiet; check each pedal's voltage, polarity and current.",
            points: [
                "Most pedals take 9 V DC with a centre-negative plug – but some want 12 V or 18 V, or centre-positive. Check before plugging in.",
                "Analog pedals draw little (often under 20 mA); digital ones need 100–500 mA. Each output must supply at least what its pedal draws.",
                "A daisy chain shares one ground between pedals, which can loop and hum – especially with digital pedals. Isolated outputs give each pedal its own.",
            ],
            tryIt: "Below: how much current your board draws, and what a ground loop sounds like."
        ),
        BoardGuideStop(
            id: .amp, title: "Amp & Loop", icon: "hifispeaker",
            headline: "The amp is the last 'pedal' – and where its gain comes from decides where time effects go.",
            points: [
                "With a clean amp, everything can go in front of it.",
                "If the amp's own preamp distorts, delay and reverb sound clearer in its effects loop, after the distortion.",
                "Fender and Vox tone controls sit before the tubes clip; Marshall's come after the preamp – try both amps with the same pedals.",
            ],
            tryIt: "On the Pedalboard, tap the amp to switch between the classic heads."
        ),
    ]
}

// MARK: - Current Draw

extension PedalModel {
    /// Roughly what the original draws at 9 V, in mA – a typical figure, not a spec;
    /// always check the label on the pedal itself.
    var typicalCurrentMA: Int {
        switch id {
        case "tube-steamer", "compulsive-drive": 8
        case "blue-diver", "sunny-drive", "dirt-station", "cloud-ensemble": 20
        case "copper-pegasus": 30
        case "the-mouse", "plus-sign", "fuzz-grin", "big-fluff", "dino-comp", "orange-ninety": 5
        case "heavy-mettle", "tremor-two": 15
        case "uni-wave": 60
        case "electric-mystery", "carbon-paper": 30
        case "digital-dee": 50
        case "holy-pail": 100
        default: 20
        }
    }

    /// Analog circuits draw little current; digital ones (DSP) draw a lot more.
    var isDigital: Bool { id == "digital-dee" || id == "holy-pail" }
}
