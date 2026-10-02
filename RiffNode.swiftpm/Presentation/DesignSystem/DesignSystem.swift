import SwiftUI

// MARK: - RiffNode Design System
// Apple iOS 26+ Human Interface Guidelines Compliant
// Uses native Liquid Glass API with full optical properties:
// - .glassEffect(.regular, in: Shape()) - Standard glass effect
// - .glassEffect(.regular.tint(color), in: Shape()) - Tinted glass
// - .glassEffect(.regular.interactive(), in: Shape()) - Interactive glass elements
// - GlassEffectContainer - Liquid fusion effect when glass elements are near each other

// MARK: - Design Tokens

/// Spacing scale following Apple's 8pt grid system
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Corner radius scale for consistent rounded corners
enum CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let pill: CGFloat = 100
}

/// Monochrome palette: system surfaces, ONE accent, and colour only where it carries
/// meaning (LED on, in tune, clipping). Category colours all resolve to the accent so
/// no screen turns into a rainbow.
extension Color {
    /// The single accent (AccentColor asset – indigo, matching the logo).
    static let riffPrimary = Color.accentColor
    static let riffSecondary = Color.secondary

    /// Content background – plain system surface, follows light / dark mode.
    static let riffBackground = Color(uiColor: .systemGroupedBackground)
    /// Raised surface for cards that are not glass.
    static let riffSurface = Color(uiColor: .secondarySystemGroupedBackground)

    // Effect categories – intentionally the accent; categories are told apart by labels and icons.
    static let riffDynamics = Color.accentColor
    static let riffFilter = Color.accentColor
    static let riffGain = Color.accentColor
    static let riffModulation = Color.accentColor
    static let riffAmbience = Color.accentColor

    // Meaningful status colours
    static let riffSuccess = Color.green
    static let riffWarning = Color.orange
    static let riffError = Color.red
}

/// Typography presets following Apple's type scale with Dynamic Type support
enum Typography {
    /// Large display titles
    static func largeTitle() -> Font { .largeTitle.weight(.bold) }
    
    /// Section headers
    static func title() -> Font { .title2.weight(.semibold) }
    
    /// Card headers
    static func headline() -> Font { .headline }
    
    /// Body text
    static func body() -> Font { .body }
    
    /// Secondary text
    static func subheadline() -> Font { .subheadline }
    
    /// Small labels
    static func caption() -> Font { .caption.weight(.medium) }
    
    /// Numeric values (monospaced)
    static func mono() -> Font { .system(.body, design: .monospaced).weight(.medium) }
    
    /// Small numeric values
    static func monoSmall() -> Font { .system(.caption, design: .monospaced).weight(.semibold) }
}

// MARK: - Adaptive Background

/// Creates a vibrant dynamic background for iOS 26 Liquid Glass testing
/// High-contrast animated orbs to showcase glass lensing and refraction
struct AdaptiveBackground: View {
    var body: some View {
        Color.riffBackground.ignoresSafeArea()
    }
}

// MARK: - Glass Card Container

/// A Liquid Glass card container using native iOS 26 .glassEffect() API
/// Supports optional tinting via GlassStyle.regular.tint(color)
struct GlassCard<Content: View>: View {
    let content: Content
    var tint: Color?
    var cornerRadius: CGFloat
    var padding: CGFloat

    init(
        tint: Color? = nil,
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .glassEffect(
                tint.map { .regular.tint($0) } ?? .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
    }
}

// MARK: - Glass Button Styles
// iOS 26 provides native Liquid Glass button styles:
// - .buttonStyle(.glass) - Standard glass button with lensing effect
// - .buttonStyle(.glassProminent) - Emphasized glass button (use sparingly, for CTAs)
// For custom glass controls, use .glassEffect(.regular.interactive(), in: Shape())
// For grouped glass elements, wrap in GlassEffectContainer for liquid fusion

// MARK: - Glass Pill Button Style

/// Compact pill-shaped glass button for tabs and toggles
struct GlassPillStyle: ButtonStyle {
    var isSelected: Bool
    var tint: Color

