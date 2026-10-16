import CoreMIDI
import Foundation
import Observation

// MARK: - MIDI Footswitch
// Listens to every connected MIDI source – USB foot controllers, or Bluetooth pedals once
// paired – and turns the usual messages into pedalboard actions:
//
//  • Program Change n → preset n
//  • CC 80 / CC 81 (value ≥ 64) → next / previous preset
//  • CC 82 → the looper's footswitch
//  • CC 83 → mute while tuning
//
// CoreMIDI is local hardware I/O – it works fully offline.

@Observable
@MainActor
final class MIDIFootswitch: FootswitchListening {

    private(set) var sourceNames: [String] = []
    private(set) var lastMessage: String?
    /// Called on the main actor for every recognised message.
    @ObservationIgnored var onEvent: (@MainActor (FootswitchEvent) -> Void)?

    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var port = MIDIPortRef()
    @ObservationIgnored private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let status = MIDIClientCreateWithBlock("RiffNode" as CFString, &client) { [weak self] _ in
            // A device was plugged in or paired: reconnect everything
            Task { @MainActor in self?.connectSources() }
        }
        guard status == noErr else { return }
        MIDIInputPortCreateWithProtocol(client, "RiffNode Input" as CFString, ._1_0, &port) { [weak self] list, _ in
            let events = MIDIFootswitch.parse(list)
            guard !events.isEmpty else { return }
            Task { @MainActor in
                for (event, description) in events {
                    self?.lastMessage = description
                    self?.onEvent?(event)
                }
            }
        }
        connectSources()
    }

    private func connectSources() {
        var names: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            MIDIPortConnectSource(port, source, nil)
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name) == noErr, let name {
                names.append(name.takeRetainedValue() as String)
            }
        }
        sourceNames = names
    }

    /// Universal MIDI Packets, MIDI 1.0 channel voice messages (message type 0x2).
    nonisolated private static func parse(_ list: UnsafePointer<MIDIEventList>) -> [(FootswitchEvent, String)] {
        var results: [(FootswitchEvent, String)] = []
        for packet in list.unsafeSequence() {
            let words = MIDIEventPacket.WordCollection(packet)
            for word in words where (word >> 28) == 0x2 {
                let status = UInt8((word >> 16) & 0xF0)
                let data1 = Int((word >> 8) & 0x7F)
                let data2 = Int(word & 0x7F)
                switch status {
                case 0xC0:
                    results.append((.programChange(data1), "Program Change \(data1)"))
                case 0xB0 where data2 >= 64:
                    switch data1 {
                    case 80: results.append((.nextPreset, "CC 80 – next preset"))
                    case 81: results.append((.previousPreset, "CC 81 – previous preset"))
                    case 82: results.append((.looper, "CC 82 – looper"))
                    case 83: results.append((.tunerMute, "CC 83 – mute"))
                    default: break
                    }
                default:
                    break
                }
            }
        }
        return results
    }
}
