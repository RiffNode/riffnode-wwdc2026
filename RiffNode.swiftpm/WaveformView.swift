import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Visualization Views
// Liquid Glass UI Design - iOS 26+

// MARK: - Liquid Waveform View (High-Performance Canvas)

struct WaveformView: View {
    let samples: [Float]
    var color: Color = .cyan
    var showMirror: Bool = true
    
    // Calculate max amplitude for dynamic coloring
    private var amplitude: Float {
        samples.max() ?? 0
    }
    
    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            
            let midY = size.height / 2
            let width = size.width
            let step = width / CGFloat(max(samples.count - 1, 1))
            
            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))
            
            // Draw smooth curve using Bezier (Liquid feel)
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * step
                let y = midY - (CGFloat(sample) * (size.height / 2))
                
                if index == 0 {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    let prevX = CGFloat(index - 1) * step
                    let prevSample = samples[index - 1]
                    let prevY = midY - (CGFloat(prevSample) * (size.height / 2))
                    
                    // Control points for smooth Bezier
                    let ctrl1 = CGPoint(x: (prevX + x) / 2, y: prevY)
                    let ctrl2 = CGPoint(x: (prevX + x) / 2, y: y)
                    
                    path.addCurve(to: CGPoint(x: x, y: y), control1: ctrl1, control2: ctrl2)
                }
            }
            
            // Mirror path for bottom half
            var fullPath = path
            var bottomPath = Path()
            bottomPath.move(to: CGPoint(x: width, y: midY))
            
            // Reverse loop for bottom mirror
            for index in (0..<samples.count).reversed() {
                let x = CGFloat(index) * step
                let y = midY + (CGFloat(samples[index]) * (size.height / 2))
                
                if index == samples.count - 1 {
                    bottomPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    let nextX = CGFloat(index + 1) * step
                    let nextSample = samples[index + 1]
                    let nextY = midY + (CGFloat(nextSample) * (size.height / 2))
                    
                    let ctrl1 = CGPoint(x: (nextX + x) / 2, y: nextY)
                    let ctrl2 = CGPoint(x: (nextX + x) / 2, y: y)
                    
                    bottomPath.addCurve(to: CGPoint(x: x, y: y), control1: ctrl1, control2: ctrl2)
                }
            }
            fullPath.addPath(bottomPath)
            fullPath.closeSubpath()
            
            // Dark glass fill with gradient
            context.fill(
                fullPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(white: 0.2, opacity: 0.4),
                        Color(white: 0.3, opacity: 0.7),
                        Color(white: 0.2, opacity: 0.4)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            // Edge glow stroke - darker, more visible
            context.stroke(
                fullPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(white: 0.4, opacity: 0.6),
                        Color(white: 0.6, opacity: 1.0),
                        Color(white: 0.4, opacity: 0.6)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: width, y: 0)
                ),
                lineWidth: 2
            )

            // Center line - subtle
            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: midY))
            centerLine.addLine(to: CGPoint(x: width, y: midY))
            context.stroke(centerLine, with: .color(Color(white: 0.5, opacity: 0.2)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}

// MARK: - Pro Level Meter View (Peak Hold)

struct LevelMeterView: View {
    let level: Float
    var label: String = "Level"
    var color: Color = .white  // Neutral default
    
    // Peak hold state
    @State private var peakLevel: CGFloat = 0
    
    private var normalizedLevel: CGFloat {
        CGFloat(min(max(level * 3, 0), 1))
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
            
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Glass Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.1))
                    
                    // Active Level (Pure neutral white gradient)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.4), location: 0.0),
                                    .init(color: .white.opacity(0.7), location: 0.6),
                                    .init(color: .white.opacity(0.9), location: 1.0)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: geo.size.height * normalizedLevel)
                        .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: normalizedLevel)
                    
                    // Peak Hold Indicator (Ghost line)
                    if peakLevel > 0.01 {
                        Rectangle()
                            .fill(.white.opacity(0.9))
                            .frame(height: 2)
                            .offset(y: -geo.size.height * peakLevel + 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    
                    // Subtle segment markers
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { _ in
                            Spacer()
                            Rectangle()
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 1)
                        }
                    }
                    
                    // Clip indicator
                    if normalizedLevel > 0.95 {
                        VStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                                .frame(height: 3)
                                .shadow(color: .white.opacity(0.6), radius: 4)
                            Spacer()
                        }
                    }
                }
                .onChange(of: normalizedLevel) { oldValue, newValue in
                    updatePeak(newLevel: newValue)
                }
            }
            .frame(width: 14) // Thinner, more elegant
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 4))
            
            // dB label
            Text(String(format: "%.0f", 20 * log10(max(level, 0.001))))
                .font(.system(size: 8, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
    
    private func updatePeak(newLevel: CGFloat) {
        if newLevel > peakLevel {
            // Immediate push up
            withAnimation(.easeOut(duration: 0.05)) {
                peakLevel = newLevel
            }
        } else {
            // Slow decay after a hold
            withAnimation(.linear(duration: 1.5).delay(0.3)) {
                peakLevel = newLevel
            }
        }
    }
}

// MARK: - Audio Visualization Panel

struct AudioVisualizationPanel: View {
    @Bindable var engine: AudioEngineManager
    @State private var visualizationMode: VisualizationMode = .waveform

    enum VisualizationMode: String, CaseIterable {
        case waveform = "Waveform"
        case bars = "Bars"
        case circular = "Circular"

        var icon: String {
            switch self {
            case .waveform: return "waveform"
            case .bars: return "chart.bar.fill"
            case .circular: return "circle.hexagongrid.fill"
            }
        }
    }

    var body: some View {
        GlassCard(cornerRadius: 16) {
            VStack(spacing: 12) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundStyle(.secondary)
                        Text("Visualizer")
                            .font(.headline)
                    }

                    Spacer()

                    // Glass segment slider for mode selection
                    GlassSegmentSlider(
                        selection: $visualizationMode,
                        options: VisualizationMode.allCases
                    ) { mode in
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(width: 120)
                }

                // Visualization content
                HStack(spacing: 12) {
                    // Input level meter
                    LevelMeterView(level: engine.inputLevel, label: "IN")

                    // Main visualization
                    ZStack {
                        // Subtle dark glass background for visualization area
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(0.15))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            }

                        // Visualization
                        Group {
                            switch visualizationMode {
                            case .waveform:
                                WaveformView(samples: engine.waveformSamples)
                                    .padding(8)
                            case .bars:
                                BarVisualizationView(samples: engine.waveformSamples)
                            case .circular:
                                CircularVisualizationView(samples: engine.waveformSamples)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }

                    // Output level meter
                    LevelMeterView(level: engine.outputLevel, label: "OUT")
                }
                .frame(height: 140)
            }
        }
    }
    
    // Haptic feedback for mode switching
    private func triggerHaptic() {
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #endif
    }
}

