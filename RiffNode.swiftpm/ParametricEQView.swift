import SwiftUI

// MARK: - Parametric EQ View
// Liquid Glass UI Design - iOS 26+
// Modern parametric equalizer with glass styling and smooth curves

struct ParametricEQView: View {
    @Bindable var engine: AudioEngineManager
    @State private var selectedBand: Int? = nil
    @State private var bands: [EQBand] = EQBand.defaultBands
    @State private var isAnalyzerActive = true

    var body: some View {
        VStack(spacing: 16) {
            // Header with analyzer toggle and presets
            GlassEQHeader(
                isAnalyzerActive: $isAnalyzerActive,
                bands: $bands,
                onReset: {
                    bands = EQBand.defaultBands
                    engine.resetEQ()
                }
            )

            // Main EQ Display with glass styling - larger for direct interaction
            GlassCard(cornerRadius: 16, padding: 0) {
                ZStack {
                    // Subtle gradient background
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.2)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Grid
                    GlassEQGridView()

                    // Smooth frequency response curve with fill
                    GlassEQCurveView(bands: bands, selectedBand: selectedBand)

                    // Draggable band nodes - tap to select, drag to adjust
                    GlassEQBandNodes(
                        bands: $bands,
                        selectedBand: $selectedBand
                    )

                    // Hint text when no band selected
                    if selectedBand == nil {
                        VStack {
                            Spacer()
                            Text("Tap a node to select • Drag to adjust")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                        }
                    }
                }
                .frame(height: 320)
            }

            // Selected band controls - compact inline controls
            if let selected = selectedBand {
                GlassEQBandControls(band: $bands[selected])
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(duration: 0.25), value: selectedBand)
        // Sync EQ bands with audio engine whenever they change
        .onChange(of: bands) { _, newBands in
            syncEQToEngine(newBands)
        }
        .onAppear {
            // Initial sync on appear
            syncEQToEngine(bands)
        }
    }

    /// Sync the UI EQ bands to the audio engine
    private func syncEQToEngine(_ bands: [EQBand]) {
        let bandConfigs = bands.map { band in
            (frequency: band.frequency, gain: band.gain, q: band.q, isEnabled: band.isEnabled)
        }
        engine.updateAllEQBands(bandConfigs)
    }
}

// MARK: - Glass EQ Header

struct GlassEQHeader: View {
    @Binding var isAnalyzerActive: Bool
    @Binding var bands: [EQBand]
    let onReset: () -> Void
    @State private var showPresets = false

    var body: some View {
        HStack {
            // EQ Icon and title
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.primary)
                Text("Parametric EQ")
                    .font(.headline)
            }

            Spacer()

            // Controls
            HStack(spacing: 8) {
                Button {
                    showPresets.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11))
                        Text("Presets")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPresets) {
                    GlassEQPresetPicker(bands: $bands, isPresented: $showPresets)
                }

                // Analyzer toggle
                Button {
                    isAnalyzerActive.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isAnalyzerActive ? Color.primary : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text("Analyzer")
                    }
                }
                .buttonStyle(GlassPillStyle(isSelected: isAnalyzerActive, tint: .primary))

                // Reset button
                Button(action: onReset) {
                    Text("Reset")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Glass EQ Preset Picker

struct GlassEQPresetPicker: View {
    @Binding var bands: [EQBand]
    @Binding var isPresented: Bool
    var onPresetApplied: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("EQ Presets")
                    .font(.headline)
                Spacer()
            }
            .padding()

            // Preset list – each item is its own glass pill so they fuse
            ScrollView {
                GlassEffectContainer(spacing: 8) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(EQPreset.presets) { preset in
                            Button {
                                withAnimation(.spring(duration: 0.3)) {
                                    var newBands = bands
                                    preset.applyTo(&newBands)
                                    bands = newBands
                                }
                                onPresetApplied?()
                                isPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.primary)
                                        .frame(width: 24)

                                    Text(preset.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 280, height: 400)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Spectrum Analyzer View

struct SpectrumAnalyzerView: View {
    @State private var levels: [CGFloat] = Array(repeating: 0, count: 32)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { _ in
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(0..<32, id: \.self) { index in
                        let height = generateBarHeight(index: index)

                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.7), .green.opacity(0.2)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: height * geometry.size.height * 0.8)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
            }
        }
    }

    private func generateBarHeight(index: Int) -> CGFloat {
        let baseLevel = CGFloat.random(in: 0.1...0.6)
        let frequencyWeight: CGFloat
        if index < 8 {
            frequencyWeight = 0.8
        } else if index < 20 {
            frequencyWeight = 1.0
        } else {
            frequencyWeight = 0.5
        }
        return baseLevel * frequencyWeight
    }
}

