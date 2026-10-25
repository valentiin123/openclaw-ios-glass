import SwiftUI

// Pixel-art sprites for the Agents board. Drawn with Canvas from character grids (no bitmap assets).
// Grid legend: `.` transparent, `a` body, `b` shade, `c` accent, `w` white, `k` ink.
// Every sprite is a 10 x 10 grid.
//
// Raw values are persisted by `AgentTileAssignmentStore`: only ever APPEND new cases at the end,
// never reorder or remove existing ones. `.robot` is reserved (Overview / system chat) and is never
// handed out to a tile.

enum AgentTileSpriteKind: Int, CaseIterable, Sendable {
    case robot
    case cat
    case owl
    case ghost
    case mushroom
    case crystal
    case frog
    case alien
    case fox
    case penguin
    case octopus
    case dragon
    case plant
    case moon
    case star
    case cloud
    case flame
    case drop
    case key
    case book
    case planet
    case bee
    case crab
    case panda
    case rabbit
    case fish

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
        case .fox: AgentTileSpriteArt.fox
        case .penguin: AgentTileSpriteArt.penguin
        case .octopus: AgentTileSpriteArt.octopus
        case .dragon: AgentTileSpriteArt.dragon
        case .plant: AgentTileSpriteArt.plant
        case .moon: AgentTileSpriteArt.moon
        case .star: AgentTileSpriteArt.star
        case .cloud: AgentTileSpriteArt.cloud
        case .flame: AgentTileSpriteArt.flame
        case .drop: AgentTileSpriteArt.drop
        case .key: AgentTileSpriteArt.key
        case .book: AgentTileSpriteArt.book
        case .planet: AgentTileSpriteArt.planet
        case .bee: AgentTileSpriteArt.bee
        case .crab: AgentTileSpriteArt.crab
        case .panda: AgentTileSpriteArt.panda
        case .rabbit: AgentTileSpriteArt.rabbit
        case .fish: AgentTileSpriteArt.fish
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
        case .fox: AgentTilePalette.fox
        case .penguin: AgentTilePalette.penguin
        case .octopus: AgentTilePalette.octopus
        case .dragon: AgentTilePalette.dragon
        case .plant: AgentTilePalette.plant
        case .moon: AgentTilePalette.moon
        case .star: AgentTilePalette.star
        case .cloud: AgentTilePalette.cloud
        case .flame: AgentTilePalette.flame
        case .drop: AgentTilePalette.drop
        case .key: AgentTilePalette.key
        case .book: AgentTilePalette.book
        case .planet: AgentTilePalette.planet
        case .bee: AgentTilePalette.bee
        case .crab: AgentTilePalette.crab
        case .panda: AgentTilePalette.panda
        case .rabbit: AgentTilePalette.rabbit
        case .fish: AgentTilePalette.fish
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

    static let fox: [String] = [
        "ab......ba",
        "aaa....aaa",
        ".aaaaaaaa.",
        ".akaaaaka.",
        "aaaaaaaaaa",
        ".wwaaaaww.",
        "..wwkkww..",
        "...wwww...",
        "....ww....",
        "....cc....",
    ]

    static let penguin: [String] = [
        "...aaaa...",
        "..aaaaaa..",
        "..akaaka..",
        "..aaccaa..",
        ".aawwwwaa.",
        ".aawwwwaa.",
        "aaawwwwaaa",
        ".aawwwwaa.",
        "..aawwaa..",
        "..cc..cc..",
    ]

    static let octopus: [String] = [
        "...aaaa...",
        "..aaaaaa..",
        ".aaaaaaaa.",
        ".awkaawka.",
        ".aaaaaaaa.",
        ".aaaccaaa.",
        ".aaaaaaaa.",
        "ba.baab.ab",
        "a..b..b..a",
        "c........c",
    ]

    static let dragon: [String] = [
        "b........b",
        ".bb....bb.",
        ".aaaaaaaa.",
        ".akaaaaka.",
        ".aaaaaaaa.",
        ".aaakkaaa.",
        "..aaaaaa..",
        ".bacccaab.",
        ".baccccab.",
        "..bb..bb..",
    ]

