import Observation
import OpenClawKit
import SwiftUI

// MARK: - Pager state

/// Live state of the swipeable pager. It is separate from `AppShellNavigation` so that a drag
/// (60 updates per second) only re-evaluates the small views that read `dragX`, never the pages.
@MainActor
@Observable
final class AppShellPagerState {
    /// Finger translation in points while dragging, 0 at rest. Positive moves toward the previous tab.
    var dragX: CGFloat = 0
    /// Width of one page, measured from the pager container.
    var pageWidth: CGFloat = 0
    /// True from the moment the pan is recognized until it ends or is cancelled.
    var isDragging: Bool = false

    /// End of the last settle animation (swipe release or tap on the bar). A drag that starts
    /// before this moment follows the finger through a spring, so the pages catch up with the
    /// finger from where they currently are instead of jumping.
    @ObservationIgnored var settleUntil: Date = Date.distantPast
    /// True for the current drag when it started while a settle animation was still running.
    @ObservationIgnored var tracksWithSpring: Bool = false

    func noteSettle() {
        self.settleUntil = Date().addingTimeInterval(0.6)
    }

    func isSettling() -> Bool {
        Date() < self.settleUntil
    }
}

// MARK: - Math

/// Pure helpers shared by the pager, the glass tab bar and the pan handlers.
enum AppShellPagerMath {
    /// Index of the bar tab that hosts `tab` (Automations maps to Activity).
    static func index(of tab: AppShellTab) -> Int {
        let tabs: [AppShellTab] = AppShellTab.barTabs
        if let found = tabs.firstIndex(of: tab.barTab) {
            return found
        }
        return tabs.firstIndex(of: AppShellTab.launchTab) ?? 0
    }

    /// Keeps the drag inside the neighbours that exist: nothing moves past the first or last tab.
    static func clamp(dragX: CGFloat, index: Int, count: Int, width: CGFloat) -> CGFloat {
        let lower: CGFloat = index >= count - 1 ? 0 : -width
        let upper: CGFloat = index <= 0 ? 0 : width
        return min(max(dragX, lower), upper)
    }

    /// Velocity (points per second) above which a short drag still changes page.
    static let flickVelocity: CGFloat = 450
    /// Minimum travel (points) for a flick to count, so a tiny twitch never changes page.
    static let flickMinimumTravel: CGFloat = 16

    /// Page the pager settles on when the finger lifts. A quick flick in the direction of the
    /// drag changes page; otherwise the translation alone must pass a third of the page width.
    /// The result is always clamped to the existing pages (no page past either end).
    static func settleTarget(
        index: Int,
        translation: CGFloat,
        velocity: CGFloat,
        width: CGFloat,
        count: Int) -> Int
    {
        guard width > 0, count > 0 else { return index }
        var target: Int = index
        let sameDirection: Bool = (translation > 0) == (velocity > 0)
        let isFlick: Bool = abs(velocity) > Self.flickVelocity
            && abs(translation) > Self.flickMinimumTravel
            && sameDirection
        if isFlick {
            target = translation < 0 ? index + 1 : index - 1
        } else {
            let threshold: CGFloat = width / 3
            if translation < -threshold {
                target = index + 1
            } else if translation > threshold {
                target = index - 1
            }
        }
        return min(max(target, 0), count - 1)
    }

    /// Fractional page position (0 = Agents, 1 = Home, 2 = Activity) that follows the finger.
    static func position(index: Int, dragX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return CGFloat(index) }
        return CGFloat(index) - dragX / width
    }
}

// MARK: - Pager

/// Three live pages laid side by side with no gap, shifted by one offset: the selected page's
/// base offset plus the finger translation. The pages always exist, so the neighbour is already
/// on screen while the finger drags. Only the selected page receives touches, and none do during
/// a drag. The drag itself comes from `appShellTabSwipe` (a window-level pan recognizer).
///
/// The pager is meant to extend to the bottom edge of the screen (the floating tab bar is an
/// overlay, not an inset). `bottomInset` is added to each page's bottom safe area, so scroll
/// views keep their last row reachable above the bar while content scrolls underneath it.
struct AppShellPagerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var navigation: AppShellNavigation
    let pager: AppShellPagerState
    let context: AppShellContext
    let bottomInset: CGFloat

    var body: some View {
        let index: Int = AppShellPagerMath.index(of: self.navigation.selection)
        let width: CGFloat = self.pager.pageWidth
        return Color.clear
            .onGeometryChange(
                for: CGFloat.self,
                of: { (proxy: GeometryProxy) -> CGFloat in proxy.size.width },
                action: { (newWidth: CGFloat) in
                    self.pager.pageWidth = newWidth
                })
            .overlay(alignment: .topLeading) {
                self.strip(index: index, width: width)
            }
            .clipped()
            .accessibilityIdentifier("AppShell.Pager")
    }

    @ViewBuilder
    private func strip(index: Int, width: CGFloat) -> some View {
        if width > 0 {
            HStack(spacing: 0) {
                ForEach(AppShellTab.barTabs) { (tab: AppShellTab) in
                    self.page(tab, width: width)
                }
            }
            .modifier(AppShellPagerOffset(pager: self.pager, index: index, reduceMotion: self.reduceMotion))
        }
    }

    @ViewBuilder
    private func page(_ tab: AppShellTab, width: CGFloat) -> some View {
        let isCurrent: Bool = tab == self.navigation.selection.barTab
        let hidden: Bool = self.reduceMotion && !isCurrent
        self.pageContent(tab)
            .safeAreaPadding(.bottom, self.bottomInset)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(isCurrent && !self.pager.isDragging)
            .accessibilityHidden(!isCurrent)
    }

    @ViewBuilder
    private func pageContent(_ tab: AppShellTab) -> some View {
        switch tab {
        case .agents:
            AppShellAgentsView(navigation: self.navigation)
        case .overview:
            AppShellOverviewView(navigation: self.navigation, context: self.context)
        case .activity, .automations:
            AppShellActivityView(navigation: self.navigation, context: self.context)
        }
    }
}

