import SwiftUI

// MARK: - Stompbox View
// Draws one pedal as hardware: the enclosure shape and paint of its classic model, its
// knobs and labels, the status LED and the metal footswitch. Purely visual – the board
// and Stage Mode wrap it with their own gestures. Sizes are in points at scale 1; Stage
// Mode scales the whole pedal up.

struct StompboxView: View {
    let effect: EffectNode
    /// Lit when the pedal is actually in the signal (on, and the board not bypassed).
    let isLive: Bool
    var scale: CGFloat = 1

    private var model: PedalModel? { effect.model }
    private var look: PedalLook {
        model?.look ?? PedalLook(shape: .classic, body: 0, ink: 0, knob: .black, knobLabels: [])
    }
    private var body_: Color { model == nil ? effect.type.enclosureColor : Color(hex: look.body) }
    private var ink: Color {
        model == nil ? (effect.type.enclosureIsLight ? Color(white: 0.12) : Color(white: 0.96)) : Color(hex: look.ink)
    }
    private var knobCount: Int { model.map { $0.look.knobLabels.count } ?? effect.type.knobCount }

    /// Footprint at scale 1, by shape.
    nonisolated static func size(for shape: PedalLook.Shape) -> CGSize {
        switch shape {
        case .mini: CGSize(width: 70, height: 128)
        case .wide: CGSize(width: 124, height: 132)
        case .dome: CGSize(width: 112, height: 112)
        case .treadlePlate: CGSize(width: 80, height: 136)
        case .slantSwitch, .classic: CGSize(width: 86, height: 132)
        }
    }

    var body: some View {
        let size = Self.size(for: look.shape)
        content
            .frame(width: size.width * scale, height: size.height * scale)
            .background(enclosure)
            .overlay(edge)
            // A bypassed pedal looks switched off
            .saturation(isLive ? 1 : 0.45)
            .brightness(isLive ? 0 : -0.12)
            .shadow(color: .black.opacity(0.3), radius: 6 * scale, y: 3 * scale)
    }

    // MARK: Layout per shape

