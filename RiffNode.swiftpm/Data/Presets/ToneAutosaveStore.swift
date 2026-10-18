import Foundation

// MARK: - Tone Autosave Store
// The board you were playing, saved as a small tone file in the app's own folder, so the
// next launch starts where you left off.

struct ToneAutosaveStore: ToneStoring {
    private var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RiffNode", isDirectory: true)
            .appendingPathComponent("current-board.json")
    }

    func load() -> ToneDocument? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ToneDocument.self, from: data)
    }

    func save(_ document: ToneDocument) {
        guard let url, let data = try? JSONEncoder().encode(document) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