/// Reads `dragX` and `pageWidth` here, not in the pager body, so a drag only re-runs this modifier.
/// Under Reduce Motion the slide is replaced by a cross-fade (pages fade, the offset jumps).
private struct AppShellPagerOffset: ViewModifier {
    let pager: AppShellPagerState
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let base: CGFloat = -CGFloat(self.index) * self.pager.pageWidth
        let x: CGFloat = base + self.pager.dragX
        let reduce: Bool = self.reduceMotion
        return content
            .offset(x: x)
            .transaction(value: self.index) { (transaction: inout Transaction) in
                if reduce {
                    transaction.animation = nil
                }
            }
    }
}

// MARK: - Glass tab bar

/// Position and stretch of the selection capsule, computed per frame from the fractional page
/// position. Because `position` is animatable, the same effect runs for a finger drag (the value
/// follows the finger) and for a tap (the spring interpolates the value), and the capsule
/// stretches along its travel like the native Liquid Glass selection.
private struct AppShellIndicatorEffect: GeometryEffect {
    var position: CGFloat
    let itemWidth: CGFloat
    let inset: CGFloat
    let count: Int

    var animatableData: CGFloat {
        get { self.position }
        set { self.position = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let upper: CGFloat = CGFloat(max(self.count - 1, 0))
        let clamped: CGFloat = min(max(self.position, 0), upper)
        let fraction: CGFloat = clamped - clamped.rounded(.down)
        let travel: CGFloat = sin(fraction * CGFloat.pi)
        let stretchX: CGFloat = 1 + 0.18 * travel
        let squashY: CGFloat = 1 - 0.05 * travel
        let x: CGFloat = self.inset + self.position * self.itemWidth
        var transform: CGAffineTransform = CGAffineTransform(
            translationX: x + size.width / 2,
            y: size.height / 2)
        transform = transform.scaledBy(x: stretchX, y: squashY)
        transform = transform.translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(transform)
    }
}

/// Button style that only reports the pressed state, so the selection capsule can swell while a
/// finger is down (the native "lens" press feedback). It draws nothing itself.
private struct AppShellTabButtonStyle: ButtonStyle {
    let onPressChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { (_: Bool, newValue: Bool) in
                self.onPressChange(newValue)
            }
    }
}

