import SwiftUI

// MARK: - EQ Curve

struct GlassEQGridView: View {
    let frequencies: [Float] = [30, 60, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    let gains: [Float] = [-24, -18, -12, -6, 0, 6, 12, 18, 24]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                // Vertical frequency lines
                ForEach(frequencies, id: \.self) { freq in
                    let x = frequencyToX(freq, width: width)

                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)

                    // Frequency label at bottom
                    Text(formatFrequency(freq))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .position(x: x, y: height - 8)
                }

                // Horizontal gain lines
                ForEach(gains, id: \.self) { gain in
                    let y = gainToY(gain, height: height)

                    Path { path in
                        path.move(to: CGPoint(x: 25, y: y))
                        path.addLine(to: CGPoint(x: width - 5, y: y))
                    }
                    .stroke(
                        gain == 0 ? Color.white.opacity(0.2) : Color.white.opacity(0.04),
                        lineWidth: gain == 0 ? 1 : 0.5
                    )

                    // Gain label on left
                    if gain == 0 || abs(gain) == 12 || abs(gain) == 24 {
                        Text("\(gain > 0 ? "+" : "")\(Int(gain))")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                            .position(x: 12, y: y)
                    }
                }
            }
        }
    }

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return "\(Int(freq / 1000))k"
        }
        return "\(Int(freq))"
    }

    private func frequencyToX(_ freq: Float, width: CGFloat) -> CGFloat {
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logFreq = log10(max(freq, minFreq))
        return 30 + CGFloat((logFreq - logMin) / (logMax - logMin)) * (width - 40)
    }

    private func gainToY(_ gain: Float, height: CGFloat) -> CGFloat {
        let minGain: Float = -24
        let maxGain: Float = 24
        return 15 + CGFloat(1 - (gain - minGain) / (maxGain - minGain)) * (height - 35)
    }
}

struct GlassEQCurveView: View {
    let bands: [EQBand]
    let selectedBand: Int?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            // Gradient fill under curve
            Path { path in
                let zeroY = gainToY(0, height: height)
                path.move(to: CGPoint(x: 30, y: zeroY))

                for x in stride(from: 30, to: width - 10, by: 1) {
                    let freq = xToFrequency(x, width: width)
                    let totalGain = calculateTotalGain(at: freq)
                    let y = gainToY(totalGain, height: height)
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                path.addLine(to: CGPoint(x: width - 10, y: zeroY))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.25),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Main curve stroke
            Path { path in
                var started = false
                for x in stride(from: 30, to: width - 10, by: 1) {
                    let freq = xToFrequency(x, width: width)
                    let totalGain = calculateTotalGain(at: freq)
                    let y = gainToY(totalGain, height: height)

                    if !started {
                        path.move(to: CGPoint(x: x, y: y))
                        started = true
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.8), .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )

            // Selected band individual curve highlight
            if let selected = selectedBand {
                let band = bands[selected]
                Path { path in
                    var started = false
                    for x in stride(from: 30, to: width - 10, by: 1) {
                        let freq = xToFrequency(x, width: width)
                        let bandGain = calculateBandGain(band, at: freq)
                        let y = gainToY(bandGain, height: height)

                        if !started {
                            path.move(to: CGPoint(x: x, y: y))
                            started = true
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(band.type.color.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
    }

    private func calculateTotalGain(at frequency: Float) -> Float {
        var total: Float = 0
        for band in bands where band.isEnabled {
            total += calculateBandGain(band, at: frequency)
        }
        return max(-24, min(24, total))
    }

    private func calculateBandGain(_ band: EQBand, at frequency: Float) -> Float {
        let ratio = frequency / band.frequency
        let logRatio = log2(ratio)

        switch band.type {
        case .peak:
            let bandwidth = 1.0 / band.q
            let x = logRatio / bandwidth
            return band.gain * exp(-x * x * 2)

        case .lowShelf:
            if frequency < band.frequency {
                return band.gain
            } else {
                let x = logRatio * band.q
                return band.gain * exp(-x * x)
            }

        case .highShelf:
            if frequency > band.frequency {
                return band.gain
            } else {
                let x = -logRatio * band.q
                return band.gain * exp(-x * x)
            }

        case .highPass:
            if frequency < band.frequency {
                let octaves = log2(band.frequency / frequency)
                return -octaves * 12
            }
            return 0

        case .lowPass:
            if frequency > band.frequency {
                let octaves = log2(frequency / band.frequency)
                return -octaves * 12
            }
            return 0
        }
    }

    private func xToFrequency(_ x: CGFloat, width: CGFloat) -> Float {
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let ratio = Float((x - 30) / (width - 40))
        let logFreq = logMin + ratio * (logMax - logMin)
        return pow(10, logFreq)
    }

    private func gainToY(_ gain: Float, height: CGFloat) -> CGFloat {
        let minGain: Float = -24
        let maxGain: Float = 24
        return 15 + CGFloat(1 - (gain - minGain) / (maxGain - minGain)) * (height - 35)
    }
}

struct GlassEQBandNodes: View {
    @Binding var bands: [EQBand]
    @Binding var selectedBand: Int?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ForEach(bands.indices, id: \.self) { index in
                let band = bands[index]
                let x = frequencyToX(band.frequency, width: width)
                let y = gainToY(band.gain, height: height)
                let isSelected = selectedBand == index

                ZStack {
                    // Outer glow for selected
                    if isSelected {
                        Circle()
                            .fill(band.type.color.opacity(0.3))
                            .frame(width: 36, height: 36)
                            .blur(radius: 6)
                    }

                    // Main node with glass effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [band.type.color, band.type.color.opacity(0.7)],
                                center: .center,
                                startRadius: 0,
                                endRadius: isSelected ? 12 : 8
                            )
                        )
                        .frame(width: isSelected ? 24 : 16, height: isSelected ? 24 : 16)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white, lineWidth: isSelected ? 2 : 1)
                        )

                    // Band number
                    Text("\(index + 1)")
                        .font(.system(size: isSelected ? 10 : 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .position(x: x, y: y)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            selectedBand = index
                            let newFreq = xToFrequency(value.location.x, width: width)
                            let newGain = yToGain(value.location.y, height: height)
                            bands[index].frequency = max(20, min(20000, newFreq))
                            bands[index].gain = max(-24, min(24, newGain))
                        }
                )
                .onTapGesture {
                    withAnimation(.spring(duration: 0.2)) {
                        selectedBand = selectedBand == index ? nil : index
                    }
                }
            }
        }
    }

    private func frequencyToX(_ freq: Float, width: CGFloat) -> CGFloat {
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logFreq = log10(max(freq, minFreq))
        return 30 + CGFloat((logFreq - logMin) / (logMax - logMin)) * (width - 40)
    }

    private func xToFrequency(_ x: CGFloat, width: CGFloat) -> Float {
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let ratio = Float(max(0, min(x - 30, width - 40)) / (width - 40))
        let logFreq = logMin + ratio * (logMax - logMin)
        return pow(10, logFreq)
    }

    private func gainToY(_ gain: Float, height: CGFloat) -> CGFloat {
        let minGain: Float = -24
        let maxGain: Float = 24
        return 15 + CGFloat(1 - (gain - minGain) / (maxGain - minGain)) * (height - 35)
    }

    private func yToGain(_ y: CGFloat, height: CGFloat) -> Float {
        let minGain: Float = -24
        let maxGain: Float = 24
        let ratio = Float(max(0, min(y - 15, height - 35)) / (height - 35))
        return maxGain - ratio * (maxGain - minGain)
    }
}
