import SwiftUI

#if os(iOS)
import UIKit

/// Pure helpers for the thinking slider, kept separate so they can be unit tested.
enum ChatThinkingSliderMath {
    /// Nearest detent for a thumb centre position along the track.
    static func nearestIndex(position: CGFloat, travel: CGFloat, count: Int) -> Int {
        guard count > 1, travel > 0 else { return 0 }
        let fraction: CGFloat = min(max(position / travel, 0), 1)
        return Int((fraction * CGFloat(count - 1)).rounded())
    }

    /// Thumb centre position for a detent, measured from the start of the travel.
    static func position(index: Int, travel: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let clamped: Int = min(max(index, 0), count - 1)
        return travel * CGFloat(clamped) / CGFloat(count - 1)
    }

    /// Index of the level to show: the explicit selection, else the inherited effective level.
    static func resolvedIndex(
        selectionID: String,
        effectiveLevelID: String,
        options: [OpenClawChatThinkingLevelOption]) -> Int
    {
        let resolvedID: String = selectionID == OpenClawChatViewModel.inheritedThinkingSelectionID
            ? effectiveLevelID
            : selectionID
        return options.firstIndex(where: { $0.id == resolvedID }) ?? 0
    }
}

/// Horizontal thinking-level control: a thick track with detents and a round thumb the user drags.
/// Opaque palette colors only (no Liquid Glass). One light haptic tick per detent crossed.
struct ChatThinkingSlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let options: [OpenClawChatThinkingLevelOption]
    let selectedIndex: Int
    let isEnabled: Bool
    let onSelectIndex: @MainActor (Int) -> Void

    @State private var dragIndex: Int?

    private static let trackHeight: CGFloat = 16
    private static let thumbSize: CGFloat = 32
    private static let touchHeight: CGFloat = 44
    private static let notchSize: CGFloat = 6

    private var displayedIndex: Int {
        let raw: Int = self.dragIndex ?? self.selectedIndex
        return min(max(raw, 0), max(self.options.count - 1, 0))
    }

    private var displayedLabel: String {
        guard self.options.indices.contains(self.displayedIndex) else { return "" }
        return self.options[self.displayedIndex].label.capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.track
            self.endLabels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Thinking level"))
        .accessibilityValue(self.displayedLabel)
        .accessibilityAdjustableAction { direction in
            self.adjust(direction)
        }
        .accessibilityIdentifier("chat-thinking-slider")
    }

    private var track: some View {
        GeometryReader { proxy in
            let travel: CGFloat = max(proxy.size.width - Self.thumbSize, 1)
            let count: Int = self.options.count
            let thumbX: CGFloat = ChatThinkingSliderMath.position(
                index: self.displayedIndex,
                travel: travel,
                count: count)
            ZStack(alignment: .leading) {
                self.trackBar(travel: travel, thumbX: thumbX)
                self.notches(travel: travel)
                self.thumb
                    .offset(x: thumbX)
            }
            .frame(height: Self.touchHeight)
            .contentShape(Rectangle())
            .gesture(self.dragGesture(travel: travel, count: count))
        }
        .frame(height: Self.touchHeight)
    }

    private func trackBar(travel: CGFloat, thumbX: CGFloat) -> some View {
        let inset: CGFloat = Self.thumbSize / 2
        let fillWidth: CGFloat = thumbX + inset
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(OpenClawChatTheme.surfaceHover)
                .overlay(Capsule().strokeBorder(OpenClawChatTheme.hairline, lineWidth: 1))
                .frame(height: Self.trackHeight)
            Capsule()
                .fill(OpenClawChatTheme.brandAccent.opacity(self.isEnabled ? 1 : 0.4))
                .frame(width: max(fillWidth, Self.trackHeight), height: Self.trackHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notches(travel: CGFloat) -> some View {
        let count: Int = self.options.count
        return ZStack(alignment: .leading) {
            ForEach(0..<count, id: \.self) { index in
                let x: CGFloat = ChatThinkingSliderMath.position(index: index, travel: travel, count: count)
                let covered: Bool = index <= self.displayedIndex
                Circle()
                    .fill(covered ? Color.white.opacity(0.85) : OpenClawChatTheme.inkMuted.opacity(0.55))
                    .frame(width: Self.notchSize, height: Self.notchSize)
                    .offset(x: x + (Self.thumbSize - Self.notchSize) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var thumb: some View {
        Circle()
            .fill(OpenClawChatTheme.surfaceRaised)
            .overlay(Circle().strokeBorder(OpenClawChatTheme.brandAccent, lineWidth: 3))
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
            .opacity(self.isEnabled ? 1 : 0.5)
            .animation(
                self.dragIndex == nil ? OpenClawChatMotion.animation(reduceMotion: self.reduceMotion) : nil,
                value: self.displayedIndex)
            .accessibilityHidden(true)
    }

    private var endLabels: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Faster"))
                .font(OpenClawChatTypography.caption)
                .foregroundStyle(OpenClawChatTheme.inkMuted)
            Spacer(minLength: 8)
            Text(verbatim: self.displayedLabel)
                .font(OpenClawChatTypography.captionSemiBold)
                .foregroundStyle(OpenClawChatTheme.inkStrong)
            Spacer(minLength: 8)
            Text(String(localized: "Smarter"))
                .font(OpenClawChatTypography.caption)
                .foregroundStyle(OpenClawChatTheme.inkMuted)
        }
        .accessibilityHidden(true)
    }

    private func dragGesture(travel: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard self.isEnabled else { return }
                let position: CGFloat = value.location.x - Self.thumbSize / 2
                let next: Int = ChatThinkingSliderMath.nearestIndex(
                    position: position,
                    travel: travel,
                    count: count)
                if next != self.displayedIndex {
                    Self.tick()
                }
                self.dragIndex = next
            }
            .onEnded { _ in
                guard self.isEnabled else { return }
                let committed: Int = self.displayedIndex
                self.dragIndex = nil
                if committed != self.selectedIndex {
                    self.onSelectIndex(committed)
                }
            }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard self.isEnabled else { return }
        let delta: Int
        switch direction {
        case .increment: delta = 1
        case .decrement: delta = -1
        @unknown default: delta = 0
        }
        let next: Int = min(max(self.selectedIndex + delta, 0), max(self.options.count - 1, 0))
        guard next != self.selectedIndex else { return }
        Self.tick()
        self.onSelectIndex(next)
    }

    @MainActor
    private static func tick() {
        let generator: UISelectionFeedbackGenerator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

/// Popover body for the thinking button: title, slider, and a reset to the inherited default.
struct ChatThinkingPopoverContent: View {
    @Bindable var viewModel: OpenClawChatViewModel

    var body: some View {
        let options: [OpenClawChatThinkingLevelOption] = self.viewModel.thinkingLevelOptions
        let selectionID: String = self.viewModel.thinkingSelectionID
        let index: Int = ChatThinkingSliderMath.resolvedIndex(
            selectionID: selectionID,
            effectiveLevelID: self.viewModel.thinkingLevel,
            options: options)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "Thinking"))
                    .font(OpenClawChatTypography.captionSemiBold)
                    .foregroundStyle(OpenClawChatTheme.inkMuted)
                Spacer(minLength: 8)
            }
            if options.count > 1 {
                ChatThinkingSlider(
                    options: options,
                    selectedIndex: index,
                    isEnabled: !self.viewModel.isUpdatingSessionSettings)
                { next in
                    guard options.indices.contains(next) else { return }
                    self.viewModel.selectThinkingLevel(options[next].id)
                }
            } else if let only = options.first {
                Text(verbatim: only.label.capitalized)
                    .font(OpenClawChatTypography.body)
                    .foregroundStyle(OpenClawChatTheme.inkStrong)
                    .frame(minHeight: ChatPopoverMetrics.rowHeight, alignment: .leading)
            }
            if self.viewModel.showsFastModeControls {
                self.fastModeRow
            }
        }
        .padding(.horizontal, ChatPopoverMetrics.rowInset + 2)
        .padding(.vertical, 10)
    }

    private var fastModeRow: some View {
        let isOn: Bool = self.viewModel.fastModeIsEnabled
        let canChange: Bool = self.viewModel.selectedModelSupportsFastMode && !self.viewModel.isUpdatingSessionSettings
        return ChatPopoverRow(
            title: String(localized: "Fast mode"),
            systemImage: "bolt.fill",
            isSelected: isOn,
            isEnabled: canChange,
            closesPopover: false)
        {
            let next: String = isOn ? "off" : "on"
            self.viewModel.selectFastMode(next)
        }
        .padding(.horizontal, -ChatPopoverMetrics.rowInset)
        .accessibilityIdentifier("chat-fast-mode-toggle")
    }
}


#endif