// MARK: - Glass EQ Grid View

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

// MARK: - Glass EQ Curve View

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

// MARK: - Glass EQ Band Nodes

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

// MARK: - Glass EQ Band Strip

struct GlassEQBandStrip: View {
    @Binding var bands: [EQBand]
    @Binding var selectedBand: Int?

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            ForEach(Array(bands.indices), id: \.self) { index in
                let band = bands[index]
                let isSelected = selectedBand == index

                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        selectedBand = selectedBand == index ? nil : index
                    }
                } label: {
                    VStack(spacing: 2) {
                        // Band number – selected gets a tinted glass circle
                        ZStack {
                            Circle()
                                .fill(.clear)
                                .frame(width: 20, height: 20)
                                .glassEffect(
                                    isSelected
                                        ? .regular.tint(band.type.color)
                                        : .regular.tint(band.type.color.opacity(0.2)),
                                    in: Circle()
                                )

                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isSelected ? .white : .primary)
                        }

                        // Frequency
                        Text(formatFrequency(band.frequency))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .glassEffect(
                    isSelected ? .regular.tint(band.type.color) : .regular,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .buttonStyle(.plain)
            }
        }
    }

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk", freq / 1000)
        }
        return "\(Int(freq))"
    }
}

// MARK: - Glass EQ Band Controls

struct GlassEQBandControls: View {
    @Binding var band: EQBand

