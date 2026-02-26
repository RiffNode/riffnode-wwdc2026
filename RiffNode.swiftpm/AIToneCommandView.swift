import SwiftUI

// MARK: - AI Tone Command View
// Liquid Glass UI for natural language tone control
// Uses Foundation Models on iOS 26+ with graceful fallback

struct AIToneCommandView: View {
    @Bindable var processor: SemanticCommandProcessor
    @Bindable var engine: AudioEngineManager

    @State private var commandText = ""
    @State private var showResult = false

    // Quick command suggestions
    private let suggestions = [
        "Make it spacey and ambient",
        "Heavy metal crunch",
        "Clean with subtle reverb",
        "80s chorus sound",
        "Warm vintage blues"
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple)
                Text("AI Tone Assistant")
                    .font(.headline)

                Spacer()

                if processor.isAvailable {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("On-Device AI")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text("Smart Presets")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Text input
            HStack(spacing: 12) {
                TextField("Describe your tone...", text: $commandText)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    Task {
                        await processCommand()
                    }
                } label: {
                    Group {
                        if processor.isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                    }
                    .foregroundStyle(.purple)
                    .frame(width: 36, height: 36)
                }
                .disabled(commandText.isEmpty || processor.isProcessing)
                .buttonStyle(.plain)
            }

            // Quick suggestions – fuse into one morphing glass group
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                commandText = suggestion
                                Task {
                                    await processCommand()
                                }
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .glassEffect(.regular, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Result display
            if !processor.lastExplanation.isEmpty && showResult {
                VStack(alignment: .leading, spacing: 12) {
                    // Explanation
                    Text(processor.lastExplanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Show enabled effects
                    if !processor.lastEnabledEffects.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(processor.lastEnabledEffects, id: \.self) { effect in
                                    Text(effect.capitalized)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .foregroundStyle(.purple)
                                        .glassEffect(.regular.tint(.purple.opacity(0.15)), in: Capsule())
                                }
                            }
                        }
                    }

                    // Apply button – tinted capsule glass
                    Button {
                        processor.applyToEngine(engine)
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Apply This Tone")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .glassEffect(.regular.tint(Color.riffPrimary.opacity(0.18)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // Error display
            if let error = processor.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func processCommand() async {
        guard !commandText.isEmpty else { return }

        withAnimation(.spring(duration: 0.3)) {
            showResult = false
        }

        let success = await processor.processCommand(commandText)

        if success {
            withAnimation(.spring(duration: 0.4)) {
                showResult = true
            }
        }
    }
}

// MARK: - Compact AI Tone Badge (for header bar)

struct CompactAIToneBadge: View {
    @Bindable var processor: SemanticCommandProcessor
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.purple)

                Text("AI Tone")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if processor.isProcessing {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule())
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var processor = SemanticCommandProcessor()
    @Previewable @State var engine = AudioEngineManager()

    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        AIToneCommandView(processor: processor, engine: engine)
            .padding()
    }
}
