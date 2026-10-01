import Accelerate
import AVFoundation
import SwiftUI

// MARK: - Chord Detector View

struct ChordDetectorView: View {
    let detector: ChordDetector

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .foregroundStyle(.yellow)
                    Text("CHORD DETECTION")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }

                Spacer()

                // Confidence meter
                HStack(spacing: 4) {
                    Text("AI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    ConfidenceMeter(confidence: detector.confidence)
                }
            }

            // Main display
            HStack(spacing: 24) {
                // Note display
                VStack(spacing: 4) {
                    Text(detector.detectedNote)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(detector.isInTune ? .green : .white)

                    Text(detector.fullNoteName)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 100)

                // Tuning indicator
                TuningIndicator(cents: detector.centsDeviation)

                // Chord display
                VStack(spacing: 4) {
                    Text(detector.detectedChord)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.yellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    // Active notes
                    HStack(spacing: 4) {
                        ForEach(detector.activeNotes, id: \.self) { note in
                            Text(note)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Frequency display
            HStack {
                Text(String(format: "%.1f Hz", detector.detectedPitch))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                // Tuning status
                HStack(spacing: 4) {
                    Circle()
                        .fill(detector.isInTune ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(detector.isInTune ? "In Tune" : tuningDirection)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .glassEffect(.regular.tint(.yellow.opacity(0.1)), in: RoundedRectangle(cornerRadius: 12))
    }

    private var tuningDirection: String {
        if detector.centsDeviation > 10 {
            return "Sharp (\(Int(detector.centsDeviation))¢)"
        } else if detector.centsDeviation < -10 {
            return "Flat (\(Int(detector.centsDeviation))¢)"
        }
        return "—"
    }
}

// MARK: - Confidence Meter

struct ConfidenceMeter: View {
    let confidence: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Rectangle()
                    .fill(i < Int(confidence * 5) ? Color.green : Color.white.opacity(0.2))
                    .frame(width: 4, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
    }
}

// MARK: - Tuning Indicator

struct TuningIndicator: View {
    let cents: Float

    var body: some View {
        VStack(spacing: 4) {
            // Visual tuner
            GeometryReader { geometry in
                let width = geometry.size.width
                let center = width / 2
                let offset = CGFloat(cents / 50) * (width / 2 - 10)

                ZStack {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)

                    // Center marker
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: 2, height: 16)
                        .position(x: center, y: geometry.size.height / 2)

                    // Current pitch indicator
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 12, height: 12)
                        .position(x: center + offset, y: geometry.size.height / 2)
                        .shadow(color: indicatorColor.opacity(0.5), radius: 4)
                }
            }
            .frame(width: 80, height: 20)

            // Labels
            HStack {
                Text("♭")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("♯")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80)
        }
    }

    private var indicatorColor: Color {
        let absCents = abs(cents)
        if absCents < 10 {
            return .green
        } else if absCents < 25 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Compact Chord Badge (for top bar)
// Liquid Glass UI Design - iOS 26+

struct CompactChordBadge: View {
    let detector: ChordDetector

    private var hasChord: Bool {
        !detector.detectedChord.isEmpty && detector.detectedChord != "—"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Chord icon
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.purple)
                .symbolEffect(.pulse, options: .repeating, isActive: !hasChord)

            // Detected chord
            VStack(alignment: .leading, spacing: 2) {
                Text("Detected Chord")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(hasChord ? detector.detectedChord : "Listening… strum a chord")
                    .font(.system(size: hasChord ? 16 : 13, weight: hasChord ? .bold : .medium))
                    .foregroundStyle(hasChord ? .primary : .secondary)
                    .contentTransition(.opacity)
            }

            Spacer()

            // Confidence indicator – only meaningful once something is detected
            if hasChord {
                Text(String(format: "%.0f%%", detector.confidence * 100))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.purple)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .animation(.smooth(duration: 0.2), value: hasChord)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var previewDetector = ChordDetector()
    VStack(spacing: 20) {
        ChordDetectorView(detector: previewDetector)
        CompactChordBadge(detector: previewDetector)
    }
    .padding()
    .background(Color.black)
}