    var body: some View {
        GlassCard(cornerRadius: 12) {
            VStack(spacing: 12) {
                // Type selector – each type pill gets glass; selected one is tinted
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(EQBand.BandType.allCases, id: \.self) { type in
                            Button {
                                band.type = type
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: type.icon)
                                        .font(.system(size: 12))
                                    Text(type.shortName)
                                        .font(.system(size: 8, weight: .medium))
                                }
                                .frame(width: 46, height: 32)
                                .foregroundStyle(band.type == type ? .white : .secondary)
                                .glassEffect(
                                    band.type == type
                                        ? .regular.tint(type.color)
                                        : .regular,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Value controls
                HStack(spacing: 20) {
                    // Frequency
                    VStack(spacing: 4) {
                        Text("FREQ")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Text(formatFrequency(band.frequency))
                            .font(.system(size: 16, weight: .bold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 70)

                    // Gain with +/- buttons
                    VStack(spacing: 4) {
                        Text("GAIN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                band.gain = max(-24, band.gain - 1)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)

                            Text(String(format: "%+.1f", band.gain))
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundStyle(.primary)
                                .frame(width: 50)

                            Button {
                                band.gain = min(24, band.gain + 1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }

                    // Q with +/- buttons
                    VStack(spacing: 4) {
                        Text("Q")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                band.q = max(0.1, band.q - 0.1)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)

                            Text(String(format: "%.1f", band.q))
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundStyle(.primary)
                                .frame(width: 36)

                            Button {
                                band.q = min(10, band.q + 0.1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.2fk", freq / 1000)
        }
        return String(format: "%.0f", freq)
    }
}

// MARK: - EQ Band Model

struct EQBand: Identifiable, Equatable {
    let id: Int
    var frequency: Float      // 20 - 20000 Hz
    var gain: Float           // -24 to +24 dB
    var q: Float              // 0.1 to 10
    var type: BandType
    var isEnabled: Bool

    enum BandType: String, CaseIterable {
        case highPass = "High Pass"
        case lowShelf = "Low Shelf"
        case peak = "Peak"
        case highShelf = "High Shelf"
        case lowPass = "Low Pass"

        var icon: String {
            switch self {
            case .highPass: return "line.diagonal"
            case .lowShelf: return "arrow.down.left"
            case .peak: return "diamond"
            case .highShelf: return "arrow.up.right"
            case .lowPass: return "line.diagonal"
            }
        }

        var shortName: String {
            switch self {
            case .highPass: return "HP"
            case .lowShelf: return "LS"
            case .peak: return "PK"
            case .highShelf: return "HS"
            case .lowPass: return "LP"
            }
        }

        var color: Color {
            switch self {
            case .highPass: return .red
            case .lowShelf: return .orange
            case .peak: return .green
            case .highShelf: return .cyan
            case .lowPass: return .purple
            }
        }
    }

    // 10-band frequencies: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k
    static let defaultBands: [EQBand] = [
        EQBand(id: 0, frequency: 32, gain: 0, q: 1.0, type: .lowShelf, isEnabled: true),
        EQBand(id: 1, frequency: 64, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 2, frequency: 125, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 3, frequency: 250, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 4, frequency: 500, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 5, frequency: 1000, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 6, frequency: 2000, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 7, frequency: 4000, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 8, frequency: 8000, gain: 0, q: 1.0, type: .peak, isEnabled: true),
        EQBand(id: 9, frequency: 16000, gain: 0, q: 1.0, type: .highShelf, isEnabled: true)
    ]
}

// MARK: - EQ Presets

struct EQPreset: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let gains: [Float] // 10 values for 10 bands

    static let presets: [EQPreset] = [
        EQPreset(name: "Flat", icon: "equal", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Rock", icon: "guitars", gains: [5, 4, 3, 1, -1, 1, 3, 4, 5, 4]),
        EQPreset(name: "Pop", icon: "music.note", gains: [-2, -1, 0, 2, 4, 4, 2, 0, -1, -2]),
        EQPreset(name: "Jazz", icon: "music.quarternote.3", gains: [4, 3, 1, 2, -2, -2, 0, 1, 3, 4]),
        EQPreset(name: "Classical", icon: "waveform", gains: [5, 4, 3, 2, -1, -1, 0, 2, 3, 4]),
        EQPreset(name: "Hip-Hop", icon: "headphones", gains: [5, 5, 3, 1, -1, 0, 1, 0, 2, 3]),
        EQPreset(name: "Electronic", icon: "bolt.fill", gains: [4, 5, 3, 0, -2, 1, 3, 4, 4, 3]),
        EQPreset(name: "R&B", icon: "heart.fill", gains: [3, 6, 4, 1, -2, 0, 2, 3, 3, 2]),
        EQPreset(name: "Acoustic", icon: "guitars.fill", gains: [4, 3, 2, 1, 1, 1, 2, 3, 3, 2]),
        EQPreset(name: "Bass Boost", icon: "speaker.wave.3.fill", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Treble Boost", icon: "sparkles", gains: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6]),
        EQPreset(name: "Vocal", icon: "mic.fill", gains: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]),
        EQPreset(name: "Loudness", icon: "speaker.wave.2.fill", gains: [4, 3, 0, 0, -1, 0, -1, 0, 3, 4]),
        EQPreset(name: "Metal", icon: "flame.fill", gains: [4, 3, 0, 0, -3, 0, 0, 3, 4, 3])
    ]

    func applyTo(_ bands: inout [EQBand]) {
        for i in 0..<min(bands.count, gains.count) {
            bands[i].gain = gains[i]
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()

        ParametricEQView(engine: AudioEngineManager())
            .frame(height: 500)
            .padding()
    }
}