    static let plant: [String] = [
        "...cccc...",
        "..ccwwcc..",
        "..ccwwcc..",
        "...cccc...",
        "....aa....",
        ".aa.aa.aa.",
        "..aaaaaa..",
        ".bbbbbbbb.",
        "..bkbbkb..",
        "..bbbbbb..",
    ]

    static let moon: [String] = [
        "...aaaaa..",
        "..aaaaa...",
        ".aaabaa..c",
        ".aaaaa....",
        ".aabaa....",
        ".aaaaa....",
        ".aaabaa...",
        "..aaaaa...",
        "...aaaaa..",
        "...bbbb...",
    ]

    static let star: [String] = [
        "....aa....",
        "....aa....",
        "...aaaa...",
        "aaaaaaaaaa",
        ".aaaaaaaa.",
        "..akaaka..",
        "...aaaa...",
        "..aaccaa..",
        "..aa..aa..",
        ".bb....bb.",
    ]

    static let cloud: [String] = [
        "...aaa....",
        "..aaaaa.aa",
        ".aaaaaaaaa",
        "aaaaaaaaaa",
        "aakaaaakaa",
        "aaaaccaaaa",
        ".bbbbbbbb.",
        "..c..c..c.",
        "...c..c...",
        ".c..c...c.",
    ]

    static let flame: [String] = [
        ".....b....",
        "....bb....",
        "...bab..b.",
        "..baab.bb.",
        "..baaabab.",
        ".baaaaaaab",
        ".baakaakab",
        ".baacccaab",
        "..baccaab.",
        "...bbbb...",
    ]

    static let drop: [String] = [
        "....aa....",
        "....aa....",
        "...aaaa...",
        "...aaaa...",
        "..awaaaa..",
        ".awaaaaaa.",
        ".aakaakaa.",
        ".aaaccaaa.",
        "..aaaaaa..",
        "...bbbb...",
    ]

    static let key: [String] = [
        "...aaaa...",
        "..aabbaa..",
        "..abccba..",
        "..abccba..",
        "..aabbaa..",
        "...aaaa...",
        "....aa....",
        "....aab...",
        "....aa....",
        "....aab...",
    ]

    static let book: [String] = [
        ".bbbbbbbb.",
        "baaaaaaaab",
        "baacccaaab",
        "baaaaaaaab",
        "baakaakaab",
        "baaaaaaaab",
        "baaaccaaab",
        "bwwwwwwwwb",
        ".wwwwwwww.",
        ".bbbbbbbb.",
    ]

    static let planet: [String] = [
        "...aaaa...",
        "..aaaaaa..",
        ".aaaaaaaa.",
        ".aakaakaa.",
        "cccccccccc",
        ".aaaaaaaa.",
        ".aabbbbaa.",
        "..aabbaa..",
        "...aaaa...",
        "....bb....",
    ]

    static let bee: [String] = [
        "...w..w...",
        "..ww..ww..",
        "...aaaa...",
        "..akaaka..",
        "..aaaaaa..",
        "..kkkkkk..",
        "..aaaaaa..",
        "..kkkkkk..",
        "...aaaa...",
        "....cc....",
    ]

    static let crab: [String] = [
        "cc..ww..cc",
        "cc..kk..cc",
        ".c.aaaa.c.",
        "..aaaaaa..",
        ".aakaakaa.",
        ".aaaaaaaa.",
        ".aaaccaaa.",
        "..aaaaaa..",
        ".b.b..b.b.",
        "b..b..b..b",
    ]

    static let panda: [String] = [
        "kk......kk",
        "kkk....kkk",
        ".aaaaaaaa.",
        ".akkaakka.",
        ".aaaaaaaa.",
        ".aaakkaaa.",
        "..aaccaa..",
        ".kkaaaakk.",
        ".kkaaaakk.",
        "..kk..kk..",
    ]

    static let rabbit: [String] = [
        "..aa..aa..",
        "..ac..ca..",
        "..ac..ca..",
        "..aaaaaa..",
        ".aaaaaaaa.",
        ".akaaaaka.",
        ".aaaccaaa.",
        "..aaaaaa..",
        "..aaaaaa..",
        "..bb..bb..",
    ]

