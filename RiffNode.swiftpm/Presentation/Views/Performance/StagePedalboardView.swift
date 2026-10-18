import SwiftUI

// MARK: - Stage Pedalboard
// Stage Mode's board, laid out like a real one:
//  • The signal runs right to left – the guitar plugs in on the right, the amp on the left –
//    because pedals take their input on the right side and send it out on the left.
//  • A tuner comes first: stomp it and the output mutes while you tune.
//  • Short patch cables with right-angle plugs join each pedal to the next; a cable from the
//    end of one row dives under the board and comes back up at the start of the next.
//  • The power brick is mounted under the rails; each pedal's 9 V lead comes up through the
//    gap behind it into the DC jack on top.
//  • The surface is aluminium rails with gaps between them, so cables can run underneath.

struct StagePedalboardView: View {
    let engine: any PerformanceEngine
    let tuner: any ChordDetecting

    private static let rowGap: CGFloat = 34
    private static let pedalGap: CGFloat = 26
    private static let margin = EdgeInsets(top: 34, leading: 78, bottom: 30, trailing: 78)

    var body: some View {
        GeometryReader { geo in
            let items = boardItems
            let plan = Self.plan(items.map(\.size), in: geo.size)
            ZStack(alignment: .topLeading) {
                BoardSurface()

                // Cables sit on the rails, under the pedals
                Canvas { context, _ in
                    drawPowerLeads(context, frames: plan.frames)
                    drawPatchCables(context, frames: plan.frames, rows: plan.rows, size: geo.size)
                }
                .allowsHitTesting(false)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let frame = plan.frames[index]
                    pedal(item, number: index, scale: plan.scale)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }

                // Plug heads sit over the pedals' side jacks
                Canvas { context, _ in drawPlugs(context, frames: plan.frames, scale: plan.scale) }
                    .allowsHitTesting(false)

                powerBrick(scale: plan.scale)
                    .position(x: geo.size.width - 78, y: geo.size.height - 18)
                jackLabel("GUITAR IN", alignment: .trailing)
                    .position(x: geo.size.width - 36, y: plan.frames.first.map { $0.minY + $0.height * 0.3 - 18 } ?? 40)
                jackLabel("TO AMP", alignment: .leading)
                    .position(x: 36, y: plan.frames.last.map { $0.minY + $0.height * 0.3 - 18 } ?? 40)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: Items

    private enum Item: Identifiable {
        case tuner
        case pedal(EffectNode)

        var id: String {
            switch self {
            case .tuner: "tuner"
            case .pedal(let effect): effect.id.uuidString
            }
        }

        var size: CGSize {
            switch self {
            case .tuner: StompboxView.size(for: .mini)
            case .pedal(let effect): StompboxView.size(for: effect.model?.look.shape ?? .classic)
            }
        }
    }

    private var boardItems: [Item] { [.tuner] + engine.effectsChain.map(Item.pedal) }

    @ViewBuilder
    private func pedal(_ item: Item, number: Int, scale: CGFloat) -> some View {
        switch item {
        case .tuner:
            TunerPedal(detector: tuner, isMuted: engine.isTunerMuted, scale: scale) {
                engine.isTunerMuted.toggle()
            }
        case .pedal(let effect):
            PerformanceStompbox(effect: effect, number: number, scale: scale,
                                isBoardBypassed: engine.isPedalboardBypassed) {
                engine.toggleEffect(effect)
            }
        }
    }

    // MARK: Layout

    struct Plan {
        var scale: CGFloat
        var rows: [[Int]]
        var frames: [CGRect]
    }

    /// Splits the chain into rows (right to left), scaled as large as the board allows.
    static func plan(_ sizes: [CGSize], in board: CGSize) -> Plan {
        let usableWidth = board.width - margin.leading - margin.trailing
        let usableHeight = board.height - margin.top - margin.bottom
        var best = Plan(scale: 0.3, rows: [Array(sizes.indices)], frames: [])
        for rowCount in 1...min(4, max(1, sizes.count)) {
            let rows = balancedRows(sizes.map(\.width), count: rowCount)
            let widest = rows.map { row in row.reduce(0) { $0 + sizes[$1].width } + CGFloat(row.count - 1) * pedalGap }.max() ?? 1
            let tallest = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }.reduce(0, +)
            let scale = min(usableWidth / widest,
                            (usableHeight - CGFloat(rowCount - 1) * rowGap) / max(tallest, 1),
                            2.0)
            if scale > best.scale { best = Plan(scale: scale, rows: rows, frames: []) }
        }
        // Place each row right to left, rows top to bottom, pedals standing on a common line
        var frames = Array(repeating: CGRect.zero, count: sizes.count)
        let rowHeights = best.rows.map { row in (row.map { sizes[$0].height }.max() ?? 0) * best.scale }
        let totalHeight = rowHeights.reduce(0, +) + CGFloat(best.rows.count - 1) * rowGap
        var y = margin.top + max(0, (usableHeight - totalHeight) / 2)
        for (r, row) in best.rows.enumerated() {
            let rowWidth = row.reduce(0) { $0 + sizes[$1].width * best.scale } + CGFloat(row.count - 1) * pedalGap
            var x = board.width - margin.trailing - max(0, (usableWidth - rowWidth) / 2)
            for index in row {
                let w = sizes[index].width * best.scale, h = sizes[index].height * best.scale
                frames[index] = CGRect(x: x - w, y: y + rowHeights[r] - h, width: w, height: h)
                x -= w + pedalGap
            }
            y += rowHeights[r] + rowGap
        }
        best.frames = frames
        return best
    }

    /// Consecutive runs of roughly equal width.
    private static func balancedRows(_ widths: [CGFloat], count: Int) -> [[Int]] {
        let total = widths.reduce(0, +)
        var rows: [[Int]] = [[]]
        var running: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if !rows[rows.count - 1].isEmpty && running + width / 2 > total * CGFloat(rows.count) / CGFloat(count) && rows.count < count {
                rows.append([])
            }
            rows[rows.count - 1].append(index)
            running += width
        }
        return rows
    }

