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
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(animation, value: configuration.isPressed)
    }
}

// MARK: - Activity dot

/// Small dot that breathes while a run is active. Static (and absent when idle) under Reduce Motion or when inactive.
private struct AgentTileActivityDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing: Bool = false
    let isActive: Bool
    let color: Color

    var body: some View {
        if self.isActive {
            self.dot
        }
    }

    private var pulseAnimation: Animation? {
        if self.reduceMotion { return nil }
        return Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    }

    private var dot: some View {
        let animated: Bool = self.pulsing && !self.reduceMotion
        let scale: CGFloat = animated ? 1.35 : 1
        let opacity: Double = animated ? 0.55 : 1
        return Circle()
            .fill(self.color)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(self.pulseAnimation, value: self.pulsing)
            .onAppear(perform: self.startPulse)
            .accessibilityHidden(true)
    }

    private func startPulse() {
        self.pulsing = true
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
            .contentTransition(.numericText())
    }
}

// MARK: - Tile

struct AgentTileView: View {
    let item: AgentTileItem
    let canStop: Bool
    /// Tap: opens the subagent chat.
    let onOpen: (AgentTileItem) -> Void
    let onStop: (AgentTileItem) -> Void
    /// Context menu "View details" (run facts sheet). Falls back to `onOpen` when nil.
    var onDetails: ((AgentTileItem) -> Void)?
    /// Context menu "Delete" (removes the conversation). Hidden when nil.
    var onDelete: ((AgentTileItem) -> Void)?
    /// Context menu "Rename" (sets the conversation label). Hidden when nil.
    var onRename: ((AgentTileItem) -> Void)?
    /// Context menu "Pin" / "Unpin" (keeps a subagent on the board after the 30 minute window). Hidden when nil.
    var onTogglePin: ((AgentTileItem) -> Void)?
    var isPinned: Bool = false
    /// Receives this tile's global frame (zoom origin of the chat). Nil -> not measured.
    var frameStore: AgentTileFrameStore?
    /// Position in the grid, used for the staggered entrance. Defaults to 0 (no extra delay).
    var entranceIndex: Int = 0

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
        .openClawEntrance(index: self.entranceIndex)
        .onGeometryChange(for: CGRect.self, of: self.globalFrame, action: self.storeFrame)
        .contextMenu { self.menuItems }
        .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.item.accessibilityText))
        .accessibilityHint(Text("Opens the subagent chat"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("View details"), self.showDetails)
        .accessibilityAction(named: Text("Stop"), self.stopIfAllowed)
        .accessibilityAction(named: Text("Rename"), self.requestRename)
        .accessibilityAction(named: Text("Delete"), self.requestDelete)
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
            self.parentLine
            self.toolLine
            Spacer(minLength: 0)
        }
        .openClawAnimation(value: self.item.toolLine)
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
            .openClawAnimation(value: asleep)
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
            AgentTileActivityDot(isActive: self.item.state.isActive, color: self.item.state.tint)
            Text(verbatim: self.item.state.label)
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(self.item.state.tint)
                .lineLimit(1)
                .contentTransition(.interpolate)
            AgentTileClock(item: self.item)
        }
        .openClawAnimation(value: self.item.state.label)
    }

    /// Small parent link for subagents whose parent conversation is known.
    @ViewBuilder
    private var parentLine: some View {
        if let parent = self.item.parentName {
            let text: String = String(localized: "Subagent of \(parent)")
            Text(verbatim: text)
                .font(OpenClawType.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var toolLine: some View {
        if let line = self.item.toolLine {
            Text(verbatim: line)
                .font(OpenClawType.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .transition(OpenClawMotion.edge(.top, reduceMotion: self.reduceMotion))
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Open chat", systemImage: "bubble.left.and.text.bubble.right", action: self.open)
        Button("View details", systemImage: "doc.text", action: self.showDetails)
        if self.canStopNow {
            Button("Stop", systemImage: "stop.circle", role: .destructive, action: self.requestStop)
        }
        if self.onTogglePin != nil {
            Button(
                self.isPinned ? "Unpin" : "Pin",
                systemImage: self.isPinned ? "pin.slash" : "pin",
                action: self.requestTogglePin)
        }
        if self.onRename != nil {
            Button("Rename", systemImage: "pencil", action: self.requestRename)
        }
        if self.onDelete != nil {
            Button("Delete", systemImage: "trash", role: .destructive, action: self.requestDelete)
        }
    }

    // MARK: Frame

    private var globalFrame: @Sendable (GeometryProxy) -> CGRect {
        let reader: @Sendable (GeometryProxy) -> CGRect = { proxy in
            proxy.frame(in: .global)
        }
        return reader
    }

    private func storeFrame(_ frame: CGRect) {
        self.frameStore?.set(frame, for: self.item.session.key)
    }

    // MARK: Actions

    private func open() {
        self.onOpen(self.item)
    }

    private func showDetails() {
        if let onDetails = self.onDetails {
            onDetails(self.item)
        } else {
            self.onOpen(self.item)
        }
    }

    private func requestStop() {
        self.onStop(self.item)
    }

    private func requestTogglePin() {
        self.onTogglePin?(self.item)
    }

    private func requestRename() {
        self.onRename?(self.item)
    }

    private func requestDelete() {
        self.onDelete?(self.item)
    }

    private func stopIfAllowed() {
        if self.canStopNow { self.onStop(self.item) }
    }
}
