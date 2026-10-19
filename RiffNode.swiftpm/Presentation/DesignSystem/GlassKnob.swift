import SwiftUI

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
    @State private var dragStartValue: Float?

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
                        if dragStartValue == nil { dragStartValue = value }
                        let delta = Float(-gesture.translation.height / 200)
                        let newValue = (dragStartValue ?? value) + delta * (range.upperBound - range.lowerBound)
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragStartValue = nil
                    }
            )

            if !label.isEmpty {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "Parameter" : label)
        .accessibilityValue(String(format: format, value))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 100
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}
