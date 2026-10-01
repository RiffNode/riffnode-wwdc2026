import SwiftUI
import Observation

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    var appliedEffects: [String]?
    var commandMode: String?  // "preset", "additive", "remove"
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
        appliedEffects: [String]? = nil,
        commandMode: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.appliedEffects = appliedEffects
        self.commandMode = commandMode
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
        ("guitars.fill",     "Classic rock"),
        ("waveform.path.ecg","Add fuzz"),
        ("clock.arrow.circlepath", "Add delay"),
        ("arrow.up.and.down.circle", "Add compressor"),
        ("speaker.wave.3",   "Surf rock")
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
            // For remove/additive/delete commands show what was affected
            let affectedEffects: [String]
            switch processor.lastCommandMode {
            case "remove":
                affectedEffects = processor.lastDisabledEffects
            case "delete":
                affectedEffects = processor.lastDeletedEffects
            default:
                affectedEffects = processor.lastEnabledEffects
            }

            let response = ChatMessage(
                role: .assistant,
                content: processor.lastExplanation,
                appliedEffects: affectedEffects.isEmpty ? nil : affectedEffects,
                commandMode: processor.lastCommandMode
            )
            messages.append(response)

            let responseIndex = messages.count - 1
            try? await Task.sleep(for: .milliseconds(300))
            processor.applyToEngine(engine)

            if responseIndex < messages.count {
                messages[responseIndex].isApplied = true
            }
        } else {
            let fallbackMsg = processor.lastExplanation.isEmpty
                ? "Try \"add reverb\", \"heavy metal\", \"more bass\", or \"remove delay\"."
                : processor.lastExplanation
            messages.append(ChatMessage(
                role: .assistant,
                content: fallbackMsg
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

    func clearHistory(processor: SemanticCommandProcessor? = nil) {
        processor?.resetConversation()
        messages = [ChatMessage(
            role: .assistant,
            content: "Fresh start! What tone are you going for?"
        )]
    }
}
