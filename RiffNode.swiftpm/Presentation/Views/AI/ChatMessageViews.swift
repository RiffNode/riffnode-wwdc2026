import SwiftUI
import Observation
import PhotosUI

// MARK: - Chat Message Views

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
                    .font(.system(.subheadline))
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
                        // Mode label + badges – whole badges wrap to the next line, never their words
                        FlowLayout(spacing: 6) {
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
                            .font(.system(.caption2, weight: .medium))
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
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 14)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: isDestructive
                                                ? [Color.orange, Color.red.opacity(0.8)]
                                                : [Color.purple, Color.indigo],
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

struct EffectBadge: View {
    let effectName: String
    var isRemoving: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isRemoving ? "minus.circle" : effectIcon)
                .font(.system(size: 8, weight: .bold))
            Text(effectName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
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

struct TypingIndicator: View {
    @State private var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

/// The assistant's face: the Apple Intelligence glyph when the on-device model is answering,
/// a wand for the offline matcher – the same mark as the floating button.
struct AssistantAvatar: View {
    let size: CGFloat
    let usesAppleIntelligence: Bool

    var body: some View {
        Image(systemName: usesAppleIntelligence ? "apple.intelligence" : "wand.and.stars")
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(.purple.opacity(0.12)), in: Circle())
            .accessibilityHidden(true)
    }
}

struct ThinkingStepsView: View {
    let steps: [AssistantThinkingStep]

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
                                .tint(.purple)
                        }
                    }
                    .font(.system(.caption))
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
        .glassEffect(.regular.tint(.purple.opacity(0.1)), in: RoundedRectangle(cornerRadius: 16))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: steps)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tone Assistant is working: " + (steps.last?.text ?? ""))
    }
}