    // MARK: Cables

    /// Input jack (right side) and output jack (left side), a third of the way down.
    private func inputJack(_ f: CGRect) -> CGPoint { CGPoint(x: f.maxX, y: f.minY + f.height * 0.3) }
    private func outputJack(_ f: CGRect) -> CGPoint { CGPoint(x: f.minX, y: f.minY + f.height * 0.3) }

    private func drawPatchCables(_ context: GraphicsContext, frames: [CGRect], rows: [[Int]], size: CGSize) {
        guard let first = frames.first, let last = frames.last else { return }
        let cable = Color(white: 0.07)
        let width: CGFloat = 5

        // Guitar cable in from the right edge
        let start = inputJack(first)
        var guitar = Path()
        guitar.move(to: CGPoint(x: size.width + 10, y: start.y + 30))
        guitar.addCurve(to: CGPoint(x: start.x + 14, y: start.y),
                        control1: CGPoint(x: size.width - 20, y: start.y + 30), control2: CGPoint(x: start.x + 40, y: start.y))
        stroke(context, guitar, cable, width + 1)

        for index in 0..<(frames.count - 1) {
            let from = outputJack(frames[index]), to = inputJack(frames[index + 1])
            var path = Path()
            path.move(to: CGPoint(x: from.x - 14, y: from.y))
            if to.x < from.x {
                // Same row: a short loop that sags between the two pedals
                let sag = max(18, (from.x - to.x) * 0.6)
                path.addCurve(to: CGPoint(x: to.x + 14, y: to.y),
                              control1: CGPoint(x: from.x - 14 - sag * 0.4, y: from.y + sag),
                              control2: CGPoint(x: to.x + 14 + sag * 0.4, y: to.y + sag))
                stroke(context, path, cable, width)
            } else {
                // Next row: dive into the gap under the rails, come back up at the row's start
                let gapY = frames[index].maxY + Self.rowGap / 2
                path.addCurve(to: CGPoint(x: from.x - 30, y: gapY),
                              control1: CGPoint(x: from.x - 40, y: from.y), control2: CGPoint(x: from.x - 40, y: gapY - 10))
                stroke(context, path, cable, width)
                var under = Path()
                under.move(to: CGPoint(x: from.x - 30, y: gapY))
                under.addLine(to: CGPoint(x: to.x + 30, y: gapY))
                context.stroke(under, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [2, 9]))
                var up = Path()
                up.move(to: CGPoint(x: to.x + 30, y: gapY))
                up.addCurve(to: CGPoint(x: to.x + 14, y: to.y),
                            control1: CGPoint(x: to.x + 44, y: gapY), control2: CGPoint(x: to.x + 40, y: to.y))
                stroke(context, up, cable, width)
            }
        }