    static let fish: [String] = [
        "...w......",
        "....w.....",
        "...bbbb...",
        "..baaaab.c",
        ".baaaaaabc",
        "baakaaaaac",
        "baaaaaaacc",
        ".baaaaaabc",
        "..baaaab.c",
        "...bbbb...",
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

    static let fox: AgentTilePalette = AgentTilePalette(
        body: rgb(0.92, 0.50, 0.20),
        shade: rgb(0.62, 0.28, 0.12),
        accent: rgb(0.30, 0.22, 0.20))

    static let penguin: AgentTilePalette = AgentTilePalette(
        body: rgb(0.20, 0.27, 0.40),
        shade: rgb(0.12, 0.17, 0.27),
        accent: rgb(0.98, 0.70, 0.20))

    static let octopus: AgentTilePalette = AgentTilePalette(
        body: rgb(0.88, 0.45, 0.70),
        shade: rgb(0.62, 0.25, 0.48),
        accent: rgb(0.99, 0.80, 0.85))

    static let dragon: AgentTilePalette = AgentTilePalette(
        body: rgb(0.30, 0.72, 0.55),
        shade: rgb(0.15, 0.45, 0.38),
        accent: rgb(0.98, 0.82, 0.40))

    static let plant: AgentTilePalette = AgentTilePalette(
        body: rgb(0.35, 0.72, 0.30),
        shade: rgb(0.72, 0.42, 0.28),
        accent: rgb(0.98, 0.45, 0.60))

    static let moon: AgentTilePalette = AgentTilePalette(
        body: rgb(0.98, 0.88, 0.50),
        shade: rgb(0.80, 0.66, 0.28),
        accent: rgb(0.70, 0.80, 1.00))

    static let star: AgentTilePalette = AgentTilePalette(
        body: rgb(1.00, 0.82, 0.25),
        shade: rgb(0.85, 0.60, 0.10),
        accent: rgb(0.96, 0.45, 0.40))

    static let cloud: AgentTilePalette = AgentTilePalette(
        body: rgb(0.82, 0.88, 0.96),
        shade: rgb(0.55, 0.65, 0.82),
        accent: rgb(0.35, 0.60, 0.98))

    static let flame: AgentTilePalette = AgentTilePalette(
        body: rgb(0.99, 0.60, 0.15),
        shade: rgb(0.82, 0.25, 0.15),
        accent: rgb(1.00, 0.88, 0.35))

    static let drop: AgentTilePalette = AgentTilePalette(
        body: rgb(0.30, 0.62, 0.98),
        shade: rgb(0.18, 0.40, 0.78),
        accent: rgb(0.98, 0.55, 0.65))

    static let key: AgentTilePalette = AgentTilePalette(
        body: rgb(0.95, 0.78, 0.25),
        shade: rgb(0.72, 0.52, 0.12),
        accent: rgb(0.40, 0.85, 0.80))

    static let book: AgentTilePalette = AgentTilePalette(
        body: rgb(0.28, 0.45, 0.80),
        shade: rgb(0.16, 0.26, 0.52),
        accent: rgb(0.98, 0.78, 0.30))

    static let planet: AgentTilePalette = AgentTilePalette(
        body: rgb(0.55, 0.40, 0.85),
        shade: rgb(0.34, 0.24, 0.62),
        accent: rgb(0.98, 0.72, 0.38))

    static let bee: AgentTilePalette = AgentTilePalette(
        body: rgb(0.99, 0.82, 0.22),
        shade: rgb(0.70, 0.50, 0.10),
        accent: rgb(0.90, 0.35, 0.30))

    static let crab: AgentTilePalette = AgentTilePalette(
        body: rgb(0.92, 0.32, 0.28),
        shade: rgb(0.62, 0.18, 0.18),
        accent: rgb(0.98, 0.52, 0.40))

    static let panda: AgentTilePalette = AgentTilePalette(
        body: rgb(0.95, 0.95, 0.93),
        shade: rgb(0.60, 0.60, 0.62),
        accent: rgb(0.98, 0.60, 0.68))

    static let rabbit: AgentTilePalette = AgentTilePalette(
        body: rgb(0.86, 0.78, 0.70),
        shade: rgb(0.58, 0.48, 0.42),
        accent: rgb(0.98, 0.62, 0.72))

    static let fish: AgentTilePalette = AgentTilePalette(
        body: rgb(0.25, 0.78, 0.78),
        shade: rgb(0.14, 0.50, 0.58),
        accent: rgb(0.98, 0.65, 0.30))

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
