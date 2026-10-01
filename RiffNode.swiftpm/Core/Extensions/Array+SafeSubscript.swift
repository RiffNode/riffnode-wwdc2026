import SwiftUI
import Observation

// MARK: - Array Safe Subscript Extension

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