        // Out to the amp on the left edge
        let end = outputJack(last)
        var amp = Path()
        amp.move(to: CGPoint(x: end.x - 14, y: end.y))
        amp.addCurve(to: CGPoint(x: -10, y: end.y + 30),
                     control1: CGPoint(x: end.x - 40, y: end.y), control2: CGPoint(x: 20, y: end.y + 30))
        stroke(context, amp, cable, width + 1)
    }

    /// A cable with a faint highlight along its top, so it reads as round.
    private func stroke(_ context: GraphicsContext, _ path: Path, _ color: Color, _ width: CGFloat) {
        context.stroke(path, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: width + 2, lineCap: .round))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        context.stroke(path.offsetBy(dx: 0, dy: -width * 0.22), with: .color(.white.opacity(0.13)),
                       style: StrokeStyle(lineWidth: width * 0.3, lineCap: .round))
    }

    /// Each pedal's 9 V lead rises out of the rail gap behind it into the DC jack on top.
    private func drawPowerLeads(_ context: GraphicsContext, frames: [CGRect]) {
        for frame in frames {
            let jack = CGPoint(x: frame.midX, y: frame.minY + 2)
            var lead = Path()
            lead.move(to: CGPoint(x: jack.x + 14, y: frame.minY - 16))
            lead.addCurve(to: jack, control1: CGPoint(x: jack.x + 14, y: jack.y - 6), control2: CGPoint(x: jack.x, y: jack.y - 10))
            context.stroke(lead, with: .color(Color(white: 0.12)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            // Where it comes up through the gap
            context.fill(Path(ellipseIn: CGRect(x: jack.x + 10, y: frame.minY - 19, width: 8, height: 5)),
                         with: .color(.black.opacity(0.7)))
        }
    }

    /// Right-angle plugs: a metal barrel at each side jack, the DC plug on top.
    private func drawPlugs(_ context: GraphicsContext, frames: [CGRect], scale: CGFloat) {
        let barrel = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color(white: 0.85), Color(white: 0.45)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: 10))
        for frame in frames {
            for (jack, outward) in [(inputJack(frame), CGFloat(1)), (outputJack(frame), CGFloat(-1))] {
                let head = CGRect(x: outward > 0 ? jack.x - 1 : jack.x - 15, y: jack.y - 6, width: 16, height: 12)
                context.fill(Path(roundedRect: head, cornerRadius: 3), with: barrel)
                context.stroke(Path(roundedRect: head, cornerRadius: 3), with: .color(.black.opacity(0.5)), lineWidth: 0.8)
            }
            let dc = CGRect(x: frame.midX - 5, y: frame.minY - 5, width: 10, height: 9)
            context.fill(Path(roundedRect: dc, cornerRadius: 2), with: .color(Color(white: 0.15)))
        }
    }

    // MARK: Hardware

    private func powerBrick(scale: CGFloat) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.green).frame(width: 5, height: 5).shadow(color: .green, radius: 3)
            Text("9V · ISOLATED")
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color(white: 0.75))
            ForEach(0..<6, id: \.self) { _ in
                Circle().fill(Color.black).frame(width: 5, height: 5)
                    .overlay(Circle().strokeBorder(Color(white: 0.4), lineWidth: 0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(white: 0.25), lineWidth: 0.8))
        .accessibilityHidden(true)
    }

    private func jackLabel(_ text: String, alignment: HorizontalAlignment) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundStyle(Color(white: 0.55))
            .accessibilityHidden(true)
    }
}

