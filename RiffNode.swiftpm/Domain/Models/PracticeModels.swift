import Foundation

// MARK: - Practice Tools

/// What the looper is doing – like the single footswitch on a looper pedal.
enum LooperState: Equatable, Sendable {
    case empty
    case recording
    case playing
    case overdubbing
    case stopped

    /// What a press of the footswitch does next.
    var nextActionTitle: String {
        switch self {
        case .empty, .stopped: "Record"
        case .recording: "Play"
        case .playing: "Overdub"
        case .overdubbing: "Play"
        }
    }
}

/// A song's musical facts, found on device (iOS / macOS 27 Music Understanding).
struct SongAnalysis: Equatable, Sendable {
    /// e.g. "E minor"
    var key: String?
    var isMinor: Bool
    /// Root note name, e.g. "E"
    var tonic: String?
    var beatsPerMinute: Double?
    /// Bar start times, seconds
    var bars: [TimeInterval]
    /// Section start times (verse, chorus…), seconds
    var sections: [TimeInterval]
    /// Instruments heard: drums, bass, vocals, other
    var instruments: [String]

    /// The scale to solo with: minor pentatonic in minor keys, major pentatonic in major ones.
    var soloScale: String? {
        guard let tonic else { return nil }
        return "\(tonic) \(isMinor ? "minor" : "major") pentatonic"
    }
}

// MARK: - Sharing Tones

/// A whole tone – pedals, amp and input – as a small JSON file you can share.
struct ToneDocument: Codable, Equatable, Sendable {
    struct Pedal: Codable, Equatable, Sendable {
        var type: String
        var isEnabled: Bool
        var parameters: [String: Float]
    }
    struct Amp: Codable, Equatable, Sendable {
        var isEnabled: Bool
        var model: String
        var cabinet: String
        var gain, bass, mid, treble, master: Float
    }

    var format = "riffnode.tone"
    var version = 1
    var name: String
    var pedals: [Pedal]
    var amp: Amp
    var eqGains: [Float]

    init(name: String, chain: [EffectNode], amp: AmpSettings, eqBands: [EQBand]) {
        self.name = name
        pedals = chain.map { Pedal(type: $0.type.rawValue, isEnabled: $0.isEnabled, parameters: $0.parameters) }
        self.amp = Amp(isEnabled: amp.isEnabled, model: amp.model.rawValue,
                       cabinet: amp.cabinet == .impulse ? CabinetType.twoByTwelve.rawValue : amp.cabinet.rawValue,
                       gain: amp.gain, bass: amp.bass, mid: amp.mid, treble: amp.treble, master: amp.master)
        eqGains = eqBands.map(\.gain)
    }

    /// The pedals this document describes (unknown types are skipped).
    var effectNodes: [EffectNode] {
        pedals.compactMap { pedal in
            EffectType(rawValue: pedal.type).map { EffectNode(type: $0, isEnabled: pedal.isEnabled, parameters: pedal.parameters) }
        }
    }

    var ampSettings: AmpSettings {
        AmpSettings(isEnabled: amp.isEnabled,
                    model: AmpModel(rawValue: amp.model) ?? .clean,
                    cabinet: CabinetType(rawValue: amp.cabinet) ?? .twoByTwelve,
                    gain: amp.gain, bass: amp.bass, mid: amp.mid, treble: amp.treble, master: amp.master)
    }
}

// MARK: - Footswitch

/// What a MIDI foot controller asked for.
enum FootswitchEvent: Equatable, Sendable {
    case programChange(Int)
    case nextPreset
    case previousPreset
    case looper
    case tunerMute
}
