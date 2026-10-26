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

/// Horizontal thinking-level control: a glass capsule bar with an accent fill, detents and a round thumb
/// the user drags. The fill grows from the first detent when the bar appears, the thumb swells while
/// held and settles with a spring on the nearest detent. One light haptic tick per detent crossed.
struct ChatThinkingSlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let options: [OpenClawChatThinkingLevelOption]
    let selectedIndex: Int
    let isEnabled: Bool
    let onSelectIndex: @MainActor (Int) -> Void

    @State private var dragIndex: Int?
    @State private var isDragging: Bool = false
    @State private var hasAppeared: Bool = false

    private static let trackHeight: CGFloat = 12
    private static let thumbSize: CGFloat = 36
    private static let barHeight: CGFloat = 60
    private static let barInset: CGFloat = 12
    private static let notchSize: CGFloat = 5

    private var displayedIndex: Int {
        let raw: Int = self.dragIndex ?? self.selectedIndex
        return min(max(raw, 0), max(self.options.count - 1, 0))
    }

    /// Index used for drawing: the first detent until the entrance animation has run.
    private var shownIndex: Int {
        self.hasAppeared ? self.displayedIndex : 0
    }

    private var displayedLabel: String {
        guard self.options.indices.contains(self.displayedIndex) else { return "" }
        return self.options[self.displayedIndex].label.capitalized
    }

    var body: some View {
        VStack(spacing: 10) {
            self.bar
                .modifier(ChatPopoverStagger())
            self.endLabels
                .modifier(ChatPopoverStagger())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Thinking level"))
        .accessibilityValue(self.displayedLabel)
        .accessibilityAdjustableAction { direction in
            self.adjust(direction)
        }
        .accessibilityIdentifier("chat-thinking-slider")
        .onAppear {
            self.playEntrance()
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let travel: CGFloat = max(proxy.size.width - Self.barInset * 2 - Self.thumbSize, 1)
            let count: Int = self.options.count
            let thumbX: CGFloat = ChatThinkingSliderMath.position(
                index: self.shownIndex,
                travel: travel,
                count: count)
            ZStack(alignment: .leading) {
                self.trackBar(width: proxy.size.width, thumbX: thumbX)
                self.notches(travel: travel)
                self.thumb
                    .offset(x: Self.barInset + thumbX)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .animation(
                self.isDragging
                    ? ChatPopoverMotion.selecting(reduceMotion: self.reduceMotion)
                    : ChatPopoverMotion.thumb(reduceMotion: self.reduceMotion),
                value: self.shownIndex)
            .contentShape(Rectangle())
            .gesture(self.dragGesture(travel: travel, count: count))
        }
        .frame(height: Self.barHeight)
        .openClawChatGlass(cornerRadius: Self.barHeight / 2)
        .shadow(color: Color.black.opacity(0.20), radius: 18, x: 0, y: 8)
    }

    private func trackBar(width: CGFloat, thumbX: CGFloat) -> some View {
        let fillWidth: CGFloat = thumbX + Self.thumbSize / 2
        let accent: Color = OpenClawChatTheme.brandAccent
        let enabledOpacity: Double = self.isEnabled ? 1 : 0.4
        let gradient: LinearGradient = LinearGradient(
            colors: [accent.opacity(0.78), accent],
            startPoint: .leading,
            endPoint: .trailing)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(OpenClawChatTheme.inkMuted.opacity(0.24))
                .frame(width: max(width - Self.barInset * 2, 1), height: Self.trackHeight)
                .offset(x: Self.barInset)
            Capsule()
                .fill(gradient)
                .frame(width: max(fillWidth, Self.trackHeight), height: Self.trackHeight)
                .shadow(color: accent.opacity(0.45), radius: 6, x: 0, y: 0)
                .opacity(enabledOpacity)
                .offset(x: Self.barInset)
        }
    }

    private func notches(travel: CGFloat) -> some View {
        let count: Int = self.options.count
        return ZStack(alignment: .leading) {
            ForEach(0..<count, id: \.self) { index in
                let x: CGFloat = ChatThinkingSliderMath.position(index: index, travel: travel, count: count)
                let covered: Bool = index <= self.shownIndex
                let dotColor: Color = covered
                    ? Color.white.opacity(0.9)
                    : OpenClawChatTheme.inkMuted.opacity(0.6)
                Circle()
                    .fill(dotColor)
                    .frame(width: Self.notchSize, height: Self.notchSize)
                    .offset(x: Self.barInset + x + (Self.thumbSize - Self.notchSize) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var thumb: some View {
        let scale: CGFloat = (self.isDragging && !self.reduceMotion) ? 1.14 : 1
        return Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(OpenClawChatTheme.brandAccent, lineWidth: 3))
            .overlay(
                Circle()
                    .fill(OpenClawChatTheme.brandAccent.opacity(0.9))
                    .frame(width: 8, height: 8))
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .shadow(color: Color.black.opacity(0.28), radius: 6, x: 0, y: 3)
            .scaleEffect(scale)
            .opacity(self.isEnabled ? 1 : 0.5)
            .animation(ChatPopoverMotion.thumb(reduceMotion: self.reduceMotion), value: self.isDragging)
            .accessibilityHidden(true)
    }

    private var endLabels: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Faster"))
                .font(OpenClawChatTypography.captionSemiBold)
                .foregroundStyle(OpenClawChatTheme.inkStandard)
            Spacer(minLength: 8)
            Text(verbatim: self.displayedLabel)
                .font(OpenClawChatTypography.body)
                .foregroundStyle(OpenClawChatTheme.inkStrong)
                .contentTransition(.opacity)
                .animation(
                    ChatPopoverMotion.selecting(reduceMotion: self.reduceMotion),
                    value: self.displayedLabel)
            Spacer(minLength: 8)
            Text(String(localized: "Smarter"))
                .font(OpenClawChatTypography.captionSemiBold)
                .foregroundStyle(OpenClawChatTheme.inkStandard)
        }
        .padding(.horizontal, 10)
        .accessibilityHidden(true)
    }

    private func playEntrance() {
        guard !self.hasAppeared else { return }
        if self.reduceMotion {
            self.hasAppeared = true
            return
        }
        withAnimation(ChatPopoverMotion.thumbSpring.delay(0.22)) {
            self.hasAppeared = true
        }
    }

    private func dragGesture(travel: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard self.isEnabled else { return }
                self.isDragging = true
                let position: CGFloat = value.location.x - Self.barInset - Self.thumbSize / 2
                let next: Int = ChatThinkingSliderMath.nearestIndex(
                    position: position,
                    travel: travel,
                    count: count)
                if next != self.displayedIndex {
                    ChatPopoverHaptics.selected()
                }
                self.dragIndex = next
            }
            .onEnded { _ in
                guard self.isEnabled else { return }
                let committed: Int = self.displayedIndex
                self.isDragging = false
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
        ChatPopoverHaptics.selected()
        self.onSelectIndex(next)
    }
}

/// Press feedback of the glass pill buttons that float on the thinking blur.
private struct ChatPopoverPillButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed: Bool = configuration.isPressed
        let scale: CGFloat = (pressed && !self.reduceMotion) ? 0.96 : 1
        let animation: Animation = self.reduceMotion
            ? OpenClawChatMotion.reducedFade
            : ChatPopoverMotion.pressSpring
        configuration.label
            .scaleEffect(scale)
            .animation(animation, value: pressed)
    }
}