    @ViewBuilder private var content: some View {
        switch look.shape {
        case .dome:
            VStack(spacing: 6 * scale) {
                knobs(size: 15)
                    .padding(.top, 16 * scale)
                nameplate(size: 11)
                led
                footswitch(size: 22)
                Spacer(minLength: 0)
            }
        case .slantSwitch:
            // Two big knobs at the corners, the small middle one tucked lower, the name, then a
            // wide rectangular treadle across the bottom half
            VStack(spacing: 3 * scale) {
                HStack(alignment: .top, spacing: 0) {
                    labelledKnob(0, size: 18)
                    Spacer(minLength: 0)
                    labelledKnob(1, size: 11).padding(.top, 9 * scale)
                    Spacer(minLength: 0)
                    labelledKnob(2, size: 18)
                }
                .padding(.horizontal, 8 * scale)
                .padding(.top, 8 * scale)
                HStack(spacing: 4 * scale) {
                    led
                    nameplate(size: 10)
                }
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 3 * scale)
                    .fill(LinearGradient(colors: [body_.mix(with: .white, by: 0.12), body_.mix(with: .black, by: 0.3)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 50 * scale)
                    .overlay(RoundedRectangle(cornerRadius: 3 * scale).strokeBorder(.black.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 1.5 * scale, y: 1.5 * scale)
                    .padding(.horizontal, 6 * scale)
                    .padding(.bottom, 6 * scale)
            }
        case .treadlePlate:
            // Knobs along the top with the check LED, then a hinged treadle carrying a ribbed
            // black rubber pad; the pedal's name is printed across the bottom of the treadle
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 3 * scale) {
                    ForEach(0..<knobCount, id: \.self) { labelledKnob($0, size: 12) }
                }
                .padding(.top, 7 * scale)
                led.padding(.top, 3 * scale)
                Spacer(minLength: 3 * scale)
                VStack(spacing: 4 * scale) {
                    VStack(spacing: 2.5 * scale) {
                        ForEach(0..<7, id: \.self) { _ in
                            Capsule().fill(Color(white: 0.2)).frame(height: 1.6 * scale)
                        }
                    }
                    .padding(5 * scale)
                    .background(RoundedRectangle(cornerRadius: 3 * scale).fill(Color(white: 0.08)))
                    .padding(.horizontal, 9 * scale)
                    .padding(.top, 6 * scale)
                    nameplate(size: 9)
                        .padding(.bottom, 5 * scale)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 70 * scale)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 3 * scale, bottomLeadingRadius: 9 * scale,
                                           bottomTrailingRadius: 9 * scale, topTrailingRadius: 3 * scale)
                        .fill(body_.mix(with: .white, by: 0.06))
                        .shadow(color: .black.opacity(0.35), radius: 1, y: -1)
                )
            }
        case .mini:
            VStack(spacing: 6 * scale) {
                knobs(size: 13)
                    .padding(.top, 9 * scale)
                nameplate(size: 15, vertical: true, italic: true)
                Spacer(minLength: 0)
                led
                footswitch(size: 22)
                    .padding(.bottom, 9 * scale)
            }
        case .wide:
            VStack(spacing: 6 * scale) {
                knobs(size: 15)
                    .padding(.top, 10 * scale)
                nameplate(size: 14)
                Spacer(minLength: 0)
                HStack {
                    led
                    Spacer()
                }
                .padding(.horizontal, 12 * scale)
                footswitch(size: 24)
                    .padding(.bottom, 9 * scale)
            }
        case .classic:
            VStack(spacing: 7 * scale) {
                knobs(size: 16)
                    .padding(.top, 10 * scale)
                nameplate(size: 15)
                Spacer(minLength: 0)
                led
                footswitch(size: 26)
                    .padding(.bottom, 10 * scale)
            }
        }
    }

    // MARK: Parts

    @ViewBuilder private var enclosure: some View {
        let paint = LinearGradient(colors: [body_, body_.mix(with: .black, by: 0.22)], startPoint: .top, endPoint: .bottom)
        switch look.shape {
        case .dome: Circle().fill(paint)
        case .wide: RoundedRectangle(cornerRadius: 6 * scale).fill(paint)
        case .mini: RoundedRectangle(cornerRadius: 9 * scale).fill(paint)
        case .slantSwitch, .treadlePlate, .classic: RoundedRectangle(cornerRadius: 10 * scale).fill(paint)
        }
    }

    @ViewBuilder private var edge: some View {
        let stroke = LinearGradient(colors: [.white.opacity(0.45), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        switch look.shape {
        case .dome: Circle().strokeBorder(stroke, lineWidth: 1.2)
        case .wide: RoundedRectangle(cornerRadius: 6 * scale).strokeBorder(stroke, lineWidth: 1.2)
        case .mini: RoundedRectangle(cornerRadius: 9 * scale).strokeBorder(stroke, lineWidth: 1.2)
        case .slantSwitch, .treadlePlate, .classic: RoundedRectangle(cornerRadius: 10 * scale).strokeBorder(stroke, lineWidth: 1.2)
        }
    }

    /// The pedal's own name, in its ink – no logos.
    private func nameplate(size: CGFloat, vertical: Bool = false, italic: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(model?.name ?? effect.type.abbreviation)
                .font(.system(size: size * scale, weight: .heavy, design: .rounded))
                .italic(italic)
                .multilineTextAlignment(.center)
                .lineLimit(vertical ? 3 : 2)
                .minimumScaleFactor(0.6)
            if model == nil {
                Text(effect.type.rawValue.uppercased())
                    .font(.system(size: 7.5 * scale, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.75)
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 6 * scale)
    }

    private func knobs(size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 5 * scale) {
            ForEach(0..<knobCount, id: \.self) { labelledKnob($0, size: size) }
        }
    }

    /// One knob and its printed label, the pointer at the knob's real setting.
    private func labelledKnob(_ index: Int, size: CGFloat) -> some View {
        let label = look.knobLabels[safe: index]
        return VStack(spacing: 2 * scale) {
            knob(diameter: size * scale, position: label.map(knobPosition) ?? 0.5)
            if let label, look.shape != .classic {
                Text(label)
                    .font(.system(size: 5.5 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// 0…1 for the parameter a printed label stands for (0.5 when it has no single parameter).
    private func knobPosition(for label: String) -> Double {
        let p = effect.parameters
        func unit(_ key: String, _ range: ClosedRange<Float>) -> Double {
            guard let v = p[key] else { return 0.5 }
            return Double((v - range.lowerBound) / (range.upperBound - range.lowerBound))
        }
        let rateRange: ClosedRange<Float> = switch effect.type {
        case .tremolo: 0.5...15
        case .phaser: 0.1...5
        case .flanger: 0.1...2
        default: 0.1...10
        }
        let position: Double = switch label {
        case "DRIVE", "GAIN", "DIST", "DISTORTION": unit("drive", 0...100)
        case "FUZZ", "SUSTAIN": p["fuzz"] != nil ? unit("fuzz", 0...100) : unit("drive", 0...100)
        case "TONE", "TREBLE", "FILTER", "LOW", "HIGH": unit("tone", 0...100)
        case "LEVEL", "VOLUME", "OUTPUT": unit("level", 0...100)
        case "SENSITIVITY": 1 - unit("threshold", -40...0)
        case "RATE", "SPEED": unit("rate", rateRange)
        case "DEPTH", "INTENSITY", "RANGE": unit("depth", 0...100)
        case "COLOR", "REGEN", "FEEDBACK": unit("feedback", 0...100)
        case "MIX": unit("mix", 0...100)
        case "DELAY", "TIME": unit("time", 0.02...2)
        case "REVERB": unit("wetDryMix", 0...100)
        default: 0.5
        }
        return min(max(position, 0), 1)
    }

    private func knob(diameter: CGFloat, position: Double = 0.5) -> some View {
        let colors: [Color] = switch look.knob {
        case .black: [Color(white: 0.28), Color(white: 0.06)]
        case .cream: [Color(red: 0.96, green: 0.92, blue: 0.82), Color(red: 0.78, green: 0.72, blue: 0.6)]
        case .chrome: [Color(white: 0.95), Color(white: 0.55)]
        case .red: [Color(red: 0.85, green: 0.15, blue: 0.15), Color(red: 0.5, green: 0.05, blue: 0.05)]
        }
        let pointer: Color = look.knob == .black || look.knob == .red ? .white.opacity(0.85) : .black.opacity(0.7)
        return Circle()
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: diameter, height: diameter)
            .overlay(Rectangle().fill(pointer).frame(width: max(1.5, diameter * 0.09), height: diameter * 0.38)
                .offset(y: -diameter * 0.25)
                .rotationEffect(.degrees(-135 + 270 * position)))   // 7 o'clock … 5 o'clock
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
    }

    private var led: some View {
        Circle()
            .fill(isLive ? Color.red : Color(white: 0.25))
            .frame(width: 7 * scale, height: 7 * scale)
            .shadow(color: isLive ? .red.opacity(0.9) : .clear, radius: 4 * scale)
    }

    private func footswitch(size: CGFloat) -> some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.55)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size * scale, height: size * scale)
            .overlay(Circle().strokeBorder(Color(white: 0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

// MARK: - Helpers

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Pedal Model Menu

/// The pedal's name; tap to swap it for another classic of the same kind.
struct PedalModelMenu: View {
    let effect: EffectNode
    let engine: any EffectsChainManaging

    var body: some View {
        let models = PedalModel.models(for: effect.type)
        if models.count > 1 {
            Menu {
                Picker("Pedal", selection: Binding(
                    get: { effect.modelID ?? "" },
                    set: { engine.setPedalModel(effect, modelID: $0) }
                )) {
                    ForEach(models) { model in
                        Text(model.name).tag(model.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    title
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityHint("Chooses which classic \(effect.type.rawValue.lowercased()) this pedal is")
        } else {
            title
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(effect.model?.name ?? effect.type.rawValue).font(.headline)
            if let model = effect.model {
                Text(model.type.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Pedal Model About

/// What the classic circuit does, and which original it's voiced after.
struct PedalModelAbout: View {
    let model: PedalModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.about)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Voiced after the \(model.inspiredBy) (\(String(model.year))). Names and designs are RiffNode's own; trademarks belong to their owners.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
