import os

// MARK: - Logging
// Unified logging instead of print: debug messages cost nothing in a release build and can
// be filtered by category in Console.app.

enum Log {
    static let audio = Logger(subsystem: "com.yujia.RiffNode", category: "audio")
    static let analysis = Logger(subsystem: "com.yujia.RiffNode", category: "analysis")
    static let vision = Logger(subsystem: "com.yujia.RiffNode", category: "vision")
}