    init(isSelected: Bool = false, tint: Color = .accentColor) {
        self.isSelected = isSelected
        self.tint = tint
    }

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(
                isSelected ? .regular.tint(tint) : .regular,
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Glass Icon Button

/// Circular glass button for icons
struct GlassIconButton: View {
    let icon: String
    var tint: Color
    var size: CGFloat
    let action: () -> Void

    init(
        icon: String,
        tint: Color = .primary,
        size: CGFloat = 44,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.tint = tint
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scale Button Style

/// Simple scale animation on press
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Native iOS 26 Slider
// In iOS 26, native Slider automatically uses Liquid Glass styling
// Example: Slider(value: $value, in: 0...1).tint(.primary)

// MARK: - Glass Knob

/// A modern glass circular knob control
struct GlassKnob: View {
    @Binding var value: Float
    var range: ClosedRange<Float>
    var tint: Color
    var label: String
    var format: String
    var size: CGFloat

    @State private var isDragging = false

    init(
        value: Binding<Float>,
        range: ClosedRange<Float> = 0...100,
        tint: Color = .accentColor,
        label: String = "",
        format: String = "%.0f",
        size: CGFloat = 60
    ) {
        self._value = value
        self.range = range
        self.tint = tint
        self.label = label
        self.format = format
        self.size = size
    }

    private var normalizedValue: Double {
        Double((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    private var rotation: Angle {
        .degrees(-135 + normalizedValue * 270)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Track arc
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        Color.primary.opacity(0.1),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: size + 8, height: size + 8)
                    .rotationEffect(.degrees(135))

                // Value arc
                Circle()
                    .trim(from: 0, to: normalizedValue * 0.75)
                    .stroke(
                        LinearGradient(
                            colors: [tint.opacity(0.6), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: size + 8, height: size + 8)
                    .rotationEffect(.degrees(135))

                // Knob body with Liquid Glass
                Circle()
                    .fill(.clear)
                    .frame(width: size, height: size)
                    .glassEffect(.regular, in: Circle())
                    .shadow(color: isDragging ? tint.opacity(0.4) : .black.opacity(0.1), radius: isDragging ? 8 : 4)

                // Indicator line
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3, height: size * 0.25)
                    .offset(y: -size * 0.28)
                    .rotationEffect(rotation)

                // Center value
                Text(String(format: format, value))
                    .font(.system(size: size * 0.2, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let delta = Float(-gesture.translation.height / 100)
                        let sensitivity: Float = (range.upperBound - range.lowerBound) * 0.01
                        let newValue = value + delta * sensitivity
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )

            if !label.isEmpty {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

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


// MARK: - Glass Status Indicator

/// A minimal glass status indicator (online/offline/loading)
struct GlassStatusIndicator: View {
    enum Status {
        case active, inactive, loading
    }

    let status: Status
    var label: String?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.3))
                    .frame(width: 10, height: 10)

                if status == .loading {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(statusColor, lineWidth: 2)
                        .frame(width: 10, height: 10)
                        .rotationEffect(.degrees(360))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: status)
                } else {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                }
            }

            if let label = label {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .active: return .green
        case .inactive: return .red
        case .loading: return .orange
        }
    }
}

// MARK: - Glass Divider

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

// MARK: - Effect Pedal Card

/// A realistic dark pedal enclosure with an LED and effect icon.
/// Only the selected-state overlay uses glass; the body itself is solid dark
/// so the pedalboard reads as hardware, not UI.
struct GlassEffectPedal: View {
    let effect: EffectNode
    var isSelected: Bool = false
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 10) {
            // LED indicator
            ZStack {
                // Outer glow when enabled
                Circle()
                    .fill(effect.isEnabled ? Color.green.opacity(0.35) : .clear)
                    .frame(width: 18, height: 18)
                    .blur(radius: 5)

                // LED dot
                Circle()
                    .fill(effect.isEnabled ? Color.green : Color(white: 0.35))
                    .frame(width: 10, height: 10)
                    .shadow(color: effect.isEnabled ? .green.opacity(0.9) : .clear, radius: 5)
            }

            // Effect icon
            Image(systemName: effect.type.icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(effect.isEnabled ? effect.type.color : Color(white: 0.55))

            // Abbreviation label
            Text(effect.type.abbreviation)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(effect.isEnabled ? .white : Color(white: 0.6))

            // Full name – very subtle
            Text(effect.type.rawValue)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(white: 0.4))
                .lineLimit(1)
        }
        .frame(width: 88, height: 118)
        // Dark pedal enclosure body
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.17), Color(white: 0.11)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        // Metallic edge – subtle rim highlight on top, dark on bottom
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(white: 0.35),          // top highlight
                            Color(white: 0.18),          // sides
                            Color(white: 0.08)           // bottom shadow
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
        )
        // Selected state: a glass-coloured ring around the pedal
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(effect.type.color, lineWidth: 2.5)
                    .shadow(color: effect.type.color.opacity(0.45), radius: 6)
            }
        }
        // Subtle drop shadow so pedals "sit" on the board
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        // Delete badge on hover
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .red)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(duration: 0.2), value: isHovering)
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(effect.type.rawValue) pedal, \(effect.isEnabled ? "enabled" : "bypassed")")
        .accessibilityHint("Tap to select, double-tap to toggle")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Conditional Glass Modifier

/// A view modifier that conditionally applies a glass effect
struct ConditionalGlassModifier<S: Shape>: ViewModifier {
    let isEnabled: Bool
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.glassEffect(.regular, in: shape)
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply glass card styling with Liquid Glass
    func glassCard(tint: Color? = nil, cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .glassEffect(
                tint.map { .regular.tint($0) } ?? .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
    }

    /// Apply glass pill styling with Liquid Glass
    func glassPill() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
    }
}

// MARK: - Native iOS 26 Button Styles
// Use native button styles for action buttons:
// - .buttonStyle(.glass) - Liquid Glass button
// - .buttonStyle(.glassProminent) - Emphasized Liquid Glass button
// - .buttonStyle(.borderedProminent) - Solid action button

// MARK: - Segment Slider

/// A Liquid Glass segmented slider using native iOS Picker
/// In iOS 26, Picker automatically uses Liquid Glass styling with drag support
struct GlassSegmentSlider<T: Hashable & CaseIterable, Content: View>: View where T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    let options: T.AllCases
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                content(option)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}


