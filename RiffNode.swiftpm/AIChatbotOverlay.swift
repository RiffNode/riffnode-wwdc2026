import SwiftUI
import Observation

// MARK: - Chat Message Model

/// Represents a single message in the AI chatbot conversation
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

/// Manages the AI chatbot conversation state
@Observable
@MainActor
final class AIChatbotController {

    // MARK: - State

    private(set) var messages: [ChatMessage] = []
    private(set) var isProcessing = false
    var inputText: String = ""

    // Suggested prompts for quick access
    let quickSuggestions = [
        "Make it heavy",
        "Add some ambience",
        "80s clean tone",
        "Blues crunch"
    ]

    // MARK: - Initialization

    init() {
        // Add welcome message
        messages.append(ChatMessage(
            role: .assistant,
            content: "Hey! I'm your tone assistant. Tell me what sound you're looking for - like \"make it heavy\" or \"add some ambient reverb\" - and I'll dial it in for you!"
        ))
    }

    // MARK: - Send Message

    /// Send a user message and get AI response
    func sendMessage(_ text: String, processor: SemanticCommandProcessor, engine: AudioEngineManager) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isProcessing = true

        // Process with SemanticCommandProcessor
        let success = await processor.processCommand(text)

        if success {
            // Create response with effect recommendations
            let response = ChatMessage(
                role: .assistant,
                content: processor.lastExplanation,
                appliedEffects: processor.lastEnabledEffects
            )
            messages.append(response)

            // Store the response index for later update when applied
            let responseIndex = messages.count - 1

            // Auto-apply after a brief delay for better UX
            try? await Task.sleep(for: .milliseconds(300))

            // Apply to engine
            processor.applyToEngine(engine)

            // Mark as applied
            if responseIndex < messages.count {
                messages[responseIndex].isApplied = true
            }
        } else {
            messages.append(ChatMessage(
                role: .assistant,
                content: "I couldn't quite understand that. Try something like \"warm blues tone\" or \"add more reverb\"."
            ))
        }

        isProcessing = false
    }

    /// Apply effects from a specific message
    func applyEffects(from message: ChatMessage, processor: SemanticCommandProcessor, engine: AudioEngineManager) {
        guard message.appliedEffects != nil else { return }

        processor.applyToEngine(engine)

        // Mark message as applied
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index].isApplied = true
        }
    }

    /// Clear conversation history
    func clearHistory() {
        messages = [ChatMessage(
            role: .assistant,
            content: "Conversation cleared. What tone are you looking for?"
        )]
    }
}

// MARK: - Chat Message Bubble

struct ChatMessageBubble: View {
    let message: ChatMessage
    let onApply: (() -> Void)?

    init(message: ChatMessage, onApply: (() -> Void)? = nil) {
        self.message = message
        self.onApply = onApply
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 50)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Message content
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(bubbleTint, in: RoundedRectangle(cornerRadius: 16))

                // Effect badges and apply button for AI responses
                if let effects = message.appliedEffects, !effects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        // Effect badges
                        HStack(spacing: 4) {
                            ForEach(effects.prefix(4), id: \.self) { effect in
                                EffectBadge(effectName: effect)
                            }
                            if effects.count > 4 {
                                Text("+\(effects.count - 4)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Apply button – tinted capsule glass
                        if !message.isApplied {
                            Button {
                                onApply?()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Apply")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 14)
                                .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.18)), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                Text("Applied")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                        }
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 50)
            }
        }
    }

    /// Glass tint for the bubble – user messages get an indigo tint,
    /// assistant messages get a purple tint.  Both render as proper
    /// Liquid Glass rather than flat colour fills.
    private var bubbleTint: Glass {
        if message.role == .user {
            return .regular.tint(Color.riffPrimary.opacity(0.2))
        } else {
            return .regular.tint(.purple.opacity(0.2))
        }
    }
}

// MARK: - Effect Badge

struct EffectBadge: View {
    let effectName: String

    var body: some View {
        Text(effectName.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(effectColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(effectColor.opacity(0.2)), in: Capsule())
    }

    private var effectColor: Color {
        switch effectName.lowercased() {
        case "reverb", "delay": return .riffAmbience
        case "distortion", "overdrive", "fuzz": return .riffGain
        case "chorus", "phaser", "flanger", "tremolo": return .riffModulation
        case "compressor": return .riffDynamics
        case "equalizer": return .riffFilter
        default: return .secondary
        }
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

    private let panelWidth: CGFloat = 380
    private let panelMaxHeight: CGFloat = 500
    private let minimizedHeight: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                // Chat panel
                VStack(spacing: 0) {
                    // Header
                    chatHeader

                    if !isMinimized {
                        // Messages
                        messagesScrollView

                        GlassDivider()

                        // Quick suggestions
                        quickSuggestionsBar

                        // Input field
                        inputBar
                    }
                }
                .frame(width: panelWidth)
                .frame(maxHeight: isMinimized ? minimizedHeight : panelMaxHeight)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity),
                    removal: .scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity)
                ))
            }

            // FAB
            AIChatbotFAB(isExpanded: isExpanded, hasNewMessage: false) {
                withAnimation(.spring(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.purple)

                Text("Tone Assistant")
                    .font(.headline)

                if controller.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                // Minimize button
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        isMinimized.toggle()
                    }
                } label: {
                    Image(systemName: isMinimized ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                // Close button
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
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
                LazyVStack(spacing: 12) {
                    ForEach(controller.messages) { message in
                        ChatMessageBubble(message: message) {
                            controller.applyEffects(from: message, processor: processor, engine: engine)
                        }
                        .id(message.id)
                    }

                    // Processing indicator
                    if controller.isProcessing {
                        HStack {
                            TypingIndicator()
                            Spacer()
                        }
                    }
                }
                .padding()
            }
            .onChange(of: controller.messages.count) { _, _ in
                if let lastMessage = controller.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Quick Suggestions

    private var quickSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(controller.quickSuggestions, id: \.self) { suggestion in
                        Button {
                            Task {
                                await controller.sendMessage(suggestion, processor: processor, engine: engine)
                            }
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .glassEffect(.regular, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isProcessing)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Describe your tone...", text: $controller.inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
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
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        controller.inputText.isEmpty || controller.isProcessing
                            ? .secondary
                            : Color.riffPrimary
                    )
            }
            .buttonStyle(.plain)
            .disabled(controller.inputText.isEmpty || controller.isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationPhase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.purple.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .offset(y: sin(animationPhase + Double(index) * 0.5) * 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.purple.opacity(0.15)), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }
}

// MARK: - AI Chatbot FAB (Floating Action Button)

struct AIChatbotFAB: View {
    let isExpanded: Bool
    let hasNewMessage: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Pure Liquid Glass circle – no colour tint
                Circle()
                    .fill(.clear)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular, in: Circle())

                // Icon – use .primary so it adapts to the glass backdrop
                Image(systemName: isExpanded ? "xmark" : "wand.and.stars")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)

                // New-message badge
                if hasNewMessage && !isExpanded {
                    Circle()
                        .fill(.red)
                        .frame(width: 12, height: 12)
                        .offset(x: 18, y: -18)
                }
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(isHovered ? 0.18 : 0.1), radius: isHovered ? 12 : 8, x: 0, y: 4)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .help("AI Tone Assistant")
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
