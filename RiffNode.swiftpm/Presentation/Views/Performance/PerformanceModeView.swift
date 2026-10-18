import SwiftUI

// MARK: - Performance Mode View
// The board for playing live: every pedal visible at once as a big footswitch (one tap
// stomps it, like the real thing), the preset name readable from across the room, the
// looper, tuner mute and a board-wide bypass. Hardware keys, a MIDI foot controller and
// head gestures all drive the same controls.

struct PerformanceModeView: View {
    let engine: any PerformanceEngine
    let looper: any LooperControlling
    let gestureController: any GestureControlling
    @Bindable var controller: PerformanceModeController
    let presets: [EffectPreset]
    let onToggleGestures: () -> Void
    let onStepPreset: (Int) -> Void
    let onSelectPreset: (Int) -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            AdaptiveBackground()

            VStack(spacing: Spacing.lg) {
                topBar
                presetHeader
                PerformanceFootswitchGrid(engine: engine)
                    .frame(maxHeight: .infinity)
                bottomBar
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.lg)

            if gestureController.isRunning {
                GestureIndicatorOverlay(gestureController: gestureController, performanceController: controller)
            }
        }
        .background { PerformanceKeyboardShortcuts(
            engine: engine, looper: looper, controller: controller,
            onStepPreset: onStepPreset, onExit: onExit
        ) }
        .onAppear {
            controller.activate()
            setIdleTimerDisabled(true)
        }
        .onDisappear {
            controller.deactivate()
            setIdleTimerDisabled(false)
        }
    }

    /// On stage the screen must never dim or lock.
    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }

    // MARK: Top Bar

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button("Exit", systemImage: "xmark", action: onExit)
                    .buttonStyle(.glass)
                    .help("Esc")

                Spacer()

                Label("PERFORMANCE", systemImage: "music.mic")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.orange.opacity(0.15)), in: Capsule())

                Spacer()

                Button(gestureController.isRunning ? "Gestures On" : "Gestures Off",
                       systemImage: gestureController.isRunning ? "face.smiling.inverse" : "face.dashed",
                       action: onToggleGestures)
                    .buttonStyle(.glass)
                    .tint(gestureController.isRunning ? .purple : nil)
                    .help("Nod for presets, tilt to bypass or switch all on, open your mouth to wah, raise your eyebrows to boost")
            }
        }
    }

    // MARK: Preset Header

    private var presetIndex: Int {
        presets.isEmpty ? 0 : min(max(controller.currentPresetIndex, 0), presets.count - 1)
    }

    private var presetHeader: some View {
        HStack(spacing: Spacing.lg) {
            presetStepButton(-1, "chevron.left", "Previous preset")
            VStack(spacing: 4) {
                if presets.indices.contains(presetIndex) {
                    let preset = presets[presetIndex]
                    Text("PRESET \(presetIndex + 1)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(preset.category.color)
                    Text(preset.name)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                } else {
                    Text("No presets").font(.title.bold()).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: presetIndex)
            presetStepButton(1, "chevron.right", "Next preset")
        }
        .padding(.vertical, Spacing.sm)
    }

    private func presetStepButton(_ offset: Int, _ icon: String, _ label: String) -> some View {
        Button { onStepPreset(offset) } label: {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .bold))
                .frame(width: 72, height: 72)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(presets.isEmpty)
        .accessibilityLabel(label)
        .help(offset < 0 ? "← previous preset" : "→ next preset")
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: Spacing.md) {
            PerformanceMeters(engine: engine)

            PerformanceLooperSwitch(looper: looper)

            boardButton(engine.isPedalboardBypassed ? "Board Bypassed" : "Bypass Board",
                        icon: engine.isPedalboardBypassed ? "power.circle.fill" : "power.circle",
                        isOn: engine.isPedalboardBypassed, tint: .orange, key: "B") {
                controller.toggleBypassAll(engine: engine)
            }

            boardButton(engine.isTunerMuted ? "Muted" : "Tuner Mute",
                        icon: engine.isTunerMuted ? "speaker.slash.fill" : "tuningfork",
                        isOn: engine.isTunerMuted, tint: .red, key: "T") {
                engine.isTunerMuted.toggle()
            }

            QuickPresetBar(presets: presets, currentIndex: presetIndex, onSelect: onSelectPreset)
        }
    }

    private func boardButton(_ title: String, icon: String, isOn: Bool, tint: Color, key: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 26, weight: .semibold))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(isOn ? tint : .primary)
            .frame(width: 112, height: 88)
            .glassEffect(isOn ? .regular.tint(tint.opacity(0.3)).interactive() : .regular.interactive(),
                         in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .help(key)
    }
}

// MARK: - Footswitch Grid
// Every pedal on screen at once – no scrolling mid-song – on the same dark board as the
// Pedalboard tab. Its own view, so the pedals don't redraw each time a level meter moves.

private struct PerformanceFootswitchGrid: View {
    let engine: any PerformanceEngine