/// Popover body for the thinking button: a small caption, the slider bar and the Fast mode pill.
/// Nothing here has an opaque background: the controls float on the progressive blur.
struct ChatThinkingPopoverContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: OpenClawChatViewModel

    var body: some View {
        let options: [OpenClawChatThinkingLevelOption] = self.viewModel.thinkingLevelOptions
        let selectionID: String = self.viewModel.thinkingSelectionID
        let index: Int = ChatThinkingSliderMath.resolvedIndex(
            selectionID: selectionID,
            effectiveLevelID: self.viewModel.thinkingLevel,
            options: options)
        VStack(alignment: .leading, spacing: 12) {
            self.caption
                .modifier(ChatPopoverStagger())
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
                    .frame(maxWidth: .infinity, minHeight: ChatPopoverMetrics.rowHeight, alignment: .center)
                    .openClawChatGlass(cornerRadius: ChatPopoverMetrics.rowHeight / 2)
            }
            if self.viewModel.showsFastModeControls {
                self.fastModeRow
            }
        }
        .padding(.vertical, 10)
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .font(OpenClawChatTypography.captionSemiBold)
                .foregroundStyle(OpenClawChatTheme.brandAccent)
                .accessibilityHidden(true)
            Text(String(localized: "Thinking"))
                .font(OpenClawChatTypography.captionSemiBold)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(OpenClawChatTheme.inkStandard)
        }
        .padding(.horizontal, 14)
    }

    private var fastModeRow: some View {
        let isOn: Bool = self.viewModel.fastModeIsEnabled
        let canChange: Bool = self.viewModel.selectedModelSupportsFastMode && !self.viewModel.isUpdatingSessionSettings
        let boltColor: Color = isOn ? OpenClawChatTheme.brandAccent : OpenClawChatTheme.inkMuted
        return Button {
            ChatPopoverHaptics.selected()
            let next: String = isOn ? "off" : "on"
            self.viewModel.selectFastMode(next)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: OpenClawChatTypography.scaled(15), weight: .semibold))
                    .foregroundStyle(boltColor)
                    .accessibilityHidden(true)
                Text(String(localized: "Fast mode"))
                    .font(OpenClawChatTypography.body)
                    .foregroundStyle(OpenClawChatTheme.inkStrong)
                Spacer(minLength: 8)
                ChatPopoverMiniSwitch(isOn: isOn)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .openClawChatGlass(cornerRadius: 26, interactive: true)
            .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(ChatPopoverPillButtonStyle(reduceMotion: self.reduceMotion))
        .disabled(!canChange)
        .opacity(canChange ? 1 : 0.5)
        .modifier(ChatPopoverStagger())
        .accessibilityLabel(String(localized: "Fast mode"))
        .accessibilityValue(isOn ? String(localized: "Selected") : "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("chat-fast-mode-toggle")
    }
}

#endif
