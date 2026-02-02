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
        HStack {
            // Exit button
            Button {
                onExit()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text("Exit")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
            .glassEffect(.regular, in: Capsule())

            Spacer()

            // Gesture toggle
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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
            }
            .buttonStyle(.plain)
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
        }
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

struct PerformancePedalView: View {
    let effect: EffectNode
    var isSelected: Bool = false
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 12) {
            // LED indicator with larger glow
            ZStack {
                Circle()
                    .fill(effect.isEnabled ? Color.green.opacity(0.4) : .clear)
                    .frame(width: 24, height: 24)
                    .blur(radius: 8)

                Circle()
                    .fill(effect.isEnabled ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 16, height: 16)
                    .shadow(color: effect.isEnabled ? .green.opacity(0.8) : .clear, radius: 8)
            }

            // Effect icon - larger
            Image(systemName: effect.type.icon)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(effect.isEnabled ? effect.type.color : .secondary)

            // Effect name - larger
            VStack(spacing: 4) {
                Text(effect.type.abbreviation)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(effect.isEnabled ? .primary : .secondary)

                Text(effect.type.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            // Status indicator
            Text(effect.isEnabled ? "ON" : "BYPASS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(effect.isEnabled ? .green : .orange)
        }
        .frame(width: 150, height: 200)
        .glassEffect(
            effect.isEnabled ? .regular.tint(effect.type.color) : .regular,
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(effect.type.color, lineWidth: 3)
                    .shadow(color: effect.type.color.opacity(0.5), radius: 12)
            }
        }
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(duration: 0.2), value: isHovering)
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Performance Jack View

struct PerformanceJackView: View {
    let label: String
    let isInput: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Jack housing
                Color.clear
                    .frame(width: 60, height: 80)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))

                // Jack hole
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.black.opacity(0.8), Color.gray.opacity(0.3)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 16
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.gray.opacity(0.5), lineWidth: 3)
                    }
            }

            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(isInput ? .green : .cyan)
        }
    }
}

// MARK: - Performance Connector View

struct PerformanceConnectorView: View {
    var body: some View {
        ZStack {
            // Connection line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.1), .white.opacity(0.25), .white.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 40, height: 4)

            // Signal dot
            Circle()
                .fill(.cyan.opacity(0.5))
                .frame(width: 6, height: 6)
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
                        .background(
                            index == currentIndex
                                ? preset.category.color
                                : Color.clear
                        )
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
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
                        .background(Color.green.opacity(0.2))
                        .clipShape(Capsule())
                    }
                }
                .padding(16)
                .frame(width: 200)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
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
