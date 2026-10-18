import Foundation
import Observation

// MARK: - Board History
// Undo and redo for the whole board – pedals, their order and models, every knob, the amp
// and the EQ – plus autosave. Changes are recorded once they settle, so dragging a knob
// is one step, not a hundred.

@Observable
@MainActor
final class BoardHistory {
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private var undoStack: [ToneDocument] = []
    @ObservationIgnored private var redoStack: [ToneDocument] = []
    @ObservationIgnored private var current: ToneDocument?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private let store: any ToneStoring
    @ObservationIgnored private weak var board: (any ToneSharing)?

    static let depth = 50
    static let settleDelay: Duration = .milliseconds(600)

    init(store: any ToneStoring, board: any ToneSharing) {
        self.store = store
        self.board = board
    }

    /// Puts back the board saved last time, if there is one. Call once at launch.
    func restoreSavedBoard() {
        guard let saved = store.load() else { return }
        apply(saved)
    }

    /// The board as it is now. Recorded as one step once it stops changing.
    func record(_ document: ToneDocument) {
        guard !isApplying else { current = document; return }
        guard current != nil else { current = document; return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            self.commit(document)
        }
    }

    func undo() {
        flushPending()
        guard let previous = undoStack.popLast(), let current else { return }
        redoStack.append(current)
        apply(previous)
    }

    func redo() {
        flushPending()
        guard let next = redoStack.popLast(), let current else { return }
        undoStack.append(current)
        apply(next)
    }

    // MARK: Private

    private func commit(_ document: ToneDocument) {
        guard let current, current != document else { return }
        undoStack.append(current)
        if undoStack.count > Self.depth { undoStack.removeFirst() }
        redoStack.removeAll()
        self.current = document
        store.save(document)
        updateFlags()
    }

    /// A change still waiting to settle becomes its own step before undo/redo moves.
    private func flushPending() {
        pending?.cancel()
        pending = nil
        if let board {
            let now = board.makeToneDocument(named: "Current")
            commit(now)
        }
    }

    private func apply(_ document: ToneDocument) {
        isApplying = true
        board?.applyToneDocument(document)
        current = board?.makeToneDocument(named: "Current") ?? document
        isApplying = false
        store.save(document)
        updateFlags()
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
