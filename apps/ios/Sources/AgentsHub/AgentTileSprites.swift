import SwiftUI

// Pixel-art sprites for the Agents board. Drawn with Canvas from character grids (no bitmap assets).
// Grid legend: `.` transparent, `a` body, `b` shade, `c` accent, `w` white, `k` ink.
// Every sprite is a 10 x 10 grid.

enum AgentTileSpriteKind: Int, CaseIterable, Sendable {
    case robot
    case cat
    case owl
    case ghost
    case mushroom
    case crystal
    case frog
    case alien

    var rows: [String] {
        switch self {
        case .robot: AgentTileSpriteArt.robot
        case .cat: AgentTileSpriteArt.cat
        case .owl: AgentTileSpriteArt.owl
        case .ghost: AgentTileSpriteArt.ghost
        case .mushroom: AgentTileSpriteArt.mushroom
        case .crystal: AgentTileSpriteArt.crystal
        case .frog: AgentTileSpriteArt.frog
        case .alien: AgentTileSpriteArt.alien
        }
    }

    var palette: AgentTilePalette {
        switch self {
        case .robot: AgentTilePalette.robot
        case .cat: AgentTilePalette.cat
        case .owl: AgentTilePalette.owl
        case .ghost: AgentTilePalette.ghost
        case .mushroom: AgentTilePalette.mushroom
        case .crystal: AgentTilePalette.crystal
        case .frog: AgentTilePalette.frog
        case .alien: AgentTilePalette.alien
        }
    }
}

enum AgentTileSpriteArt {
    static let robot: [String] = [
        "....cc....",
        "....bb....",
        "..aaaaaa..",
        ".aaaaaaaa.",
        ".awwaawwa.",
        ".awkaawka.",
        ".aaaaaaaa.",
        ".abbbbbba.",
        "..aaaaaa..",
        "..b....b..",
    ]

    static let cat: [String] = [
        ".a......a.",
        ".aa....aa.",
        ".aaaaaaaa.",
        ".aaaaaaaa.",
        ".akaaaaka.",
        ".aaaccaaa.",
        ".aaaaaaaa.",
        "..aaaaaa..",
        "..aaaaaa..",
        "..bb..bb..",
    ]

    static let owl: [String] = [
        ".b......b.",
        ".bbbbbbbb.",
        ".baaaaaab.",
        ".bwwbbwwb.",
        ".bwkaakwb.",
        ".baaccaab.",
        ".baaaaaab.",
        ".baabbaab.",
        "..bbbbbb..",
        "..c....c..",
    ]

    static let ghost: [String] = [
        "..aaaaaa..",
        ".aaaaaaaa.",
        ".aaaaaaaa.",
        ".awwaawwa.",
        ".awkaawka.",
        ".aaaaaaaa.",
        ".aaaccaaa.",
        ".aaaaaaaa.",
        ".aaaaaaaa.",
        ".aa.aa.aa.",
    ]

    static let mushroom: [String] = [
        "...cccc...",
        "..cccwcc..",
        ".cwcccwcc.",
        ".cccccccc.",
        "..bbbbbb..",
        "...aaaa...",
        "...kaak...",
        "...aaaa...",
        "...aaaa...",
        "..bbbbbb..",
    ]

    static let crystal: [String] = [
        "....cc....",
        "...cwcc...",
        "..cwccbc..",
        ".cwcccccb.",
        ".ccccccbb.",
        ".cccccbbb.",
        "..ccccbb..",
        "...cccb...",
        "....cb....",
        "....b.....",
    ]

    static let frog: [String] = [
        ".aa....aa.",
        "awwa..awwa",
        "awkaaaakwa",
        ".aaaaaaaa.",
        ".aaaaaaaa.",
        ".akkkkkka.",
        ".aaccccaa.",
        ".aaaaaaaa.",
        "..aa..aa..",
        ".aaa..aaa.",
    ]

