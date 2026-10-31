import SwiftUI

/// A matrix-style rain veil shown over the file area while a batch runs.
/// Decorative only: it never intercepts clicks and is hidden from VoiceOver.
struct MatrixOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glyphs: [Character] = {
        let kana = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ"
        let ascii = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ@#$%&*+=<>"
        return Array(kana) + Array(ascii)
    }()
    private static let glyphColor = Color(red: 0.18, green: 0.85, blue: 0.78).opacity(0.8)
    private static let scrimTop = Color(red: 0.05, green: 0.10, blue: 0.19).opacity(0.90)
    private static let scrimBottom = Color(red: 0.05, green: 0.28, blue: 0.33).opacity(0.84)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                draw(
                    context: &context,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let rect = CGRect(origin: .zero, size: size)
        let gradient = Gradient(colors: [Self.scrimTop, Self.scrimBottom])
        let shading: GraphicsContext.Shading = .linearGradient(
            gradient,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: size.height)
        )
        context.fill(Path(rect), with: shading)
        guard size.width > 0, size.height > 0 else { return }

        let columnWidth: CGFloat = 26
        let columns: Int = max(1, Int(size.width / columnWidth))
        let rowHeight: CGFloat = 15
        let font: Font = .system(size: 11, weight: .medium, design: .monospaced)
        let glyphCount: Int = Self.glyphs.count

        for column in 0..<columns {
            let seed: Int = Self.seed(column)
            let x: CGFloat = (CGFloat(column) + 0.5) * size.width / CGFloat(columns)
            let speed: CGFloat = (28 + CGFloat(seed % 42)) * 1.69
            let trail: Int = 7 + seed % 9
            let cycle: CGFloat = size.height + CGFloat(trail) * rowHeight + rowHeight
            let offset: CGFloat = CGFloat(seed % 120) * rowHeight
            let head: Double = (time * Double(speed) + Double(offset))
                .truncatingRemainder(dividingBy: Double(cycle))

            for step in 0..<trail {
                var y: CGFloat = CGFloat(head) - CGFloat(step) * rowHeight
                y = y.truncatingRemainder(dividingBy: cycle)
                if y < 0 {
                    y += cycle
                }
                guard y >= -rowHeight, y <= size.height + rowHeight else { continue }

                let fade: Double = 1 - Double(step) / Double(trail)
                let glyphIndex: Int = (seed + step + Int(time * 10)) % glyphCount
                let character: Character = Self.glyphs[glyphIndex]
                let glyph = Text(String(character))
                    .font(font)
                    .foregroundColor(Self.glyphColor.opacity(fade))
                context.draw(glyph, at: CGPoint(x: x, y: y))
            }
        }
    }

    private static func seed(_ column: Int) -> Int {
        var value = UInt(bitPattern: column) &* 1_103_515_245 &+ 12_345
        value ^= value >> 13
        return Int(value % 10_000)
    }
}