// MARK: - Bar Visualization (Canvas-based for performance)

struct BarVisualizationView: View {
    let samples: [Float]

    private let barCount = 32
    // Smoothed bar heights – persisted across renders via @State
    @State private var smoothedBars: [Float] = Array(repeating: 0, count: 32)

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 2
            let padH: CGFloat = 8
            let barWidth = (size.width - padH * 2 - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            let halfH = size.height / 2

            for i in 0..<barCount {
                let h = max(4, CGFloat(smoothedBars[i]) * size.height * 0.85)
                let x = padH + CGFloat(i) * (barWidth + spacing)
                let y = halfH - h / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: h)

                // Base bar fill
                let brightness = 0.35 + (Double(i) / Double(barCount)) * 0.2
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(Color(white: brightness, opacity: 0.9))
                )
                // Specular highlight on top half
                let highlightRect = CGRect(x: x, y: y, width: barWidth, height: h * 0.45)
                context.fill(
                    Path(roundedRect: highlightRect, cornerRadius: 2),
                    with: .color(.white.opacity(0.18))
                )
            }
        }
        .onChange(of: samples) { _, newSamples in
            updateSmoothedBars(newSamples)
        }
    }

    private func updateSmoothedBars(_ newSamples: [Float]) {
        guard !newSamples.isEmpty else { return }
        let samplesPerBar = max(1, newSamples.count / barCount)
        let smoothing: Float = 0.45   // decay factor — tweak for feel

        for i in 0..<barCount {
            let start = i * samplesPerBar
            let end = min(start + samplesPerBar, newSamples.count)
            guard start < newSamples.count else { break }
            var peak: Float = 0
            for j in start..<end { peak = max(peak, newSamples[j]) }
            smoothedBars[i] = smoothedBars[i] * (1 - smoothing) + peak * smoothing
        }
    }
}

