import SwiftUI

// MARK: - Performance Mode View
// The board for playing live, laid out like a real one (see StagePedalboardView): a tuner
// first, patch cables, power leads, every pedal on screen and one tap to stomp it. The
// preset name is readable from across the room; the looper, tuner mute and a board-wide
// bypass sit along the bottom. Hardware keys, a MIDI foot controller and
// head gestures all drive the same controls.

struct PerformanceModeView: View {
    let engine: any PerformanceEngine
    let looper: any LooperControlling
    let tuner: any ChordDetecting
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
                StagePedalboardView(engine: engine, tuner: tuner)
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

// MARK: - Stompbox

/// The board's stompbox, scaled up – one tap stomps it, like on stage.
struct PerformanceStompbox: View {
    let effect: EffectNode
    let number: Int
    let scale: CGFloat
    let isBoardBypassed: Bool
    let onStomp: () -> Void

    private var isLive: Bool { effect.isEnabled && !isBoardBypassed }

    var body: some View {
        Button(action: onStomp) {
            StompboxView(effect: effect, isLive: isLive, scale: scale)
                // Its number, for the 1–9 keys – on the board just below the pedal
                .overlay(alignment: .bottom) {
                    if number <= 9 {
                        Text("\(number)")
                            .font(.system(size: 9 * scale, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .offset(y: 13 * scale)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(StompButtonStyle())
        .animation(.snappy(duration: 0.15), value: isLive)
        .accessibilityLabel("\(effect.model?.name ?? effect.type.rawValue), \(effect.type.rawValue), \(isLive ? "on" : "off")")
        .accessibilityHint("Stomps the pedal on or off")
        .help(number <= 9 ? "Press \(number)" : effect.type.rawValue)
    }
}

/// Presses down like a metal footswitch.
struct StompButtonStyle: ButtonStyle {
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