    static let alien: [String] = [
        "..aaaaaa..",
        ".aaaaaaaa.",
        "aaaaaaaaaa",
        "aakkaakkaa",
        "aakkaakkaa",
        ".aaaaaaaa.",
        "..aaccaa..",
        "...aaaa...",
        "....aa....",
        "....bb....",
    ]
}

struct AgentTilePalette: Sendable {
    let body: Color
    let shade: Color
    let accent: Color

    static let white: Color = Color(red: 0.97, green: 0.97, blue: 0.99)
    static let ink: Color = Color(red: 0.11, green: 0.11, blue: 0.14)

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red, green: green, blue: blue)
    }

    static let robot: AgentTilePalette = AgentTilePalette(
        body: rgb(0.62, 0.70, 0.80),
        shade: rgb(0.38, 0.46, 0.58),
        accent: rgb(0.96, 0.40, 0.29))

    static let cat: AgentTilePalette = AgentTilePalette(
        body: rgb(0.95, 0.62, 0.30),
        shade: rgb(0.75, 0.42, 0.18),
        accent: rgb(0.98, 0.55, 0.62))

    static let owl: AgentTilePalette = AgentTilePalette(
        body: rgb(0.65, 0.48, 0.32),
        shade: rgb(0.42, 0.29, 0.18),
        accent: rgb(0.98, 0.78, 0.25))

    static let ghost: AgentTilePalette = AgentTilePalette(
        body: rgb(0.88, 0.90, 0.98),
        shade: rgb(0.60, 0.64, 0.80),
        accent: rgb(0.98, 0.60, 0.70))

    static let mushroom: AgentTilePalette = AgentTilePalette(
        body: rgb(0.96, 0.90, 0.80),
        shade: rgb(0.70, 0.55, 0.40),
        accent: rgb(0.85, 0.25, 0.25))

    static let crystal: AgentTilePalette = AgentTilePalette(
        body: rgb(0.40, 0.80, 0.95),
        shade: rgb(0.20, 0.50, 0.80),
        accent: rgb(0.40, 0.80, 0.95))

    static let frog: AgentTilePalette = AgentTilePalette(
        body: rgb(0.45, 0.78, 0.40),
        shade: rgb(0.28, 0.55, 0.28),
        accent: rgb(0.95, 0.50, 0.50))

    static let alien: AgentTilePalette = AgentTilePalette(
        body: rgb(0.62, 0.50, 0.90),
        shade: rgb(0.40, 0.30, 0.70),
        accent: rgb(0.50, 0.95, 0.70))

    func color(for pixel: Character) -> Color? {
        switch pixel {
        case "a": self.body
        case "b": self.shade
        case "c": self.accent
        case "w": Self.white
        case "k": Self.ink
        default: nil
        }
    }
}

/// Decorative sprite. Hidden from accessibility: the tile exposes one combined label.
struct AgentTileSpriteView: View {
    let kind: AgentTileSpriteKind

    var body: some View {
        Canvas { context, size in
            Self.draw(kind: self.kind, context: &context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static func draw(kind: AgentTileSpriteKind, context: inout GraphicsContext, size: CGSize) {
        let rows: [String] = kind.rows
        let palette: AgentTilePalette = kind.palette
        let rowCount: Int = rows.count
        guard rowCount > 0 else { return }
        let columnCount: Int = rows[0].count
        guard columnCount > 0 else { return }
        let cellWidth: CGFloat = size.width / CGFloat(columnCount)
        let cellHeight: CGFloat = size.height / CGFloat(rowCount)
        let cell: CGFloat = min(cellWidth, cellHeight)
        let originX: CGFloat = (size.width - cell * CGFloat(columnCount)) / 2
        let originY: CGFloat = (size.height - cell * CGFloat(rowCount)) / 2
        // Slight overdraw hides anti-aliasing seams between neighbouring pixels.
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
