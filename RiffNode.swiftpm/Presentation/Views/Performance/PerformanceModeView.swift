import SwiftUI

// MARK: - Performance Mode View

/// Fullscreen pedalboard view for stage use with gesture control
struct PerformanceModeView: View {
    @Bindable var engine: AudioEngineManager
    @Bindable var gestureController: VisionGestureController
    @Bindable var controller: PerformanceModeController
    let presets: [EffectPreset]
    let onExit: () -> Void

    @State private var showGestureOverlay = true
    @State private var selectedEffect: EffectNode?

    var body: some View {
        ZStack {
            // Background
            AdaptiveBackground()

            VStack(spacing: 0) {
                // Top bar
                performanceTopBar

                Spacer()

                // Main pedal chain
                performancePedalChain

                Spacer()

                // Bottom bar with presets and meters
                performanceBottomBar
            }

            // Gesture indicator overlay
            if showGestureOverlay && gestureController.isRunning {
                GestureIndicatorOverlay(
                    gestureController: gestureController,
                    performanceController: controller
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            controller.activate()
            setupGestureCallbacks()
        }
        .onDisappear {
            controller.deactivate()
        }
    }

    // MARK: - Top Bar

    private var performanceTopBar: some View {
        GlassEffectContainer(spacing: 16) {
            HStack {
                // Exit button – capsule glass
                Button {
                    onExit()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text("Exit")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Mode title
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.expand.vertical")
                        .foregroundStyle(.orange)
                    Text("PERFORMANCE MODE")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(.orange.opacity(0.15)), in: Capsule())

                Spacer()

                // Gesture toggle – capsule glass
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        showGestureOverlay.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: gestureController.isRunning ? "hand.raised.fill" : "hand.raised.slash")
                        Text(gestureController.isRunning ? "CV On" : "CV Off")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(gestureController.isRunning ? .green : .secondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, 60)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Pedal Chain

    private var performancePedalChain: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // Input jack
                PerformanceJackView(label: "IN", isInput: true)
                PerformanceConnectorView()

                // Effects pedals
                ForEach(engine.effectsChain) { effect in
                    PerformancePedalView(
                        effect: effect,
                        isSelected: selectedEffect?.id == effect.id,
                        onTap: {
                            withAnimation(.spring(duration: 0.2)) {
                                selectedEffect = effect
                            }
                        },
                        onDoubleTap: {
                            engine.toggleEffect(effect)
                        }
                    )
                    PerformanceConnectorView()
                }

                // Output jack
                PerformanceJackView(label: "OUT", isInput: false)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        // Pedalboard surface background
        .background(
            ZStack {
                // Dark wood/carpet texture base
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.1, blue: 0.08),
                                Color(red: 0.08, green: 0.06, blue: 0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Subtle grip texture pattern
                GeometryReader { geometry in
                    Canvas { context, size in
                        for y in stride(from: 0, to: size.height, by: 8) {
                            for x in stride(from: 0, to: size.width, by: 8) {
                                let rect = CGRect(x: x, y: y, width: 2, height: 2)
                                context.fill(
                                    Circle().path(in: rect),
                                    with: .color(.white.opacity(0.015))
                                )
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))

                // Edge highlight
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(white: 0.25),
                                Color(white: 0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )
            }
            .padding(.horizontal, Spacing.md)
        )
    }

    // MARK: - Bottom Bar

    private var performanceBottomBar: some View {
        HStack(spacing: Spacing.lg) {
            // Input meter
            PerformanceLevelMeter(
                level: engine.inputLevel,
                label: "IN",
                color: .green
            )

            // Quick presets
            QuickPresetBar(
                presets: presets,
                currentIndex: controller.currentPresetIndex,
                onSelect: { index in
                    controller.currentPresetIndex = index
                    if index < presets.count {
                        engine.applyPreset(presets[index])
                    }
                }
            )

            // Output meter
            PerformanceLevelMeter(
                level: engine.outputLevel,
                label: "OUT",
                color: .cyan
            )
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .padding(.bottom, 40)
    }

    // MARK: - Setup Gesture Callbacks

    private func setupGestureCallbacks() {
        gestureController.onGestureDetected = { [controller, engine] gesture in
            controller.handleGesture(gesture, engine: engine, presets: presets)
        }

        gestureController.onMouthOpenValueChanged = { [controller, engine] value in
            controller.updateWahPosition(value, engine: engine)
        }
    }
}

// MARK: - Performance Pedal View (Large)
// Stage-ready pedal design with realistic hardware look

struct PerformancePedalView: View {
    let effect: EffectNode
    var isSelected: Bool = false
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 14) {
            // LED indicator with enhanced glow
            ZStack {
                // Outer ambient glow
                Circle()
                    .fill(effect.isEnabled ? Color.green.opacity(0.5) : .clear)
                    .frame(width: 32, height: 32)
                    .blur(radius: 12)

                // Inner bright glow
                Circle()
                    .fill(effect.isEnabled ? Color.green.opacity(0.8) : .clear)
                    .frame(width: 18, height: 18)
                    .blur(radius: 4)

                // LED housing ring
                Circle()
                    .strokeBorder(Color(white: 0.3), lineWidth: 2)
                    .frame(width: 20, height: 20)

                // LED dot
                Circle()
                    .fill(effect.isEnabled ? Color.green : Color(white: 0.25))
                    .frame(width: 14, height: 14)
                    .shadow(color: effect.isEnabled ? .green : .clear, radius: 10)
            }

            // Effect icon - larger with subtle glow when enabled
            ZStack {
                if effect.isEnabled {
                    Image(systemName: effect.type.icon)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(effect.type.color.opacity(0.4))
                        .blur(radius: 8)
                }

                Image(systemName: effect.type.icon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(effect.isEnabled ? effect.type.color : Color(white: 0.45))
            }

            // Effect name
            VStack(spacing: 6) {
                Text(effect.type.abbreviation)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(effect.isEnabled ? .white : Color(white: 0.55))

                Text(effect.type.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.4))
                    .lineLimit(1)
            }

            // Footswitch indicator - realistic stomp button
            ZStack {
                // Switch housing
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.25), Color(white: 0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 50, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(white: 0.35), lineWidth: 1)
                    )

                // Status text
                Text(effect.isEnabled ? "ON" : "BYPASS")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(effect.isEnabled ? .green : .orange)
            }
        }
        .frame(width: 160, height: 220)
        // Dark metallic pedal enclosure
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        // Metallic edge highlight
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(white: 0.4),
                            Color(white: 0.2),
                            Color(white: 0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
        )
        // Subtle color tint when enabled
        .overlay {
            if effect.isEnabled {
                RoundedRectangle(cornerRadius: 20)
                    .fill(effect.type.color.opacity(0.08))
            }
        }
        // Selected state ring
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(effect.type.color, lineWidth: 3)
                    .shadow(color: effect.type.color.opacity(0.6), radius: 15)
            }
        }
        // Drop shadow for depth
        .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 8)
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .animation(.spring(duration: 0.2), value: isHovering)
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Performance Jack View
// Realistic 1/4" jack connector visualization

struct PerformanceJackView: View {
    let label: String
    let isInput: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Jack housing - dark metallic box
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.2), Color(white: 0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color(white: 0.35), Color(white: 0.15)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )

                VStack(spacing: 8) {
                    // Jack plate
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(white: 0.35), Color(white: 0.2)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 20
                            )
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            // Jack hole
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.black, Color(white: 0.15)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 12
                                    )
                                )
                                .frame(width: 24, height: 24)
                        )
                        .overlay(
                            // Metal rim
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color(white: 0.5), Color(white: 0.25)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )

                    // Signal indicator LED
                    Circle()
                        .fill(isInput ? Color.green : Color.cyan)
                        .frame(width: 8, height: 8)
                        .shadow(color: isInput ? .green.opacity(0.6) : .cyan.opacity(0.6), radius: 6)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

            // Label
            Text(label)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(isInput ? .green : .cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(white: 0.15))
                )
        }
    }
}

// MARK: - Performance Connector View
// Realistic patch cable visualization

struct PerformanceConnectorView: View {
    @State private var signalPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Cable body
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.25), Color(white: 0.15), Color(white: 0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 50, height: 8)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)

            // Cable highlights
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.08))
                .frame(width: 46, height: 2)
                .offset(y: -2)

            // Signal flow indicator
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.cyan, .cyan.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 10, height: 10)
                .offset(x: signalPhase)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        signalPhase = 20
                    }
                }
        }
    }
}

// MARK: - Performance Level Meter

