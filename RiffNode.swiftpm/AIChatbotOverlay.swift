import SwiftUI
import Observation

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    var appliedEffects: [String]?
    var isApplied: Bool = false

    enum Role {
        case user
        case assistant
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        appliedEffects: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.appliedEffects = appliedEffects
    }
}

// MARK: - AI Chatbot Controller

@Observable
@MainActor
final class AIChatbotController {

    private(set) var messages: [ChatMessage] = []
    private(set) var isProcessing = false
    var inputText: String = ""

    let quickSuggestions: [(icon: String, label: String)] = [
        ("bolt.fill",        "Heavy metal"),
        ("water.waves",      "Add reverb"),
        ("music.note",       "Jazz clean"),
        ("flame.fill",       "Blues crunch"),
        ("sparkles",         "80s chorus"),
        ("waveform",         "Warm lead"),
        ("moon.stars.fill",  "Ambient pad"),
        ("guitars.fill",     "Classic rock")
    ]

    init() {
        messages.append(ChatMessage(
            role: .assistant,
            content: "Hey! I'm your AI tone assistant. Tell me the sound you're after — like \"heavy metal riff\" or \"warm jazz clean\" — and I'll dial it in instantly."
        ))
    }

    func sendMessage(_ text: String, processor: SemanticCommandProcessor, engine: AudioEngineManager) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""
        isProcessing = true

        let success = await processor.processCommand(text)

        if success {
            let response = ChatMessage(
                role: .assistant,
                content: processor.lastExplanation,
                appliedEffects: processor.lastEnabledEffects
            )
            messages.append(response)

            let responseIndex = messages.count - 1
            try? await Task.sleep(for: .milliseconds(300))
            processor.applyToEngine(engine)

            if responseIndex < messages.count {
                messages[responseIndex].isApplied = true
            }
        } else {
            messages.append(ChatMessage(
                role: .assistant,
                content: "I didn't quite catch that. Try something like \"warm blues tone\" or \"more reverb and delay\"."
            ))
        }

        isProcessing = false
    }

    func applyEffects(from message: ChatMessage, processor: SemanticCommandProcessor, engine: AudioEngineManager) {
        guard message.appliedEffects != nil else { return }
        processor.applyToEngine(engine)
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index].isApplied = true
        }
    }

    func clearHistory() {
        messages = [ChatMessage(
            role: .assistant,
            content: "Fresh start! What tone are you going for?"
        )]
    }
}

// MARK: - AI Chatbot Overlay View

struct AIChatbotOverlayView: View {
    @Bindable var controller: AIChatbotController
    let processor: SemanticCommandProcessor
    let engine: AudioEngineManager
    @Binding var isExpanded: Bool

    @State private var isMinimized = false
    @FocusState private var inputFocused: Bool

    private let panelWidth: CGFloat = 390
    private let panelMaxHeight: CGFloat = 520

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if isExpanded {
                VStack(spacing: 0) {
                    chatHeader
                    if !isMinimized {
                        messagesScrollView
                        Divider().opacity(0.3)
                        quickSuggestionsBar
                        Divider().opacity(0.3)
                        inputBar
                    }
                }
                .frame(width: panelWidth)
                .frame(maxHeight: isMinimized ? 60 : panelMaxHeight)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity),
                    removal:   .scale(scale: 0.92, anchor: .bottomTrailing).combined(with: .opacity)
                ))
            }

            AIChatbotFAB(isExpanded: isExpanded) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 10) {
            // AI avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Tone Assistant")
                    .font(.system(size: 15, weight: .semibold))
                Text("Apple Intelligence")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if controller.isProcessing {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .tint(.purple)
            }

            Spacer()

            HStack(spacing: 4) {
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

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
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
                        ChatMessageBubble(message: message) {
                            controller.applyEffects(from: message, processor: processor, engine: engine)
                        }
                        .id(message.id)
                    }

                    if controller.isProcessing {
                        HStack(alignment: .bottom, spacing: 8) {
                            aiAvatarSmall
                            TypingIndicator()
                            Spacer()
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
        }
    }

    private var aiAvatarSmall: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 26, height: 26)
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
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
                                    colors: [Color.purple, Color.indigo],
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
    let onApply: (() -> Void)?

    @State private var showAppliedFlash = false

    init(message: ChatMessage, onApply: (() -> Void)? = nil) {
        self.message = message
        self.onApply = onApply
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 48)
            }

            if message.role == .assistant {
                // AI avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.purple.opacity(0.85), Color.indigo.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 26, height: 26)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
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

                // Effect badges + apply button
                if let effects = message.appliedEffects, !effects.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        // Badges
                        HStack(spacing: 4) {
                            ForEach(effects.prefix(5), id: \.self) { effect in
                                EffectBadge(effectName: effect)
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
                                Text("Applied to pedalboard")
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
                                HStack(spacing: 5) {
                                    Image(systemName: "wand.and.sparkles")
                                    Text("Apply to pedalboard")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 14)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [Color.purple, Color.indigo],
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
            ? .regular.tint(Color.indigo.opacity(0.22))
            : .regular.tint(Color.purple.opacity(0.12))
    }
}

// MARK: - Effect Badge

struct EffectBadge: View {
    let effectName: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: effectIcon)
                .font(.system(size: 8, weight: .bold))
            Text(effectName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(effectColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .glassEffect(.regular.tint(effectColor.opacity(0.18)), in: Capsule())
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
                    .fill(Color.purple.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .offset(y: CGFloat(sin(phase + Double(i) * 0.8)) * 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular.tint(.purple.opacity(0.12)), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Floating Action Button

struct AIChatbotFAB: View {
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Gradient fill when closed, glass when expanded
                if !isExpanded {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple, Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                } else {
                    Circle()
                        .fill(.clear)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular, in: Circle())
                }

                Image(systemName: isExpanded ? "xmark" : "wand.and.stars")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isExpanded ? Color.primary : Color.white)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .shadow(
            color: isExpanded ? .black.opacity(0.1) : .purple.opacity(0.4),
            radius: isHovered ? 14 : 8,
            x: 0, y: 4
        )
        .scaleEffect(isHovered ? 1.06 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .onHover { isHovered = $0 }
        .help("AI Tone Assistant")
        .accessibilityLabel(isExpanded ? "Close Tone Assistant" : "Open Tone Assistant")
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