// MARK: - Board Surface

/// Anodised aluminium rails with dark gaps between them, like the boards players velcro
/// their pedals to.
private struct BoardSurface: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.04)))
            let rail: CGFloat = 46, gap: CGFloat = 12
            var y: CGFloat = 8
            while y < size.height {
                let rect = CGRect(x: 0, y: y, width: size.width, height: rail)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [Color(white: 0.19), Color(white: 0.12), Color(white: 0.15)]),
                    startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
                // Brushed-metal grain
                var grain = Path()
                var x: CGFloat = 0
                while x < size.width {
                    grain.move(to: CGPoint(x: x, y: rect.minY + 3)); grain.addLine(to: CGPoint(x: x + 40, y: rect.minY + 3))
                    x += 61
                }
                context.stroke(grain, with: .color(.white.opacity(0.05)), lineWidth: 1)
                context.fill(Path(CGRect(x: 0, y: rect.minY, width: size.width, height: 1)), with: .color(.white.opacity(0.1)))
                y += rail + gap
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(white: 0.3), lineWidth: 2))
    }
}

// MARK: - Tuner Pedal

/// The first pedal on every board: a tuner that mutes the signal while it's on.
private struct TunerPedal: View {
    let detector: any ChordDetecting
    let isMuted: Bool
    let scale: CGFloat
    let onStomp: () -> Void

    private var hasNote: Bool { detector.detectedNote != "—" && !detector.detectedNote.isEmpty }
    private var colour: Color {
        guard hasNote else { return Color(white: 0.4) }
        return detector.isInTune ? .green : (abs(detector.centsDeviation) < 20 ? .yellow : .red)
    }

    var body: some View {
        let size = StompboxView.size(for: .mini)
        Button(action: onStomp) {
            VStack(spacing: 6 * scale) {
                // The display
                VStack(spacing: 3 * scale) {
                    Text(hasNote ? detector.detectedNote : "–")
                        .font(.system(size: 22 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(colour)
                        .shadow(color: colour.opacity(0.6), radius: 4 * scale)
                        .contentTransition(.numericText())
                    GeometryReader { geo in
                        let x = geo.size.width / 2 + CGFloat(max(-50, min(50, detector.centsDeviation)) / 50) * geo.size.width / 2
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(white: 0.2))
                            Capsule().fill(colour).frame(width: 3 * scale).offset(x: x - 1.5 * scale)
                        }
                    }
                    .frame(height: 4 * scale)
                }
                .padding(6 * scale)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 4 * scale).fill(Color.black))
                .padding(.horizontal, 7 * scale)
                .padding(.top, 9 * scale)

                Text("TUNER")
                    .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(white: 0.9))
                Text(isMuted ? "MUTED" : "LIVE")
                    .font(.system(size: 6.5 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(isMuted ? .red : Color(white: 0.6))
                Spacer(minLength: 0)
                Circle()
                    .fill(isMuted ? Color.red : Color(white: 0.25))
                    .frame(width: 7 * scale, height: 7 * scale)
                    .shadow(color: isMuted ? .red : .clear, radius: 4 * scale)
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 22 * scale, height: 22 * scale)
                    .padding(.bottom, 9 * scale)
            }
            .frame(width: size.width * scale, height: size.height * scale)
            .background(RoundedRectangle(cornerRadius: 9 * scale)
                .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.17)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 9 * scale).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 6 * scale, y: 3 * scale)
        }
        .buttonStyle(StompButtonStyle())
        .accessibilityLabel(hasNote ? "Tuner, \(detector.detectedNote)" : "Tuner")
        .accessibilityValue(isMuted ? "Muted" : "Live")
        .accessibilityHint("Stomp to mute the output while you tune")
        .help("T")
    }
}
