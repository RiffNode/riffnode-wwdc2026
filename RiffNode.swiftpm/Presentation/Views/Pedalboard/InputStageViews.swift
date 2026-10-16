import SwiftUI

// MARK: - Input Stage Panel
// What happens before the first pedal: the pickup and cable filter (tone suck), a buffer,
// a volume pedal and a noise gate – with the cable's effect drawn as a frequency response.

struct InputStagePanelView: View {
    let engine: any InputStageControlling
    var isWide: Bool

    private var settings: InputSettings { engine.inputSettings }

    var body: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.md))
            : AnyLayout(VStackLayout(spacing: Spacing.md))
        layout {
            controls.frame(maxWidth: isWide ? 420 : .infinity)
            CableResponseCard(engine: engine)
        }
    }

    private var controls: some View {
        GlassCard(tint: Color.green.opacity(0.1), cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Guitar, cable & front of the board", systemImage: "cable.connector")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cable length").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(settings.cableFeet)) ft · \(Int(settings.cableFeet * 0.3048)) m")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: binding(\.cableFeet), in: 3...60, step: 1)
                        .tint(.green)
                    Text("Guitar to board, between pedals, board to amp – every foot adds about 30 pF.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle(isOn: binding(\.isBuffered)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Buffer at the front").font(.subheadline.weight(.semibold))
                        Text("Drives the long cables so only the guitar cable loads the pickup.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.green)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Volume pedal").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(settings.volume * 100))%").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(value: binding(\.volume), in: 0...1).tint(.green)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: binding(\.isGateOn)) {
                        Text("Noise gate").font(.subheadline.weight(.semibold))
                    }
                    .tint(.green)
                    HStack {
                        Text("Threshold").font(.caption).foregroundStyle(.secondary)
                        Slider(value: binding(\.gateThresholdDB), in: -80 ... -30).tint(.green)
                        Text("\(Int(settings.gateThresholdDB)) dB").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .disabled(!settings.isGateOn)
                    .opacity(settings.isGateOn ? 1 : 0.5)
                    Text("Closes when you stop playing, so high gain doesn't hiss.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func binding<T>(_ key: WritableKeyPath<InputSettings, T>) -> Binding<T> {
        Binding(get: { engine.inputSettings[keyPath: key] }, set: { engine.inputSettings[keyPath: key] = $0 })
    }
}

// MARK: - Cable Response

/// The pickup and cable as a filter: a small resonant bump, then the highs fall away.
struct CableResponseCard: View {
    let engine: any InputStageControlling

    private static let frequencies: [Float] = (0..<120).map { 40 * pow(Float(16_000) / 40, Float($0) / 119) }

    var body: some View {
        let settings = engine.inputSettings
        let response = engine.inputResponse(at: Self.frequencies)
        let corner = settings.pickupResonanceHz

        GlassCard(tint: Color.green.opacity(0.06), cornerRadius: CornerRadius.xl) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Tone suck, measured", systemImage: "waveform.path.ecg")
                        .font(.headline)
                    Text("What the pickup and \(Int(settings.loadingFeet)) ft of cable do to your guitar's highs")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Canvas { context, size in
                    func y(_ db: Float) -> CGFloat { CGFloat(0.5 - max(-24, min(12, db)) / 36) * size.height * 0.95 + size.height * 0.1 }
                    func x(_ f: Float) -> CGFloat { CGFloat(log2(f / 40) / log2(16_000 / 40)) * size.width }
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y(0))); grid.addLine(to: CGPoint(x: size.width, y: y(0)))
                    for f: Float in [100, 1000, 10_000] {
                        grid.move(to: CGPoint(x: x(f), y: 0)); grid.addLine(to: CGPoint(x: x(f), y: size.height))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 1)
                    // Corner marker
                    var marker = Path()
                    marker.move(to: CGPoint(x: x(corner), y: 0)); marker.addLine(to: CGPoint(x: x(corner), y: size.height))
                    context.stroke(marker, with: .color(.green.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    var curve = Path()
                    for (i, f) in Self.frequencies.enumerated() {
                        let point = CGPoint(x: x(f), y: y(response[i]))
                        i == 0 ? curve.move(to: point) : curve.addLine(to: point)
                    }
                    context.stroke(curve, with: .color(.green), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                }
                .frame(height: 170)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: CornerRadius.md))
                .overlay(alignment: .topTrailing) {
                    Text(corner >= 1000 ? String(format: "Highs roll off above %.1f kHz", corner / 1000) : "Highs roll off above \(Int(corner)) Hz")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.green)
                        .padding(8)
                }
                .accessibilityElement()
                .accessibilityLabel(String(format: "Pickup and cable response, corner at %.1f kilohertz", corner / 1000))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Why long cables sound dull")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("A guitar pickup is a coil of about 2.5 henries, and cable acts as a capacitor. Together they make a filter: f = 1 / (2π√LC). More cable, more capacitance, a lower corner – the sparkle disappears. A buffer at the front stops the long cables from loading the pickup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
