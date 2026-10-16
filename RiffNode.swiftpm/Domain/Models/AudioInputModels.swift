import Foundation

// MARK: - Audio Input Device Model

struct AudioInputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let type: AudioInputDeviceType
}

// MARK: - Audio Input Device Type

enum AudioInputDeviceType: String {
    case none = "No Input"
    case builtInMicrophone = "Built-in Mic"
    case usbAudioInterface = "USB Interface"
    case headset = "Headset"
    case bluetooth = "Bluetooth"
    case external = "External"

    var icon: String {
        switch self {
        case .none: return "mic.slash"
        case .builtInMicrophone: return "laptopcomputer"
        case .usbAudioInterface: return "cable.connector"
        case .headset: return "headphones"
        case .bluetooth: return "wave.3.right"
        case .external: return "mic"
        }
    }

}
