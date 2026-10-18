import Foundation

// MARK: - Face Gestures

/// A head or face movement the camera recognises, for hands-free control while playing.
enum FaceGesture: String, CaseIterable, Sendable {
    case headNodDown = "Nod Down"
    case headNodUp = "Nod Up"
    case headTiltLeft = "Tilt Left"
    case headTiltRight = "Tilt Right"
    case mouthOpen = "Mouth Open"
    case eyebrowRaise = "Eyebrow Raise"

    var icon: String {
        switch self {
        case .headNodDown: "arrow.down"
        case .headNodUp: "arrow.up"
        case .headTiltLeft: "arrow.left"
        case .headTiltRight: "arrow.right"
        case .mouthOpen: "mouth.fill"
        case .eyebrowRaise: "eyebrow"
        }
    }

    var defaultAction: String {
        switch self {
        case .headNodDown: "Next Preset"
        case .headNodUp: "Previous Preset"
        case .headTiltLeft: "Bypass All"
        case .headTiltRight: "Enable All"
        case .mouthOpen: "Wah Effect"
        case .eyebrowRaise: "Toggle Compressor"
        }
    }
}

// MARK: - Tone Assistant

/// Who answered a Tone Assistant request.
enum ToneResponder: Equatable, Sendable {
    case appleIntelligence
    case offlineMatcher
}

/// One step of what the assistant is doing, shown while it works.
struct AssistantThinkingStep: Identifiable, Equatable, Sendable {
    let id: String
    var text: String
    var isDone: Bool
}

// MARK: - Music Apps

/// The music apps Play Along can hand off to.
enum MusicApp: Sendable {
    case appleMusic
    case spotify

    var url: URL {
        switch self {
        case .appleMusic: URL(string: "music://")!
        case .spotify: URL(string: "spotify://")!
        }
    }
}
