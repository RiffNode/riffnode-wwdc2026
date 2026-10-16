import Foundation

/// What the Demo source plays: RiffNode's original synthesized arpeggio, or a clean
/// recording the player imported themselves. Nothing is bundled – the app stays a small,
/// self-contained playground with no third-party audio.
enum DemoRiff: String, CaseIterable, Identifiable, Sendable {
    case originalArpeggio
    case recording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .originalArpeggio: "Original Arpeggio"
        case .recording: "Your Recording"
        }
    }
}
