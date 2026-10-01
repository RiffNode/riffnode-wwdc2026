import SwiftUI
import Observation

// MARK: - Riff Notch Controller
// State machine for the Dynamic Island–style notch that hangs from the top of the window.
// Modeled on NotchDrop's closed / popping / opened states:
//  - closed:  a slim live-activity pill (engine LED, input level, current note)
//  - popping: a short-lived banner announcing an event (preset, pedal, gesture)
//  - opened:  a mini control center (tuner, meters, transport, pedal chips)

@Observable
@MainActor
final class RiffNotchController {

    enum Status: Equatable {
        case closed
        case popping
        case opened
    }

    /// Higher priority events win when several fire in the same moment
    /// (e.g. a head-nod gesture that also applies a preset).
    enum Priority: Int, Comparable {
        case chain, pedal, engine, preset, gesture

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Activity: Equatable, Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String?
        let tint: Color
        let priority: Priority
        let date = Date()
    }

    // MARK: - State

    private(set) var status: Status = .closed
    private(set) var activity: Activity?

    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /// How long a popped banner stays before the notch shrinks back.
    private let popDuration: Duration = .seconds(2.2)
    /// Window in which a lower-priority event cannot replace a higher-priority one.
    private let priorityWindow: TimeInterval = 0.6

    // MARK: - Actions

    func open() {
        dismissTask?.cancel()
        status = .opened
    }

    func close() {
        dismissTask?.cancel()
        status = .closed
        activity = nil
    }

    func toggle() {
        status == .opened ? close() : open()
    }

    /// Briefly expands the notch to show an event. Ignored while the user has it opened.
    func announce(
        icon: String,
        title: String,
        detail: String? = nil,
        tint: Color = .riffPrimary,
        priority: Priority = .chain
    ) {
        guard status != .opened else { return }

        if let current = activity,
           current.priority > priority,
           Date().timeIntervalSince(current.date) < priorityWindow {
            return
        }

        activity = Activity(icon: icon, title: title, detail: detail, tint: tint, priority: priority)
        status = .popping

        dismissTask?.cancel()
        dismissTask = Task { [weak self, popDuration] in
            try? await Task.sleep(for: popDuration)
            guard !Task.isCancelled, let self, self.status == .popping else { return }
            self.status = .closed
            self.activity = nil
        }
    }
}