/// Floating Liquid Glass tab bar: a compact capsule, centered, three items of identical fixed
/// width. It is drawn as an overlay (never an inset), so page content scrolls under it. One glass
/// capsule slides under the items and follows the pager position: it moves with the finger during
/// a swipe and springs (with a stretch) on a tap.
struct AppShellGlassTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var navigation: AppShellNavigation
    let pager: AppShellPagerState
    let onSelect: (AppShellTab) -> Void

    @State private var pressedIndex: Int? = nil
    /// Finger x (bar coordinates) while the selection capsule is being dragged, nil otherwise.
    @State private var barDragX: CGFloat? = nil

    static let itemWidth: CGFloat = 84
    static let itemHeight: CGFloat = 52
    static let inset: CGFloat = 4
    static let barHeight: CGFloat = AppShellGlassTabBar.itemHeight + AppShellGlassTabBar.inset * 2
    /// Distance between the bottom safe area (home indicator) and the bar.
    static let bottomGap: CGFloat = 0
    /// Extra room kept between the last scrolled row and the bar.
    static let contentClearance: CGFloat = 12
    /// Bottom padding to add to page content so its last row stays reachable above the bar.
    static let reservedHeight: CGFloat = AppShellGlassTabBar.barHeight
        + AppShellGlassTabBar.bottomGap
        + AppShellGlassTabBar.contentClearance

    private static let indicatorSpring: Animation = .spring(response: 0.42, dampingFraction: 0.68)
    private static let pressSpring: Animation = .spring(response: 0.26, dampingFraction: 0.62)
    /// Horizontal travel (points) before a touch on the bar counts as a drag rather than a tap.
    private static let dragActivation: CGFloat = 6

    /// Fractional tab position (0 = first tab) under a finger at `x` in bar coordinates.
    private static func position(forBarX x: CGFloat, count: Int) -> CGFloat {
        let upper: CGFloat = CGFloat(max(count - 1, 0))
        let raw: CGFloat = (x - Self.inset - Self.itemWidth / 2) / Self.itemWidth
        return min(max(raw, 0), upper)
    }

    var body: some View {
        let tabs: [AppShellTab] = AppShellTab.barTabs
        let index: Int = AppShellPagerMath.index(of: self.navigation.selection)
        var position: CGFloat = AppShellPagerMath.position(
            index: index,
            dragX: self.pager.dragX,
            width: self.pager.pageWidth)
        if let fingerX: CGFloat = self.barDragX {
            position = Self.position(forBarX: fingerX, count: tabs.count)
        }
        let active: Int = min(max(Int(position.rounded()), 0), max(tabs.count - 1, 0))
        let barWidth: CGFloat = CGFloat(tabs.count) * Self.itemWidth + Self.inset * 2
        return ZStack(alignment: .leading) {
            self.indicator(position: position, index: index, count: tabs.count)
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element) { (offset: Int, tab: AppShellTab) in
                    self.item(tab, offset: offset, isActive: offset == active)
                }
            }
            .padding(.horizontal, Self.inset)
        }
        .frame(width: barWidth, height: Self.barHeight)
        .simultaneousGesture(self.barDragGesture(count: tabs.count))
        .openClawGlassCapsule(interactive: false)
        .allowsHitTesting(!self.pager.isDragging)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("AppShell.TabBar")
    }

    private func indicator(position: CGFloat, index: Int, count: Int) -> some View {
        let pressed: Bool = (self.pressedIndex != nil || self.barDragX != nil) && !self.reduceMotion
        let spring: Animation? = self.reduceMotion ? nil : Self.indicatorSpring
        let effect: AppShellIndicatorEffect = AppShellIndicatorEffect(
            position: position,
            itemWidth: Self.itemWidth,
            inset: Self.inset,
            count: count)
        return Color.clear
            .frame(width: Self.itemWidth, height: Self.itemHeight)
            .openClawGlassCapsule(tint: OpenClawBrand.accent.opacity(0.30), interactive: false)
            .scaleEffect(pressed ? 1.12 : 1)
            .animation(Self.pressSpring, value: pressed)
            .modifier(effect)
            .animation(spring, value: index)
            .allowsHitTesting(false)
    }

    private func item(_ tab: AppShellTab, offset: Int, isActive: Bool) -> some View {
        let tint: Color = isActive ? OpenClawBrand.accent : OpenClawPalette.texteAtténué
        let traits: AccessibilityTraits = isActive ? .isSelected : []
        let variant: SymbolVariants = isActive ? .fill : .none
        return Button(action: { self.onSelect(tab) }) {
            VStack(spacing: OpenClawSpace.xxs) {
                Image(systemName: tab.systemImage)
                    .symbolVariant(variant)
                    .font(OpenClawType.subheadSemiBold)
                Text(tab.title)
                    .font(OpenClawType.captionSemiBold)
            }
            .foregroundStyle(tint)
            .animation(.easeOut(duration: 0.18), value: isActive)
            .frame(width: Self.itemWidth, height: Self.itemHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(AppShellTabButtonStyle(onPressChange: { (pressed: Bool) in
            self.setPressed(pressed, offset: offset)
        }))
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    /// Drag on the bar: past a small slop the capsule follows the finger; on release it springs
    /// to the nearest tab and selects it. A plain tap is left to the buttons.
    private func barDragGesture(count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { (value: DragGesture.Value) in
                if self.barDragX != nil || abs(value.translation.width) > Self.dragActivation {
                    self.barDragX = value.location.x
                }
            }
            .onEnded { (value: DragGesture.Value) in
                guard self.barDragX != nil else { return }
                let tabs: [AppShellTab] = AppShellTab.barTabs
                let target: CGFloat = Self.position(forBarX: value.location.x, count: tabs.count)
                let nearest: Int = min(max(Int(target.rounded()), 0), max(tabs.count - 1, 0))
                if self.reduceMotion {
                    self.barDragX = nil
                } else {
                    withAnimation(Self.indicatorSpring) {
                        self.barDragX = nil
                    }
                }
                if tabs.indices.contains(nearest) {
                    self.onSelect(tabs[nearest])
                }
            }
    }

    private func setPressed(_ pressed: Bool, offset: Int) {
        if pressed {
            self.pressedIndex = offset
        } else if self.pressedIndex == offset {
            self.pressedIndex = nil
        }
    }
}