struct PerformanceLevelMeter: View {
    let level: Float
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            // Vertical meter
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))

                    // Level
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.6), color],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: geometry.size.height * CGFloat(level))
                }
            }
            .frame(width: 20, height: 100)

            // Label
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            // dB value
            Text(String(format: "%.0fdB", 20 * log10(max(level, 0.001))))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Quick Preset Bar

struct QuickPresetBar: View {
    let presets: [EffectPreset]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(Array(presets.prefix(8).enumerated()), id: \.offset) { index, preset in
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .glassEffect(
                                index == currentIndex
                                    ? .regular.tint(preset.category.color)
                                    : .regular,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Gesture Indicator Overlay

struct GestureIndicatorOverlay: View {
    @Bindable var gestureController: VisionGestureController
    @Bindable var performanceController: PerformanceModeController

    var body: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                // Gesture status panel
                GlassCard(cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header
                        HStack(spacing: 8) {
                            Image(systemName: "eye.fill")
                                .foregroundStyle(.purple)
                            Text("CV CONTROL")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }

                        GlassDivider()

                        // Face status
                        HStack(spacing: 8) {
                            Circle()
                                .fill(gestureController.faceDetected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(gestureController.faceDetected ? "Face Detected" : "No Face")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        // Gesture indicators
                        VStack(alignment: .leading, spacing: 8) {
                            GestureStatusRow(
                                icon: "arrow.down",
                                label: "Nod",
                                isActive: performanceController.lastTriggeredGesture == .headNodDown ||
                                         performanceController.lastTriggeredGesture == .headNodUp
                            )

                            GestureStatusRow(
                                icon: "arrow.left.arrow.right",
                                label: "Tilt",
                                isActive: performanceController.lastTriggeredGesture == .headTiltLeft ||
                                         performanceController.lastTriggeredGesture == .headTiltRight
                            )

                            // Wah meter
                            HStack(spacing: 8) {
                                Image(systemName: "mouth.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.purple)
                                    .frame(width: 16)

                                Text("Wah")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .leading)

                                // Wah position bar
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white.opacity(0.1))

                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.purple)
                                            .frame(width: geometry.size.width * CGFloat(performanceController.wahPosition))
                                    }
                                }
                                .frame(width: 80, height: 8)
                            }
                        }

                        // Last action
                        if let action = performanceController.lastTriggeredAction {
                            HStack(spacing: 6) {
                                Image(systemName: action.icon)
                                    .foregroundStyle(.green)
                                Text(action.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular.tint(.green.opacity(0.2)), in: Capsule())
                        }
                    }
                }
                .frame(width: 200)
                .padding(Spacing.lg)
            }
        }
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
                .frame(width: 40, alignment: .leading)

            Circle()
                .fill(isActive ? Color.green : Color.white.opacity(0.1))
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Preview

#Preview {
    PerformanceModeView(
        engine: AudioEngineManager(),
        gestureController: VisionGestureController(),
        controller: PerformanceModeController(),
        presets: [],
        onExit: {}
    )
}