// MARK: - Preview

#Preview("Design System Components") {
    ZStack {
        AdaptiveBackground()

        ScrollView {
            VStack(spacing: 24) {
                // Glass Card
                GlassCard(tint: Color.riffPrimary) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Glass Card")
                            .font(.headline)
                        Text("Liquid Glass container with lensing and refraction")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Native iOS 26 Glass Buttons
                HStack(spacing: 16) {
                    Button("Glass") {}
                        .buttonStyle(.glass)

                    Button("Prominent") {}
                        .buttonStyle(.glassProminent)

                    GlassIconButton(icon: "gear", tint: .primary) {}
                }

                // Tab Pills
                HStack(spacing: 8) {
                    Button("Selected") {}
                        .buttonStyle(GlassPillStyle(isSelected: true, tint: Color.riffPrimary))

                    Button("Unselected") {}
                        .buttonStyle(GlassPillStyle(isSelected: false))
                }

                // Status Indicators
                HStack(spacing: 16) {
                    GlassStatusIndicator(status: .active, label: "Running")
                    GlassStatusIndicator(status: .inactive, label: "Stopped")
                }

                // Knobs
                HStack(spacing: 32) {
                    GlassKnob(
                        value: .constant(75),
                        tint: Color.riffPrimary,
                        label: "GAIN"
                    )

                    GlassKnob(
                        value: .constant(50),
                        tint: .orange,
                        label: "TONE"
                    )
                }

                // Native iOS 26 Slider
                Slider(value: .constant(0.7), in: 0...1)
                    .tint(.green)
                    .padding(.horizontal)
            }
            .padding()
        }
    }
}
