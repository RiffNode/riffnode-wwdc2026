import SwiftUI
import Observation

// MARK: - AI Chatbot Overlay View

struct AIChatbotOverlayView: View {
    @Bindable var controller: AIChatbotController
    let processor: SemanticCommandProcessor
    let engine: AudioEngineManager
    @Binding var isExpanded: Bool
    /// `.inspector` renders just the conversation, for the right-hand inspector column.
    var presentation: Presentation = .floating

    enum Presentation { case floating, inspector }

    @State private var isMinimized = false
    @FocusState private var inputFocused: Bool
    @Namespace private var glassNamespace

    // Drag-to-reposition state
    @State private var committedOffset: CGSize = .zero   // persisted after drag ends
    @State private var liveOffset: CGSize = .zero        // delta during active drag
    @State private var isDragging = false

    private var totalOffset: CGSize {
        CGSize(
            width:  committedOffset.width  + liveOffset.width,
            height: committedOffset.height + liveOffset.height
        )
    }

    private let panelWidth: CGFloat = 390
    private let panelMaxHeight: CGFloat = 520

    var body: some View {
        if presentation == .inspector {
            inspectorBody
        } else {
            floatingBody
        }
    }

    private var inspectorBody: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()
            messagesScrollView
            if controller.messages.count > 1 {
                Divider()
                quickSuggestionsBar
            }
            Divider()
            inputBar
        }
        .background(Color.riffBackground)
    }

    private var floatingBody: some View {
        // One container so the button and panel morph into each other as Liquid Glass
        GlassEffectContainer(spacing: 16) {
        VStack(alignment: .trailing, spacing: 12) {
            if isExpanded {
                VStack(spacing: 0) {
                    dragHandle
                    chatHeader
                    if !isMinimized {
                        messagesScrollView
                        // The starter cards already offer these on first open
                        if controller.messages.count > 1 {
                            Divider().opacity(0.3)
                            quickSuggestionsBar
                        }
                        Divider().opacity(0.3)
                        inputBar
                    }
                }
                .frame(width: panelWidth)
                .frame(maxHeight: isMinimized ? 84 : panelMaxHeight)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
                .glassEffectID("panel", in: glassNamespace)
                .shadow(
                    color: isDragging ? .black.opacity(0.38) : .black.opacity(0.25),
                    radius: isDragging ? 36 : 24,
                    x: 0,
                    y: isDragging ? 20 : 12
                )
                .scaleEffect(isDragging ? 1.018 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isDragging)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity),
                    removal:   .scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity)
                ))
            }

            AIChatbotFAB(
                isExpanded: isExpanded,
                isThinking: controller.isProcessing,
                usesAppleIntelligence: processor.isAvailable,
                namespace: glassNamespace
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        }
        }
        .offset(totalOffset)
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.secondary.opacity(isDragging ? 0.55 : 0.28))
                .frame(width: 38, height: 4)
                .animation(.easeInOut(duration: 0.15), value: isDragging)
            Spacer()
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    liveOffset = value.translation
                }
                .onEnded { value in
                    committedOffset = CGSize(
                        width:  committedOffset.width  + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    )
                    liveOffset = .zero
                    isDragging = false
                }
        )
        // Double-tap snaps back to original bottom-right corner
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                committedOffset = .zero
                liveOffset = .zero
            }
        }
        .help("Drag to move • Double-tap to reset position")
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 10) {
            AssistantAvatar(size: 34, usesAppleIntelligence: processor.isAvailable)

            VStack(alignment: .leading, spacing: 1) {
                Text("Tone Assistant")
                    .font(.system(size: 15, weight: .semibold))
                // Honest status: only claim Apple Intelligence when it is actually answering
                Text(processor.isAvailable ? "Apple Intelligence · on device" : "Offline tone matcher")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help(processor.unavailableReason ?? "Runs entirely on this device")
                if let reason = processor.unavailableReason {
                    Text(reason)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if controller.isProcessing {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.riffPrimary)
            }

            Spacer()

            HStack(spacing: 4) {
                if presentation == .floating {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isMinimized.toggle()
                    }
                } label: {
                    Image(systemName: isMinimized ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMinimized ? "Expand chat" : "Collapse chat")
                }

            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Messages

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(controller.messages) { message in
                        ChatMessageBubble(message: message, assistantUsesAppleIntelligence: processor.isAvailable) {
                            controller.applyEffects(from: message, processor: processor, engine: engine)
                        }
                        .id(message.id)
                    }

                    // First open: big, tappable starting points instead of empty space
                    if controller.messages.count == 1 && !controller.isProcessing {
                        starterCards
                            .transition(.opacity)
                    }

                    if controller.isProcessing {
                        HStack(alignment: .bottom, spacing: 8) {
                            aiAvatarSmall
                            if processor.thinkingSteps.isEmpty {
                                TypingIndicator()
                            } else {
                                ThinkingStepsView(steps: processor.thinkingSteps)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
                        .id("typing")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: controller.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(controller.messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: controller.isProcessing) { _, processing in
                if processing {
                    withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                }
            }
            .onChange(of: processor.thinkingSteps.count) { _, _ in
                withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
            }
        }
    }

    private var aiAvatarSmall: some View {
        AssistantAvatar(size: 26, usesAppleIntelligence: processor.isAvailable)
    }

    // MARK: - Starter Cards

    private var starterCards: some View {
        let starters: [(icon: String, title: String, detail: String, tint: Color)] = [
            ("bolt.fill", "Heavy metal", "Tight, high-gain riffs", Color.riffPrimary),
            ("music.note", "Jazz clean", "Warm and round", Color.riffPrimary),
            ("moon.stars.fill", "Ambient pad", "Huge reverb and echoes", Color.riffPrimary),
            ("flame.fill", "Blues crunch", "Edge-of-breakup drive", Color.riffPrimary)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Try one, or describe your own sound")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 34)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(starters, id: \.title) { starter in
                    Button {
                        Task { await controller.sendMessage(starter.title, processor: processor, engine: engine) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: starter.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(starter.tint)
                            Text(starter.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(starter.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .glassEffect(.regular.tint(starter.tint.opacity(0.08)).interactive(), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 34)
        }
        .padding(.top, 4)
    }

    // MARK: - Quick Suggestions

    private var quickSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(controller.quickSuggestions, id: \.label) { suggestion in
                    Button {
                        Task {
                            await controller.sendMessage(suggestion.label, processor: processor, engine: engine)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(suggestion.label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 11)
                        .glassEffect(.regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isProcessing)
                    .opacity(controller.isProcessing ? 0.5 : 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        let inputBinding = Binding<String>(
            get: { controller.inputText },
            set: { controller.inputText = $0 }
        )
        return HStack(spacing: 10) {
            TextField("Describe your tone...", text: inputBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...3)
                .focused($inputFocused)
                .onSubmit {
                    Task {
                        await controller.sendMessage(controller.inputText, processor: processor, engine: engine)
                    }
                }
                .disabled(controller.isProcessing)

            Button {
                Task {
                    await controller.sendMessage(controller.inputText, processor: processor, engine: engine)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            controller.inputText.isEmpty || controller.isProcessing
                                ? AnyShapeStyle(.quaternary)
                                : AnyShapeStyle(LinearGradient(
                                    colors: [Color.riffPrimary, Color.riffPrimary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(
                            controller.inputText.isEmpty || controller.isProcessing
                                ? Color.secondary
                                : Color.white
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(controller.inputText.isEmpty || controller.isProcessing)
            .animation(.easeInOut(duration: 0.15), value: controller.inputText.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Chat Message Bubble

struct ChatMessageBubble: View {
    let message: ChatMessage
    /// For messages without a recorded responder (the greeting): what's answering now.
    var assistantUsesAppleIntelligence = false
    let onApply: (() -> Void)?

    @State private var showAppliedFlash = false

    init(message: ChatMessage, assistantUsesAppleIntelligence: Bool = false, onApply: (() -> Void)? = nil) {
        self.message = message
        self.assistantUsesAppleIntelligence = assistantUsesAppleIntelligence
        self.onApply = onApply
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 48)
            }

            if message.role == .assistant {
                AssistantAvatar(
                    size: 26,
                    usesAppleIntelligence: message.responder.map { $0 == .appleIntelligence } ?? assistantUsesAppleIntelligence
                )
                    .alignmentGuide(.bottom) { d in d[.bottom] }
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Message text
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .glassEffect(bubbleTint, in: RoundedRectangle(cornerRadius: 18))

                // Which engine answered
                if let responder = message.responder {
                    Label(
                        responder == .appleIntelligence ? "Apple Intelligence" : "Offline tone matcher",
                        systemImage: responder == .appleIntelligence ? "apple.intelligence" : "bolt.fill"
                    )
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                }

                // Effect badges + apply button
                if let effects = message.appliedEffects, !effects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        // Mode label + badges
                        HStack(spacing: 6) {
                            if let mode = message.commandMode, mode != "preset" {
                                let label = mode == "remove" ? "BYPASSED" : mode == "delete" ? "DELETED" : mode == "set" ? "SET" : "ADDED"
                                let color: Color = (mode == "remove" || mode == "delete") ? .orange : .green
                                Text(label)
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(((mode == "remove" || mode == "delete") ? Color.orange : Color.green).opacity(0.15))
                                    )
                            }
                            ForEach(effects.prefix(5), id: \.self) { effect in
                                EffectBadge(
                                    effectName: effect,
                                    isRemoving: message.commandMode == "remove" || message.commandMode == "delete"
                                )
                            }
                            if effects.count > 5 {
                                Text("+\(effects.count - 5)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Apply / Applied state
                        if message.isApplied {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text({
                                    switch message.commandMode {
                                    case "remove":  return "Bypassed on pedalboard"
                                    case "delete":  return "Deleted from pedalboard"
                                    case "set":     return "Parameter updated"
                                    default:        return "Applied to pedalboard"
                                    }
                                }())
                                .foregroundStyle(.green)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        } else {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    showAppliedFlash = true
                                }
                                onApply?()
                            } label: {
                                let isDestructive = message.commandMode == "remove" || message.commandMode == "delete"
                                HStack(spacing: 5) {
                                    Image(systemName: {
                                        switch message.commandMode {
                                        case "delete": return "trash"
                                        case "remove": return "minus.circle"
                                        case "set":    return "slider.horizontal.3"
                                        default:       return "wand.and.sparkles"
                                        }
                                    }())
                                    Text({
                                        switch message.commandMode {
                                        case "delete": return "Delete from pedalboard"
                                        case "remove": return "Bypass effect"
                                        case "set":    return "Apply parameter"
                                        default:       return "Apply to pedalboard"
                                        }
                                    }())
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 14)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: isDestructive
                                                ? [Color.orange, Color.red.opacity(0.8)]
                                                : [Color.riffPrimary, Color.riffPrimary],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 48)
            }
        }
    }

    private var bubbleTint: Glass {
        message.role == .user
            ? .regular.tint(Color.riffPrimary.opacity(0.22))
            : .regular.tint(Color.riffPrimary.opacity(0.12))
    }
}

// MARK: - Effect Badge

struct EffectBadge: View {
    let effectName: String
    var isRemoving: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isRemoving ? "minus.circle" : effectIcon)
                .font(.system(size: 8, weight: .bold))
            Text(effectName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(isRemoving ? Color.orange : effectColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .glassEffect(.regular.tint((isRemoving ? Color.orange : effectColor).opacity(0.18)), in: Capsule())
    }

    private var effectColor: Color {
        switch effectName.lowercased() {
        case "reverb", "delay":                             return .riffAmbience
        case "distortion", "overdrive", "fuzz":            return .riffGain
        case "chorus", "phaser", "flanger", "tremolo":     return .riffModulation
        case "compressor":                                  return .riffDynamics
        case "equalizer":                                   return .riffFilter
        default:                                            return .secondary
        }
    }

    private var effectIcon: String {
        switch effectName.lowercased() {
        case "reverb":      return "water.waves"
        case "delay":       return "clock.arrow.circlepath"
        case "distortion":  return "bolt.fill"
        case "overdrive":   return "flame.fill"
        case "fuzz":        return "waveform.path.ecg"
        case "chorus":      return "sparkles"
        case "compressor":  return "arrow.up.and.down.circle"
        case "equalizer":   return "slider.horizontal.3"
        default:            return "music.note"
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.riffPrimary.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .offset(y: CGFloat(sin(phase + Double(i) * 0.8)) * 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.12)), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Assistant Avatar

/// The assistant's face: the Apple Intelligence glyph when the on-device model is answering,
/// a wand for the offline matcher – the same mark as the floating button.
struct AssistantAvatar: View {
    let size: CGFloat
    let usesAppleIntelligence: Bool

    var body: some View {
        Image(systemName: usesAppleIntelligence ? "apple.intelligence" : "wand.and.stars")
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [Color.riffPrimary, Color.riffPrimary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.12)), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Thinking Steps
// What the assistant is doing right now, built from the model's streamed output.

struct ThinkingStepsView: View {
    let steps: [SemanticCommandProcessor.ThinkingStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(steps) { step in
                HStack(spacing: 8) {
                    ZStack {
                        if step.isDone {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(Color.riffPrimary)
                        }
                    }
                    .font(.system(size: 12))
                    .frame(width: 14, height: 14)

                    Text(step.text)
                        .font(.system(size: 12, weight: step.isDone ? .regular : .semibold))
                        .foregroundStyle(step.isDone ? .secondary : .primary)
                        .contentTransition(.numericText())
                        .lineLimit(2)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.1)), in: RoundedRectangle(cornerRadius: 16))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: steps)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tone Assistant is working: " + (steps.last?.text ?? ""))
    }
}

// MARK: - Floating Action Button
// A labelled Liquid Glass capsule, so it reads as "Tone Assistant" rather than a mystery
// icon. It morphs into the chat panel, and shows a glowing ring while the AI is thinking.

struct AIChatbotFAB: View {
    let isExpanded: Bool
    let isThinking: Bool
    let usesAppleIntelligence: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false
    @State private var ringRotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        if isExpanded { return "xmark" }
        return usesAppleIntelligence ? "apple.intelligence" : "wand.and.stars"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isExpanded ? AnyShapeStyle(.secondary) : AnyShapeStyle(assistantGradient))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, options: .repeating, isActive: isThinking && !reduceMotion)

                if !isExpanded {
                    Text(isThinking ? "Thinking…" : "Tone Assistant")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.opacity)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .padding(.horizontal, isExpanded ? 0 : 18)
            .frame(width: isExpanded ? 48 : nil, height: 48)
            .contentShape(Capsule())
            .glassEffect(.regular.tint(Color.riffPrimary.opacity(isExpanded ? 0 : 0.18)).interactive(), in: Capsule())
            .glassEffectID("fab", in: namespace)
            // Apple Intelligence–style glow ring while the model works
            .overlay {
                if isThinking {
                    Capsule()
                        .strokeBorder(
                            AngularGradient(
                                colors: [Color.riffPrimary, Color.riffPrimary.opacity(0.15), Color.riffPrimary],
                                center: .center,
                                angle: .degrees(ringRotation)
                            ),
                            lineWidth: 2.5
                        )
                        .blur(radius: 0.5)
                        .transition(.opacity)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                ringRotation = 360
                            }
                        }
                        .onDisappear { ringRotation = 0 }
                }
            }
        }
        .buttonStyle(.plain)
        .shadow(color: Color.riffPrimary.opacity(isExpanded ? 0 : 0.25), radius: isHovered ? 14 : 8, y: 4)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .animation(.easeInOut(duration: 0.25), value: isThinking)
        .onHover { isHovered = $0 }
        .help("Tone Assistant (⌘J)")
        .accessibilityLabel(isExpanded ? "Close Tone Assistant" : "Open Tone Assistant")
        .accessibilityValue(isThinking ? "Thinking" : "")
    }

    private var assistantGradient: LinearGradient {
        LinearGradient(colors: [Color.riffPrimary, Color.riffPrimary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AdaptiveBackground()
        VStack {
            Spacer()
            HStack {
                Spacer()
                AIChatbotOverlayView(
                    controller: AIChatbotController(),
                    processor: SemanticCommandProcessor(),
                    engine: AudioEngineManager(),
                    isExpanded: .constant(true)
                )
                .padding()
            }
        }
    }
}
