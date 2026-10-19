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
        /// The pedal model (absent in files from before models existed).
        var model: String?
    }
    struct Amp: Codable, Equatable, Sendable {
        var isEnabled: Bool
        var model: String
        var cabinet: String
        var gain, bass, mid, treble, master: Float
    }
    /// The cable, buffer and noise gate in front of the board. The volume pedal is left out:
    /// it's played, not set.
    struct Input: Codable, Equatable, Sendable {
        var cableFeet: Float
        var isBuffered: Bool
        var isGateOn: Bool
        var gateThresholdDB: Float
    }

    var format = "riffnode.tone"
    var version = 1
    var name: String
    var pedals: [Pedal]
    var amp: Amp
    var eqGains: [Float]
    /// Absent in files from before the input stage was saved.
    var input: Input?

    init(name: String, chain: [EffectNode], amp: AmpSettings, eqBands: [EQBand], input: InputSettings? = nil) {
        self.name = name
        self.input = input.map { Input(cableFeet: $0.cableFeet, isBuffered: $0.isBuffered,
                                       isGateOn: $0.isGateOn, gateThresholdDB: $0.gateThresholdDB) }
        pedals = chain.map { Pedal(type: $0.type.rawValue, isEnabled: $0.isEnabled, parameters: $0.parameters, model: $0.modelID) }
        self.amp = Amp(isEnabled: amp.isEnabled, model: amp.model.rawValue,
                       cabinet: amp.cabinet == .impulse ? CabinetType.twoByTwelve.rawValue : amp.cabinet.rawValue,
                       gain: amp.gain, bass: amp.bass, mid: amp.mid, treble: amp.treble, master: amp.master)
        eqGains = eqBands.map(\.gain)
    }

    /// The pedals this document describes (unknown types are skipped).
    var effectNodes: [EffectNode] {
        pedals.compactMap { pedal in
            EffectType(rawValue: pedal.type).map { EffectNode(type: $0, isEnabled: pedal.isEnabled, parameters: pedal.parameters, modelID: pedal.model) }
        }
    }

    var ampSettings: AmpSettings {
        AmpSettings(isEnabled: amp.isEnabled,
                    model: AmpModel(legacy: amp.model) ?? .twain,
                    cabinet: CabinetType(rawValue: amp.cabinet) ?? .twoByTwelve,
                    gain: amp.gain, bass: amp.bass, mid: amp.mid, treble: amp.treble, master: amp.master)
    }

    /// These input settings with the saved cable, buffer and gate laid over them
    /// (unchanged when the document has none).
    func inputSettings(over current: InputSettings) -> InputSettings {
        guard let input else { return current }
        var settings = current
        settings.cableFeet = max(3, min(60, input.cableFeet))
        settings.isBuffered = input.isBuffered
        settings.isGateOn = input.isGateOn
        settings.gateThresholdDB = max(-80, min(-30, input.gateThresholdDB))
        return settings
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
