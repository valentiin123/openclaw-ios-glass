import OpenClawChatUI
import SwiftUI

// Liquid Glass tile for an agent / subagent: glass surface, pixel sprite, name, state, elapsed
// time, optional tool line. Tiles of one grid share a namespace so a tile that changes position
// (state change, reorder, insertion) glides to its new slot with the shared spring.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Press style

private struct AgentGlassTilePressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed: Bool = configuration.isPressed && !self.reduceMotion
        let scale: CGFloat = pressed ? OpenClawMotion.pressedScale : 1
        let animation: Animation = OpenClawMotion.animation(reduceMotion: self.reduceMotion)
        return configuration.label
            .scaleEffect(scale)
            .animation(animation, value: configuration.isPressed)
    }
}

// MARK: - Clock

private struct AgentGlassTileClock: View {
    let item: AgentTileItem

    var body: some View {
        if let start = self.item.startDate {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                self.text(seconds: context.date.timeIntervalSince(start))
            }
        } else {
            self.text(seconds: self.item.elapsed)
        }
    }

    private func text(seconds: TimeInterval?) -> some View {
        let value: String = seconds.flatMap { AgentTileFormat.duration(seconds: $0, spelledOut: false) } ?? ""
        return Text(verbatim: value)
            .font(OpenClawType.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }
}

// MARK: - Tile

struct AgentGlassTile: View {
    let item: AgentTileItem
    let canStop: Bool
    let namespace: Namespace.ID
    let onOpen: (AgentTileItem) -> Void
    let onStop: (AgentTileItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let radius: CGFloat = 22
    private let spriteSize: CGFloat = 44

    private var canStopNow: Bool {
        self.canStop && self.item.canBeStopped
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: self.radius, style: .continuous)
    }

    var body: some View {
        Button(action: self.open) {
            self.card
        }
        .buttonStyle(AgentGlassTilePressStyle(reduceMotion: self.reduceMotion))
        .contextMenu { self.menuItems }
        .matchedGeometryEffect(id: self.item.id, in: self.namespace)
        .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.item.accessibilityText))
        .accessibilityHint(Text("Opens the subagent chat"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Stop"), self.stopIfAllowed)
    }

    // MARK: Pieces

    private var card: some View {
        self.content
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .contentShape(self.shape)
            .openClawGlass(in: self.shape, interactive: true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            self.header
            Text(verbatim: self.item.name)
                .font(OpenClawType.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            self.stateLine
            self.progressLine
            self.toolLine
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 4) {
            self.sprite
            self.bubble
            Spacer(minLength: 0)
            self.sleepMark
        }
    }

    private var sprite: some View {
        let asleep: Bool = self.item.state.isAsleep
        let opacity: Double = asleep ? 0.55 : 1
        let saturation: Double = asleep ? 0 : 1
        return AgentTileSpriteView(kind: self.item.sprite)
            .frame(width: self.spriteSize, height: self.spriteSize)
            .saturation(saturation)
            .opacity(opacity)
    }

    @ViewBuilder
    private var bubble: some View {
        if let kind = self.item.state.bubble {
            AgentTileBubbleView(kind: kind)
                .frame(width: 24)
        }
    }

    @ViewBuilder
    private var sleepMark: some View {
        if self.item.state.isAsleep {
            AgentTileBubbleView(kind: .sleep)
                .frame(width: 24)
        }
    }

    private var stateLine: some View {
        HStack(spacing: 6) {
            AgentGlassStatusBadge(state: self.item.state, size: 18)
            Text(verbatim: self.item.state.label)
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(self.item.state.tint)
                .lineLimit(1)
            AgentGlassTileClock(item: self.item)
        }
        .openClawAnimation(value: self.item.state)
    }

    @ViewBuilder
    private var progressLine: some View {
        if let progress = self.item.progress, self.item.state.isActive {
            AgentGlassProgressBar(progress: progress, tint: self.item.state.tint)
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        }
    }

    @ViewBuilder
    private var toolLine: some View {
        if let line = self.item.toolLine {
            Text(verbatim: line)
                .font(OpenClawType.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Open chat", systemImage: "bubble.left.and.text.bubble.right", action: self.open)
        if self.canStopNow {
            Button("Stop", systemImage: "stop.circle", role: .destructive, action: self.requestStop)
        }
    }

    // MARK: Actions

    private func open() {
        self.onOpen(self.item)
    }

    private func requestStop() {
        self.onStop(self.item)
    }

    private func stopIfAllowed() {
        if self.canStopNow { self.onStop(self.item) }
    }
}

// MARK: - Grid

/// Two-column grid of glass tiles. Owns the matched-geometry namespace and animates
/// insertions, removals and reorders with the shared spring (fade only under Reduce Motion).
struct AgentGlassTileGrid: View {
    let items: [AgentTileItem]
    let canStop: Bool
    let onOpen: (AgentTileItem) -> Void
    let onStop: (AgentTileItem) -> Void

    @Namespace private var namespace

    private let spacing: CGFloat = 12

    private var columns: [GridItem] {
        let column: GridItem = GridItem(.flexible(), spacing: self.spacing)
        return [column, column]
    }

    private var identity: [String] {
        self.items.map(\.id)
    }

    var body: some View {
        LazyVGrid(columns: self.columns, spacing: self.spacing) {
            ForEach(self.items) { item in
                AgentGlassTile(
                    item: item,
                    canStop: self.canStop,
                    namespace: self.namespace,
                    onOpen: self.onOpen,
                    onStop: self.onStop)
            }
        }
        .openClawAnimation(value: self.identity)
        .accessibilityElement(children: .contain)
    }
}
