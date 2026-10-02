import SwiftUI

// MARK: - Riff Notch Host
// Hangs the notch from the very top edge of the window (ignoring the safe area,
// like a hardware notch) and adds a tap-outside catcher while it is opened.

struct RiffNotchHost: View {
    let viewModel: MainViewModel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if viewModel.notch.status == .opened {
                    Color.black.opacity(0.12)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.notch.close() }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }

                RiffNotchView(viewModel: viewModel, topInset: proxy.safeAreaInsets.top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Riff Notch Metrics

enum RiffNotchMetrics {
    /// Minimum height of the closed notch (used where there is no status bar, e.g. Mac).
    static let closedHeight: CGFloat = 26

    static func size(for status: RiffNotchController.Status) -> CGSize {
        switch status {
        case .closed:  CGSize(width: 200, height: closedHeight)
        case .popping: CGSize(width: 360, height: 56)
        case .opened:  CGSize(width: 560, height: 196)
        }
    }

    static func radii(for status: RiffNotchController.Status) -> (top: CGFloat, bottom: CGFloat) {
        switch status {
        case .closed:  (6, 14)
        case .popping: (8, 22)
        case .opened:  (14, 32)
        }
    }
}

// MARK: - Riff Notch View

struct RiffNotchView: View {
    let viewModel: MainViewModel
    let topInset: CGFloat

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var notch: RiffNotchController { viewModel.notch }

    /// NotchDrop's spring: quick, with a little overshoot so the notch feels elastic.
    private var animation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .interactiveSpring(duration: 0.5, extraBounce: 0.25, blendDuration: 0.125)
    }

    var body: some View {
        let size = RiffNotchMetrics.size(for: notch.status)
        let radii = RiffNotchMetrics.radii(for: notch.status)
        // Closed, the notch lives inside the status bar strip like a real Dynamic Island,
        // so it never covers the navigation bar; it only grows down when it has news.
        let isClosed = notch.status == .closed
        let totalHeight = isClosed ? max(topInset, RiffNotchMetrics.closedHeight) : size.height + topInset
        let contentInset = isClosed ? 0 : topInset

        ZStack(alignment: .top) {
            content
                .padding(.top, contentInset)
                .frame(width: size.width, height: totalHeight, alignment: .top)
                .id(notch.status)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                            .animation(animation.delay(0.08)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    )
                )
        }
        .frame(width: size.width + radii.top * 2, height: totalHeight, alignment: .top)
        .background {
            NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
                .fill(.black)
                .shadow(color: .black.opacity(notch.status == .closed ? 0.15 : 0.35),
                        radius: notch.status == .closed ? 4 : 18, y: 4)
        }
        .clipShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
        .contentShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
        .scaleEffect(isHovering && notch.status == .closed ? 1.05 : 1, anchor: .top)
        .environment(\.colorScheme, .dark)
        .onTapGesture {
            if notch.status != .opened { notch.open() }
        }
        .onHover { isHovering = $0 }
        .animation(animation, value: notch.status)
        .animation(animation, value: notch.activity?.id)
        .animation(.spring(duration: 0.25), value: isHovering)
        .sensoryFeedback(.impact(weight: .light), trigger: notch.activity?.id)
        .onChange(of: notch.activity?.id) { _, _ in
            if let activity = notch.activity {
                AccessibilityNotification.Announcement(
                    [activity.title, activity.detail].compactMap { $0 }.joined(separator: ", ")
                ).post()
            }
        }
        .accessibilityElement(children: notch.status == .opened ? .contain : .combine)
        .accessibilityLabel(notch.status == .opened ? "RiffNode controls" : "RiffNode status")
        .accessibilityHint(notch.status == .opened ? "" : "Double-tap to open quick controls")
        .accessibilityAddTraits(notch.status == .opened ? [] : .isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch notch.status {
        case .closed:
            NotchClosedContent(viewModel: viewModel)
        case .popping:
            if let activity = notch.activity {
                NotchActivityContent(activity: activity, level: viewModel.engine.inputLevel)
            } else {
                NotchClosedContent(viewModel: viewModel)
            }
        case .opened:
            NotchOpenedContent(viewModel: viewModel)
        }
    }
}

// MARK: - Closed: live activity pill

private struct NotchClosedContent: View {
    let viewModel: MainViewModel

