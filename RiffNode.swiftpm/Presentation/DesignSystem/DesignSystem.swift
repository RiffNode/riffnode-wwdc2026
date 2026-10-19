import SwiftUI

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

/// Semantic colors following Apple HIG - uses system colors that adapt to appearance
extension Color {
    // MARK: - Brand Colors (Muted, Professional)
    
    /// Primary brand color - used for main actions and highlights
    static let riffPrimary = Color.indigo
    
    /// Secondary accent for subtle highlights
    static let riffSecondary = Color.teal
    
    // MARK: - Effect Category Colors (Muted Palette)
    
    /// Dynamics effects (Compressor) - calm blue
    static let riffDynamics = Color(red: 0.35, green: 0.55, blue: 0.75)
    
    /// Filter/EQ effects - warm amber
    static let riffFilter = Color(red: 0.75, green: 0.6, blue: 0.35)
    
    /// Gain/Dirt effects - earthy orange
    static let riffGain = Color(red: 0.8, green: 0.5, blue: 0.35)
    
    /// Modulation effects - cool teal
    static let riffModulation = Color(red: 0.35, green: 0.65, blue: 0.6)
    
    /// Time/Ambience effects - soft purple
    static let riffAmbience = Color(red: 0.55, green: 0.45, blue: 0.7)
    
    // MARK: - Semantic Colors
    
    /// Success/active state
    static let riffSuccess = Color.green
    
    /// Warning/caution state
    static let riffWarning = Color.orange
    
    /// Error/danger state
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
