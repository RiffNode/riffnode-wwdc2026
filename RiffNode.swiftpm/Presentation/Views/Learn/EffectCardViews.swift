import SwiftUI

// MARK: - Effect Cards

struct GlassEffectCardView: View {
    let effect: EffectInfoModel
    let isExpanded: Bool
    var justAdded: Bool = false
    var engine: (any LearnEngine)? = nil
    let onTap: () -> Void
    var onTryEffect: ((EffectType) -> Void)? = nil

    var body: some View {
        GlassCard(cornerRadius: 12, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Header - clean, minimal design
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        // Color dot for the effect category
                        Circle()
                            .fill(effect.color.opacity(0.8))
                            .frame(width: 8, height: 8)

                        Text(effect.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        // "Try It" badge if effect is in the app
                        if let effectType = effect.effectType, onTryEffect != nil {
                            if justAdded {
                                Label("Added!", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Text(effectType.abbreviation)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(effect.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .glassEffect(.regular.tint(effect.color.opacity(0.15)), in: Capsule())
                            }
                        }

                        Text(isExpanded ? "Less" : "More")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }
                .buttonStyle(.plain)

                if isExpanded {
                    GlassEffectCardDetails(
                        effect: effect,
                        engine: engine,
                        onTryEffect: onTryEffect
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(duration: 0.3), value: isExpanded)
        .animation(.spring(duration: 0.3), value: justAdded)
    }
}

struct GlassEffectCardDetails: View {
    let effect: EffectInfoModel
    var engine: (any LearnEngine)? = nil
    var onTryEffect: ((EffectType) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Divider - subtle
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 16) {
                // Hear it first – sound before reading
                if let effectType = effect.effectType, let engine {
                    EffectAuditionPanel(type: effectType, tint: effect.color, engine: engine)
                }

                // What It Does
                GlassEffectInfoSection(
                    title: "What It Does",
                    content: effect.function
                )

                // The Sound
                GlassEffectInfoSection(
                    title: "The Sound",
                    content: effect.sound
                )

                // How To Use
                GlassEffectTipsSection(
                    title: "How To Use",
                    content: effect.howToUse
                )

                // Signal Chain Position
                GlassEffectSignalChainSection(
                    position: effect.signalChainPosition
                )

                // Famous Artists
                GlassEffectArtistsSection(
                    artists: effect.famousUsers
                )

                // Try on Pedalboard - only for effects available in the app
                if let effectType = effect.effectType, let tryAction = onTryEffect {
                    Button {
                        tryAction(effectType)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(.caption, weight: .semibold))
                            Text("Add to Pedalboard")
                                .font(.system(.footnote, weight: .semibold))
                        }
                        .foregroundStyle(effect.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(effect.color.opacity(0.15)), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

struct GlassEffectInfoSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GlassEffectTipsSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct GlassEffectSignalChainSection: View {
    let position: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SIGNAL CHAIN")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            // Visual signal chain indicator
            HStack(spacing: 4) {
                Text("IN")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)

                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == getPositionIndex() ? Color.primary.opacity(0.6) : Color.primary.opacity(0.15))
                        .frame(width: 20, height: 8)
                }

                Text("OUT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)

                Spacer()
            }

            Text(position)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func getPositionIndex() -> Int {
        let lowercased = position.lowercased()
        if lowercased.contains("first") || lowercased.contains("beginning") || lowercased.contains("front") {
            return 0
        } else if lowercased.contains("early") || lowercased.contains("after compressor") {
            return 1
        } else if lowercased.contains("middle") {
            return 2
        } else if lowercased.contains("late") || lowercased.contains("before reverb") {
            return 3
        } else if lowercased.contains("end") || lowercased.contains("last") {
            return 4
        }
        return 2
    }
}

struct GlassEffectArtistsSection: View {
    let artists: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FAMOUS USERS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            let artistList = artists.components(separatedBy: ", ")
            FlowLayout(spacing: 6) {
                ForEach(artistList, id: \.self) { artist in
                    Text(artist)
                        .font(.system(.caption2, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: Capsule())
                }
            }
        }
    }
}
