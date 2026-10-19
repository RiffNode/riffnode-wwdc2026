import SwiftUI

// MARK: - Glass Tab Bar

/// A tab bar using native iOS Picker for drag/slide support
struct GlassTabBar<Tab: Hashable & CaseIterable & Sendable>: View where Tab: RawRepresentable, Tab.RawValue == String {
    @Binding var selection: Tab
    var tint: Color
    let icon: (Tab) -> String

    init(
        selection: Binding<Tab>,
        tint: Color = .accentColor,
        icon: @escaping (Tab) -> String
    ) {
        self._selection = selection
        self.tint = tint
        self.icon = icon
    }

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Array(Tab.allCases), id: \.self) { tab in
                Label(tab.rawValue, systemImage: icon(tab))
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// A subtle glass divider line
struct GlassDivider: View {
    var vertical: Bool

    init(vertical: Bool = false) {
        self.vertical = vertical
    }

    var body: some View {
        if vertical {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)
        } else {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
        }
    }
}