    /// The Pedalboard tab's stompbox is 84 × 132 pt; here it's scaled up to fill the stage.
    private static let pedalSize = CGSize(width: 84, height: 132)
    private static let spacing: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let count = max(engine.effectsChain.count, 1)
            let layout = Self.bestLayout(count: count, in: CGSize(width: geo.size.width - 48, height: geo.size.height - 48))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.pedalSize.width * layout.scale), spacing: Self.spacing),
                                     count: layout.columns),
                      spacing: Self.spacing) {
                ForEach(Array(engine.effectsChain.enumerated()), id: \.element.id) { index, effect in
                    PerformanceStompbox(effect: effect, number: index + 1, scale: layout.scale,
                                        isBoardBypassed: engine.isPedalboardBypassed) {
                        engine.toggleEffect(effect)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The column count that lets the pedals grow the most while all of them fit.
    private static func bestLayout(count: Int, in size: CGSize) -> (columns: Int, scale: CGFloat) {
        var best = (columns: count, scale: CGFloat(0.5))
        for columns in 1...count {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let widthScale = (size.width - CGFloat(columns - 1) * spacing) / (pedalSize.width * CGFloat(columns))
            let heightScale = (size.height - CGFloat(rows - 1) * spacing) / (pedalSize.height * CGFloat(rows))
            let scale = min(widthScale, heightScale, 2.2)
            if scale > best.scale { best = (columns, scale) }
        }
        return best
    }
}

// MARK: - Stompbox

/// The Pedalboard tab's stompbox, scaled up – same painted enclosure, knobs, name plate, LED
/// and metal footswitch – but one tap stomps it, like on stage.
private struct PerformanceStompbox: View {
    let effect: EffectNode
    let number: Int
    let scale: CGFloat
    let isBoardBypassed: Bool
    let onStomp: () -> Void

    private var isLive: Bool { effect.isEnabled && !isBoardBypassed }
    private var ink: Color { effect.type.enclosureIsLight ? Color(white: 0.12) : Color(white: 0.96) }

    var body: some View {
        Button(action: onStomp) {
            VStack(spacing: 7 * scale) {
                // Mini knobs across the top
                HStack(spacing: 6 * scale) {
                    ForEach(0..<effect.type.knobCount, id: \.self) { _ in
                        Circle()
                            .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.06)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 16 * scale, height: 16 * scale)
                            .overlay(Rectangle().fill(Color.white.opacity(0.85))
                                .frame(width: 1.5 * scale, height: 6 * scale).offset(y: -4 * scale))
                            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                    }
                }
                .padding(.top, 10 * scale)

                // Name plate
                VStack(spacing: 1) {
                    Text(effect.type.abbreviation)
                        .font(.system(size: 15 * scale, weight: .heavy, design: .rounded))
                    Text(effect.type.rawValue.uppercased())
                        .font(.system(size: 7.5 * scale, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(0.75)
                }
                .foregroundStyle(ink)

                Spacer(minLength: 0)

                // Status LED
                Circle()
                    .fill(isLive ? Color.red : Color(white: 0.25))
                    .frame(width: 7 * scale, height: 7 * scale)
                    .shadow(color: isLive ? .red.opacity(0.9) : .clear, radius: 4 * scale)

                // Metal footswitch
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26 * scale, height: 26 * scale)
                    .overlay(Circle().strokeBorder(Color(white: 0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(.bottom, 10 * scale)
            }
            .frame(width: 84 * scale, height: 132 * scale)
            .background(
                RoundedRectangle(cornerRadius: 10 * scale)
                    .fill(LinearGradient(colors: [effect.type.enclosureColor, effect.type.enclosureColor.opacity(0.78)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10 * scale)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.black.opacity(0.35)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            )
            // A bypassed pedal looks switched off, as on the Pedalboard tab
            .saturation(isLive ? 1 : 0.45)
            .brightness(isLive ? 0 : -0.12)
            // Its number, for the 1–9 keys
            .overlay(alignment: .topLeading) {
                if number <= 9 {
                    Text("\(number)")
                        .font(.system(size: 9 * scale, weight: .bold, design: .monospaced))
                        .foregroundStyle(ink.opacity(0.55))
                        .padding(5 * scale)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 10 * scale))
        }
        .buttonStyle(StompButtonStyle())
        .animation(.snappy(duration: 0.15), value: isLive)
        .accessibilityLabel("\(effect.type.rawValue), \(isLive ? "on" : "off")")
        .accessibilityHint("Stomps the pedal on or off")
        .help(number <= 9 ? "Press \(number)" : effect.type.rawValue)
    }
}

/// Presses down like a metal footswitch.
private struct StompButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Looper Switch

private struct PerformanceLooperSwitch: View {
    let looper: any LooperControlling

    private var tint: Color {
        switch looper.state {
        case .recording: .red
        case .overdubbing: .orange
        case .playing: .green
        case .empty, .stopped: .secondary
        }
    }

    private var status: String {
        switch looper.state {
        case .empty: "Looper"
        case .recording: "Recording"
        case .playing: String(format: "Loop %.1fs", looper.loopDuration)
        case .overdubbing: "Overdub"
        case .stopped: "Stopped"
        }
    }

    var body: some View {
        Button(action: looper.press) {
            VStack(spacing: 6) {
                Image(systemName: looper.state == .recording || looper.state == .overdubbing ? "record.circle.fill" : "repeat.circle")
                    .font(.system(size: 26, weight: .semibold))
                    .symbolEffect(.pulse, isActive: looper.state == .recording || looper.state == .overdubbing)
                Text(status).font(.caption.weight(.semibold)).lineLimit(1)
                Text(looper.state.nextActionTitle).font(.caption2).foregroundStyle(.secondary)
            }
            .foregroundStyle(looper.state == .empty || looper.state == .stopped ? Color.primary : tint)
            .frame(width: 112, height: 88)
            .glassEffect(looper.state == .empty || looper.state == .stopped
                         ? .regular.interactive() : .regular.tint(tint.opacity(0.3)).interactive(),
                         in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!looper.isReady)
        .accessibilityLabel("Looper, \(status)")
        .accessibilityHint("\(looper.state.nextActionTitle)")
        .help("L")
    }
}

// MARK: - Meters
// Reads the levels itself, so only the meters redraw ~20 times a second.

private struct PerformanceMeters: View {
    let engine: any PerformanceEngine

    var body: some View {
        HStack(spacing: 6) {
            PerformanceLevelMeter(level: engine.inputLevel, label: "IN", color: .green)
            PerformanceLevelMeter(level: engine.outputLevel, label: "OUT", color: .cyan)
        }
    }
}

struct PerformanceLevelMeter: View {
    let level: Float
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .bottom, endPoint: .top))
                        .frame(height: geometry.size.height * CGFloat(AudioMeter.normalized(level)))
                }
            }
            .frame(width: 14, height: 56)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement()
        .accessibilityLabel("\(label) level")
        .accessibilityValue(String(format: "%.0f decibels", AudioMeter.decibels(level)))
    }
}

// MARK: - Quick Preset Bar

struct QuickPresetBar: View {
    let presets: [EffectPreset]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(Array(presets.enumerated()), id: \.offset) { index, preset in
                            Button {
                                onSelect(index)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(index == currentIndex ? .white : preset.category.color)
                                    Text(preset.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(index == currentIndex ? .white : .primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .glassEffect(index == currentIndex ? .regular.tint(preset.category.color) : .regular,
                                             in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                }
            }
            .onChange(of: currentIndex) { _, index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Keyboard Shortcuts
// 1–9 stomp pedals · ← → presets · L looper · B bypass board · T tuner mute · Esc exit

private struct PerformanceKeyboardShortcuts: View {
    let engine: any PerformanceEngine
    let looper: any LooperControlling
    let controller: PerformanceModeController
    let onStepPreset: (Int) -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            ForEach(1...9, id: \.self) { number in
                Button("Pedal \(number)") {
                    let chain = engine.effectsChain
                    if chain.indices.contains(number - 1) { engine.toggleEffect(chain[number - 1]) }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: [])
            }
            Button("Previous Preset") { onStepPreset(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next Preset") { onStepPreset(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Looper") { looper.press() }.keyboardShortcut("l", modifiers: [])
            Button("Bypass Board") { controller.toggleBypassAll(engine: engine) }.keyboardShortcut("b", modifiers: [])
            Button("Tuner Mute") { engine.isTunerMuted.toggle() }.keyboardShortcut("t", modifiers: [])
            Button("Exit", action: onExit).keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: - Gesture Indicator Overlay

struct GestureIndicatorOverlay: View {
    let gestureController: any GestureControlling
    @Bindable var performanceController: PerformanceModeController

    var body: some View {
        VStack {
            HStack {
                Spacer()
                GlassCard(cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(gestureController.faceDetected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(gestureController.faceDetected ? "Face found" : "No face")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        GestureStatusRow(icon: "arrow.up.arrow.down", label: "Nod · preset",
                                         isActive: performanceController.lastTriggeredGesture == .headNodDown ||
                                                   performanceController.lastTriggeredGesture == .headNodUp)
                        GestureStatusRow(icon: "arrow.left.arrow.right", label: "Tilt · bypass / all on",
                                         isActive: performanceController.lastTriggeredGesture == .headTiltLeft ||
                                                   performanceController.lastTriggeredGesture == .headTiltRight)
                        HStack(spacing: 8) {
                            Image(systemName: "mouth.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.purple)
                                .frame(width: 16)
                            Text("Wah").font(.system(size: 11)).foregroundStyle(.secondary)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.1))
                                    Capsule().fill(Color.purple)
                                        .frame(width: geometry.size.width * CGFloat(performanceController.wahPosition))
                                }
                            }
                            .frame(width: 80, height: 8)
                        }
                        if let action = performanceController.lastTriggeredAction {
                            Label(action.rawValue, systemImage: action.icon)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }
                }
                .frame(width: 210)
            }
            Spacer()
        }
        .padding(.top, 76)
        .padding(.trailing, Spacing.xl)
        .allowsHitTesting(false)
    }
}

// MARK: - Gesture Status Row

struct GestureStatusRow: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? .green : .secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Circle()
                .fill(isActive ? Color.green : Color.white.opacity(0.1))
                .frame(width: 8, height: 8)
        }
    }
}
