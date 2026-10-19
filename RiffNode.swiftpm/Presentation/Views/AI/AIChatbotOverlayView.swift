import SwiftUI
import Observation
import PhotosUI

// MARK: - AI Chatbot Overlay View

struct AIChatbotOverlayView: View {
    @State private var photoItem: PhotosPickerItem?
    @Bindable var controller: AIChatbotController
    let processor: any ToneAssisting
    let engine: any EffectsChainManaging
    @Binding var isExpanded: Bool

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
                    .font(.system(.subheadline, weight: .semibold))
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
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMinimized ? "Expand chat" : "Collapse chat")

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
            ("bolt.fill", "Heavy metal", "Tight, high-gain riffs", .red),
            ("music.note", "Jazz clean", "Warm and round", .blue),
            ("moon.stars.fill", "Ambient pad", "Huge reverb and echoes", .purple),
            ("flame.fill", "Blues crunch", "Edge-of-breakup drive", .orange)
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
                                .font(.system(.callout, weight: .semibold))
                                .foregroundStyle(starter.tint)
                            Text(starter.title)
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(starter.detail)
                                .font(.system(.caption2))
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
                                .font(.system(.caption, weight: .medium))
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

    // MARK: - Photo

    /// Saves the picked photo to a temporary file and asks the assistant about it.
    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-photo-\(UUID().uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return }
        await controller.sendPhoto(at: url, processor: processor, engine: engine)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        let inputBinding = Binding<String>(
            get: { controller.inputText },
            set: { controller.inputText = $0 }
        )
        return HStack(spacing: 10) {
            // OS 27: Apple Intelligence can look at a photo and suggest the sound it evokes
            if processor.canReadImages {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(.subheadline, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(controller.isProcessing)
                .accessibilityLabel("Tone from a photo")
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task { await sendPhoto(item) }
                }
            }
            TextField("Describe your tone...", text: inputBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.subheadline))
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
                        .font(.system(.footnote, weight: .bold))
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
                    processor: AppDependencies.live().toneAssistant,
                    engine: AppDependencies.live().engine,
                    isExpanded: .constant(true)
                )
                .padding()
            }
        }
    }
}
