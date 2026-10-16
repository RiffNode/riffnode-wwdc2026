import Foundation

/// A shared display scale. Engine levels remain unclipped linear RMS values.
enum AudioMeter {
    static func decibels(_ rms: Float) -> Float {
        guard rms.isFinite else { return -120 }
        return 20 * log10(max(rms, 1e-6))
    }

    static func normalized(_ rms: Float) -> Float {
        min(1, max(0, (decibels(rms) + 60) / 60))
    }
}