    var body: some View {
        let engine = viewModel.engine
        let detector = viewModel.chordDetector
        let hasNote = detector.detectedNote != "—"

        HStack(spacing: 8) {
            Circle()
                .fill(engine.isRunning ? Color.green : Color.red)
                .frame(width: 7, height: 7)
                .shadow(color: engine.isRunning ? .green.opacity(0.8) : .clear, radius: 4)

            NotchLevelBars(level: engine.inputLevel, barCount: 5, height: 12)

            Spacer(minLength: 0)

            Text(hasNote ? detector.detectedNote : "—")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(hasNote ? (detector.isInTune ? Color.green : Color.white) : Color.white.opacity(0.4))
                .contentTransition(.numericText())
                .animation(.snappy, value: detector.detectedNote)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Popping: event banner

private struct NotchActivityContent: View {
    let activity: RiffNotchController.Activity
    let level: Float

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(activity.tint)
                .frame(width: 32, height: 32)
                .background(activity.tint.opacity(0.22), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let detail = activity.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            NotchLevelBars(level: level, barCount: 5, height: 16, tint: activity.tint)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Opened: quick controls

private struct NotchOpenedContent: View {
    let viewModel: MainViewModel

    var body: some View {
        let engine = viewModel.engine

        VStack(spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image("RiffNodeLogo")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                Text(viewModel.currentPresetName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .contentTransition(.opacity)

                Text(engine.isRunning ? "LIVE" : "OFF")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(engine.isRunning ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((engine.isRunning ? Color.green : Color.red).opacity(0.18), in: Capsule())

                Spacer()

                Button {
                    viewModel.notch.close()
                } label: {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 32, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close quick controls")
            }

            // Tiles
            HStack(spacing: 10) {
                NotchTunerTile(detector: viewModel.chordDetector)
                NotchMetersTile(engine: engine)
                NotchTransportTile(viewModel: viewModel)
            }
            .frame(height: 96)

            // Pedal chips – tap to toggle
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(engine.effectsChain) { effect in
                        Button {
                            viewModel.toggle(effect)
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(effect.isEnabled ? Color.green : Color.white.opacity(0.25))
                                    .frame(width: 5, height: 5)
                                Text(effect.type.abbreviation)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(effect.isEnabled ? effect.type.color : .white.opacity(0.45))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                (effect.isEnabled ? effect.type.color.opacity(0.22) : Color.white.opacity(0.08)),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityLabel("\(effect.type.rawValue), \(effect.isEnabled ? "on" : "bypassed")")
                        .accessibilityHint("Double-tap to toggle")
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Tiles

private struct NotchTile<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct NotchTunerTile: View {
    let detector: ChordDetector

    var body: some View {
        let hasNote = detector.detectedNote != "—"
        let cents = CGFloat(max(-50, min(50, detector.centsDeviation)))
        let tint: Color = !hasNote ? .white.opacity(0.4) : (detector.isInTune ? .green : .orange)

        NotchTile {
            VStack(spacing: 6) {
                Text(hasNote ? detector.detectedNote : "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())

                // Cents needle: centre = in tune
                GeometryReader { geo in
                    ZStack {
                        Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                        Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1.5, height: 10)
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                            .offset(x: hasNote ? cents / 50 * (geo.size.width / 2 - 4) : 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 10)
                .padding(.horizontal, 14)

                Text(detector.detectedChord == "—" ? "Tuner" : detector.detectedChord)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .animation(.snappy, value: detector.detectedNote)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasNote
            ? "Tuner: \(detector.detectedNote), \(Int(detector.centsDeviation)) cents"
            : "Tuner: no note")
    }
}

private struct NotchMetersTile: View {
    let engine: AudioEngineManager

    var body: some View {
        NotchTile {
            VStack(alignment: .leading, spacing: 8) {
                meter(label: "IN", level: engine.inputLevel)
                meter(label: "OUT", level: engine.outputLevel)
                Label(engine.currentInputDeviceName, systemImage: engine.currentInputDeviceType.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input \(Int(engine.inputLevel * 100)) percent, output \(Int(engine.outputLevel * 100)) percent")
    }

    private func meter(label: String, level: Float) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct NotchTransportTile: View {
    let viewModel: MainViewModel

    var body: some View {
        let isRunning = viewModel.engine.isRunning

        NotchTile {
            HStack(spacing: 6) {
                transportButton("backward.fill", label: "Previous preset") { viewModel.stepPreset(by: -1) }

                Button(action: viewModel.toggleEngine) {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(isRunning ? Color.white : Color.green, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel(isRunning ? "Stop engine" : "Start engine")

                transportButton("forward.fill", label: "Next preset") { viewModel.stepPreset(by: 1) }
            }
        }
    }

    private func transportButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Level Bars

private struct NotchLevelBars: View {
    let level: Float
    let barCount: Int
    let height: CGFloat
    var tint: Color = .green

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                // Centre bars react most, like an audio "pulse"
                let centre = CGFloat(barCount - 1) / 2
                let falloff = 1 - abs(CGFloat(index) - centre) / (centre + 1)
                let amount = min(1, CGFloat(level) * 2.2 * falloff)
                Capsule()
                    .fill(tint.opacity(0.5 + 0.5 * amount))
                    .frame(width: 2.5, height: max(3, height * amount))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Notch shape") {
    VStack(spacing: 40) {
        ForEach([RiffNotchController.Status.closed, .popping, .opened], id: \.self) { status in
            let size = RiffNotchMetrics.size(for: status)
            let radii = RiffNotchMetrics.radii(for: status)
            NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
                .fill(.black)
                .frame(width: size.width + radii.top * 2, height: size.height)
        }
    }
    .padding()
}
