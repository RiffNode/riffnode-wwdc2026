import AVFoundation
import Foundation

// MARK: - Audio Input Device Detection Extension

extension AudioEngineManager {

    /// Detect and update available audio input devices
    /// This method is safe to call from MainActor - updates properties directly
    func detectAudioInputDevices() {
        #if os(macOS)
        let result = AudioEngineManager.collectMacOSInputDevices()
        #else
        let result = AudioEngineManager.collectIOSInputDevices()
        #endif

        // Update properties directly (we're on MainActor)
        self.availableInputDevices = result.devices
        self.currentInputDeviceName = result.currentName
        self.currentInputDeviceType = result.currentType

        Log.audio.debug("detectAudioInputDevices: \(result.devices.count) devices, current \(result.currentName, privacy: .public)")
    }

    // MARK: - Static Device Collection (Thread-Safe, No Self Capture)

    /// Result type for device detection - avoids any self capture
    private struct DeviceDetectionResult {
        let devices: [AudioInputDevice]
        let currentName: String
        let currentType: AudioInputDeviceType
    }

    #if os(macOS)
    /// Static function to collect macOS input devices - no MainActor dependency
    private static func collectMacOSInputDevices() -> DeviceDetectionResult {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        var devices: [AudioInputDevice] = []

        for device in discoverySession.devices {
            let deviceType = classifyInputDeviceStatic(name: device.localizedName)
            devices.append(AudioInputDevice(
                id: device.uniqueID,
                name: device.localizedName,
                type: deviceType
            ))
        }

        let currentName: String
        let currentType: AudioInputDeviceType

        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            currentName = defaultDevice.localizedName
            currentType = classifyInputDeviceStatic(name: defaultDevice.localizedName)
        } else if let firstDevice = devices.first {
            currentName = firstDevice.name
            currentType = firstDevice.type
        } else {
            currentName = "No Input"
            currentType = .none
        }

        return DeviceDetectionResult(devices: devices, currentName: currentName, currentType: currentType)
    }
    #endif

    #if os(iOS) || targetEnvironment(macCatalyst)
    /// Static function to collect iOS input devices - no MainActor dependency
    private static func collectIOSInputDevices() -> DeviceDetectionResult {
        let session = AVAudioSession.sharedInstance()
        var devices: [AudioInputDevice] = []

        if let availableInputs = session.availableInputs {
            for input in availableInputs {
                let deviceType = classifyIOSPortStatic(portType: input.portType)
                devices.append(AudioInputDevice(
                    id: input.uid,
                    name: input.portName,
                    type: deviceType
                ))
            }
        }

        let currentName: String
        let currentType: AudioInputDeviceType

        if let currentInput = session.currentRoute.inputs.first {
            currentName = currentInput.portName
            currentType = classifyIOSPortStatic(portType: currentInput.portType)
        } else if let firstDevice = devices.first {
            currentName = firstDevice.name
            currentType = firstDevice.type
        } else {
            currentName = "No Input"
            currentType = .none
        }

        return DeviceDetectionResult(devices: devices, currentName: currentName, currentType: currentType)
    }

    /// Static port classification - no self dependency
    private static func classifyIOSPortStatic(portType: AVAudioSession.Port) -> AudioInputDeviceType {
        switch portType {
        case .builtInMic:
            return .builtInMicrophone
        case .headsetMic:
            return .headset
        case .usbAudio:
            return .usbAudioInterface
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            return .bluetooth
        default:
            return .external
        }
    }
    #endif

    /// Static device classification - no self dependency
    private static func classifyInputDeviceStatic(name: String) -> AudioInputDeviceType {
        let lowercaseName = name.lowercased()

        // USB Audio Interfaces
        if lowercaseName.contains("scarlett") ||
           lowercaseName.contains("focusrite") ||
           lowercaseName.contains("steinberg") ||
           lowercaseName.contains("presonus") ||
           lowercaseName.contains("behringer") ||
           lowercaseName.contains("motu") ||
           lowercaseName.contains("apogee") ||
           lowercaseName.contains("universal audio") ||
           lowercaseName.contains("usb audio") ||
           lowercaseName.contains("audio interface") {
            return .usbAudioInterface
        }

        // Built-in microphone
        if lowercaseName.contains("built-in") ||
           lowercaseName.contains("internal") ||
           lowercaseName.contains("macbook") ||
           lowercaseName.contains("imac") {
            return .builtInMicrophone
        }

        // Headsets
        if lowercaseName.contains("headset") ||
           lowercaseName.contains("airpods") ||
           lowercaseName.contains("earbuds") {
            return .headset
        }

        // Bluetooth
        if lowercaseName.contains("bluetooth") {
            return .bluetooth
        }

        return .external
    }

    /// Refresh input device list
    func refreshInputDevices() {
        detectAudioInputDevices()
    }
}
