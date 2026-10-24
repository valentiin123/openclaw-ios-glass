import SwiftUI
import UIKit

// Decor for Agents board tiles: pixel bubbles, "Zz", the clockwise progress outline.
// Everything is drawn with Canvas / Path (no bitmap assets).

// MARK: - Pixel canvas

/// Draws a character grid (legend of `AgentTilePalette.color(for:)`). Decorative: hidden from VoiceOver.
struct AgentTilePixelCanvas: View {
    let rows: [String]
    let palette: AgentTilePalette

    private var aspect: CGFloat {
        let rowCount: Int = rows.count
        let columnCount: Int = rows.first?.count ?? 0
        guard rowCount > 0, columnCount > 0 else { return 1 }
        return CGFloat(columnCount) / CGFloat(rowCount)
    }

    var body: some View {
        Canvas { context, size in
            Self.draw(rows: self.rows, palette: self.palette, context: &context, size: size)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static func draw(
        rows: [String],
        palette: AgentTilePalette,
        context: inout GraphicsContext,
        size: CGSize)
    {
        let rowCount: Int = rows.count
        guard rowCount > 0 else { return }
        let columnCount: Int = rows[0].count
        guard columnCount > 0 else { return }
        let cellWidth: CGFloat = size.width / CGFloat(columnCount)
        let cellHeight: CGFloat = size.height / CGFloat(rowCount)
        let cell: CGFloat = min(cellWidth, cellHeight)
        let originX: CGFloat = (size.width - cell * CGFloat(columnCount)) / 2
        let originY: CGFloat = (size.height - cell * CGFloat(rowCount)) / 2
        let side: CGFloat = cell + 0.35
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, pixel) in row.enumerated() {
                guard let color = palette.color(for: pixel) else { continue }
                let x: CGFloat = originX + CGFloat(columnIndex) * cell
                let y: CGFloat = originY + CGFloat(rowIndex) * cell
                let rect: CGRect = CGRect(x: x, y: y, width: side, height: side)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}

// MARK: - Bubbles

enum AgentTileBubbleKind: Equatable, Sendable {
    case speech
    case thought
    case alert
    case sleep
}

enum AgentTileDecorArt {
    // Legend: w white fill, k ink outline, c accent dots.
    static let speech: [String] = [
        ".kkkkkkk.",
        "kwwwwwwwk",
        "kwcwcwcwk",
        "kwwwwwwwk",
        ".kkkkkkk.",
        "..kk.....",
        "...k.....",
    ]

    static let thought: [String] = [
        "..kkkkk..",
        ".kwwwwwk.",
        "kwcwcwcwk",
        ".kwwwwwk.",
        "..kkkkk..",
        "..kk.....",
        ".k.......",
    ]

    static let alert: [String] = [
        ".kkkkkkk.",
        "kwwwcwwwk",
        "kwwwcwwwk",
        "kwwwcwwwk",
        "kwwwwwwwk",
        "kwwwcwwwk",
        ".kkkkkkk.",
        "..kk.....",
        "...k.....",
    ]

    // Legend: a = secondary label colour.
    static let sleep: [String] = [
        "......aaa",
        ".......a.",
        "......aaa",
        ".........",
        "..aaa....",
        "...a.....",
        "..aaa....",
        ".........",
    ]
}

extension AgentTilePalette {
    static let bubble: AgentTilePalette = AgentTilePalette(
        body: AgentTilePalette.white,
        shade: AgentTilePalette.ink,
        accent: OpenClawBrand.carapaceCoral)

    static let sleep: AgentTilePalette = AgentTilePalette(
        body: Color(uiColor: UIColor.secondaryLabel),
        shade: Color(uiColor: UIColor.secondaryLabel),
        accent: Color(uiColor: UIColor.secondaryLabel))
}

struct AgentTileBubbleView: View {
    let kind: AgentTileBubbleKind

    private var rows: [String] {
        switch self.kind {
        case .speech: AgentTileDecorArt.speech
        case .thought: AgentTileDecorArt.thought
        case .alert: AgentTileDecorArt.alert
        case .sleep: AgentTileDecorArt.sleep
        }
    }

    private var palette: AgentTilePalette {
        if self.kind == .sleep { return AgentTilePalette.sleep }
        return AgentTilePalette.bubble
    }

    var body: some View {
        AgentTilePixelCanvas(rows: self.rows, palette: self.palette)
    }
}

// MARK: - Outline starting at top centre, clockwise

/// Rounded rectangle whose path starts at the middle of the top edge and runs clockwise,
/// so `trim` grows the stroke clockwise from 12 o'clock. Corners are cubic curves
/// (no arc direction ambiguity). Also used as the tile surface so both match exactly.
struct AgentTileOutline: Shape {
    var cornerRadius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box: CGRect = rect.insetBy(dx: self.inset, dy: self.inset)
        let radius: CGFloat = min(self.cornerRadius, min(box.width, box.height) / 2)
        let reach: CGFloat = radius * 0.5523
        let topMid: CGPoint = CGPoint(x: box.midX, y: box.minY)
        let topRightStart: CGPoint = CGPoint(x: box.maxX - radius, y: box.minY)
        let rightTop: CGPoint = CGPoint(x: box.maxX, y: box.minY + radius)
        let rightBottom: CGPoint = CGPoint(x: box.maxX, y: box.maxY - radius)
        let bottomRight: CGPoint = CGPoint(x: box.maxX - radius, y: box.maxY)
        let bottomLeft: CGPoint = CGPoint(x: box.minX + radius, y: box.maxY)
        let leftBottom: CGPoint = CGPoint(x: box.minX, y: box.maxY - radius)
        let leftTop: CGPoint = CGPoint(x: box.minX, y: box.minY + radius)
        let topLeft: CGPoint = CGPoint(x: box.minX + radius, y: box.minY)

        var path: Path = Path()
        path.move(to: topMid)
        path.addLine(to: topRightStart)
        path.addCurve(
            to: rightTop,
            control1: CGPoint(x: topRightStart.x + reach, y: topRightStart.y),
            control2: CGPoint(x: rightTop.x, y: rightTop.y - reach))
        path.addLine(to: rightBottom)
        path.addCurve(
            to: bottomRight,
            control1: CGPoint(x: rightBottom.x, y: rightBottom.y + reach),
            control2: CGPoint(x: bottomRight.x + reach, y: bottomRight.y))
        path.addLine(to: bottomLeft)
        path.addCurve(
            to: leftBottom,
            control1: CGPoint(x: bottomLeft.x - reach, y: bottomLeft.y),
            control2: CGPoint(x: leftBottom.x, y: leftBottom.y + reach))
        path.addLine(to: leftTop)
        path.addCurve(
            to: topLeft,
            control1: CGPoint(x: leftTop.x, y: leftTop.y - reach),
            control2: CGPoint(x: topLeft.x - reach, y: topLeft.y))
        path.addLine(to: topMid)
        return path
    }
}

// MARK: - Progress ring

/// Orange stroke going around the tile clockwise from the top centre.
/// Known progress -> determinate arc. Unknown progress while active -> a short segment looping around
/// (replaced by a faint static outline under Reduce Motion).
struct AgentTileProgressRing: View {
    let progress: Double?
    let isActive: Bool
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lineWidth: CGFloat = 2.5
    private let segment: Double = 0.22
    private let period: Double = 2.4

    var body: some View {
        self.content
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let value = self.progress {
            self.arc(0, min(max(value, 0), 1))
        } else if self.isActive, self.reduceMotion {
            self.arc(0, 1).opacity(0.25)
        } else if self.isActive {
            TimelineView(.animation) { context in
                self.moving(at: context.date)
            }
        }
    }

    @ViewBuilder
    private func moving(at date: Date) -> some View {
        let seconds: Double = date.timeIntervalSinceReferenceDate
        let phase: Double = seconds.truncatingRemainder(dividingBy: self.period) / self.period
        let end: Double = phase + self.segment
        ZStack {
            self.arc(phase, min(end, 1))
            if end > 1 {
                self.arc(0, end - 1)
            }
        }
    }

    private func arc(_ start: Double, _ end: Double) -> some View {
        let shape: AgentTileOutline = AgentTileOutline(
            cornerRadius: self.cornerRadius,
            inset: self.lineWidth / 2)
        let style: StrokeStyle = StrokeStyle(lineWidth: self.lineWidth, lineCap: .round)
        return shape
            .trim(from: start, to: end)
            .stroke(OpenClawBrand.carapaceCoral, style: style)
    }
}
