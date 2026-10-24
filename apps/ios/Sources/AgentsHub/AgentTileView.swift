import OpenClawChatUI
import SwiftUI
import UIKit

// One tile of the Agents board: opaque rectangular surface (no glass), pixel sprite, short name,
// playful state label, elapsed time, optional tool line and a clockwise orange outline.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Press feedback

private struct AgentTilePressStyle: ButtonStyle {
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

/// Elapsed time. Ticks every second only while the run is active.
private struct AgentTileClock: View {
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

struct AgentTileView: View {
    let item: AgentTileItem
    let canStop: Bool
    let onOpen: (AgentTileItem) -> Void
    let onStop: (AgentTileItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let radius: CGFloat = OpenClawRadius.md
    private let spriteSize: CGFloat = 44

    private var canStopNow: Bool {
        self.canStop && self.item.canBeStopped
    }

    var body: some View {
        Button(action: self.open) {
            self.card
        }
        .buttonStyle(AgentTilePressStyle(reduceMotion: self.reduceMotion))
        .contextMenu { self.menuItems }
        .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.item.accessibilityText))
        .accessibilityHint(Text("Opens run details"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Stop"), self.stopIfAllowed)
    }

    // MARK: Pieces

    private var card: some View {
        let surface: AgentTileOutline = AgentTileOutline(cornerRadius: self.radius)
        let border: AgentTileOutline = AgentTileOutline(cornerRadius: self.radius, inset: 0.5)
        return self.content
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(surface.fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(border.stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .overlay(self.ring)
            .contentShape(surface)
    }

    private var ring: some View {
        AgentTileProgressRing(
            progress: self.item.progress,
            isActive: self.item.state.isActive,
            cornerRadius: self.radius)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            self.header
            Text(verbatim: self.item.name)
                .font(OpenClawType.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            self.stateLine
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
            Text(verbatim: self.item.state.label)
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(self.item.state.tint)
                .lineLimit(1)
            AgentTileClock(item: self.item)
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
        Button("View details", systemImage: "doc.text", action: self.open)
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