// MARK: - Circular Visualization (Canvas-based, batched draw calls)

struct CircularVisualizationView: View {
    let samples: [Float]
    private let barCount = 32   // Reduced from 64 — half the draw calls, same visual quality

    @State private var smoothedBars: [Float] = Array(repeating: 0, count: 32)

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let radius = min(size.width, size.height) / 2 - 16
            let innerR = radius * 0.32

            guard !smoothedBars.isEmpty else { return }

            // Build outer polygon path (filled area) — one fill call
            var outerPath = Path()
            // Build all bars as a single batched path — one stroke call
            var barsPath = Path()

            for i in 0..<barCount {
                let sample = smoothedBars[i]
                let angle = (Double(i) / Double(barCount)) * 2.0 * .pi - .pi / 2.0
                let outerR = innerR + CGFloat(sample) * radius * 0.62 + 6
                let cos_a = cos(angle)
                let sin_a = sin(angle)

                let sx = cx + cos_a * innerR
                let sy = cy + sin_a * innerR
                let ex = cx + cos_a * outerR
                let ey = cy + sin_a * outerR

                barsPath.move(to: CGPoint(x: sx, y: sy))
                barsPath.addLine(to: CGPoint(x: ex, y: ey))

                if i == 0 { outerPath.move(to: CGPoint(x: ex, y: ey)) }
                else       { outerPath.addLine(to: CGPoint(x: ex, y: ey)) }
            }
            outerPath.closeSubpath()

            // 1 fill + 1 stroke instead of 64 individual strokes
            context.fill(outerPath, with: .color(Color(white: 0.3, opacity: 0.12)))
            context.stroke(barsPath, with: .color(Color(white: 0.55, opacity: 0.85)), lineWidth: 3.5)

            // Center decorative circles
            context.fill(Path(ellipseIn: CGRect(x: cx-22, y: cy-22, width: 44, height: 44)),
                         with: .color(Color(white: 0.35, opacity: 0.2)))
            context.fill(Path(ellipseIn: CGRect(x: cx-13, y: cy-13, width: 26, height: 26)),
                         with: .color(Color(white: 0.5, opacity: 0.55)))
            context.fill(Path(ellipseIn: CGRect(x: cx-7, y: cy-7, width: 14, height: 14)),
                         with: .color(Color(white: 0.2, opacity: 0.5)))
        }
        .onChange(of: samples) { _, newSamples in
            updateSmoothedBars(newSamples)
        }
    }

    private func updateSmoothedBars(_ newSamples: [Float]) {
        guard !newSamples.isEmpty else { return }
        let samplesPerBar = max(1, newSamples.count / barCount)
        let smoothing: Float = 0.45

        for i in 0..<barCount {
            let start = i * samplesPerBar
            let end = min(start + samplesPerBar, newSamples.count)
            guard start < newSamples.count else { break }
            var peak: Float = 0
            for j in start..<end { peak = max(peak, newSamples[j]) }
            smoothedBars[i] = smoothedBars[i] * (1 - smoothing) + peak * smoothing
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()

        VStack(spacing: 20) {
            AudioVisualizationPanel(engine: AudioEngineManager())
                .frame(height: 220)

            HStack(spacing: 20) {
                WaveformView(samples: (0..<128).map { _ in Float.random(in: 0...0.8) })
                    .frame(height: 80)
                    .glassCard(cornerRadius: 12, padding: 8)

                BarVisualizationView(samples: (0..<128).map { _ in Float.random(in: 0...0.8) })
                    .frame(height: 80)
                    .glassCard(cornerRadius: 12, padding: 8)
            }

            CircularVisualizationView(samples: (0..<128).map { _ in Float.random(in: 0...0.8) })
                .frame(height: 180)
                .glassCard(cornerRadius: 12, padding: 8)
        }
        .padding()
    }
}
