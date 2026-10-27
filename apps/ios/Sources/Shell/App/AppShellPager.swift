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

    /// Page the pager settles on when the finger lifts. Uses the translation plus a short
    /// projection of the velocity, so a quick flick also changes page.
    static func settleTarget(
        index: Int,
        translation: CGFloat,
        velocity: CGFloat,
        width: CGFloat,
        count: Int) -> Int
    {
        guard width > 0, count > 0 else { return index }
        let projected: CGFloat = translation + velocity * 0.2
        let threshold: CGFloat = width * 0.4
        var target: Int = index
        if projected < -threshold {
            target = index + 1
        } else if projected > threshold {
            target = index - 1
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
struct AppShellPagerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var navigation: AppShellNavigation
    let pager: AppShellPagerState
    let context: AppShellContext

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

/// Custom Liquid Glass tab bar. One capsule indicator slides under the items and follows the
/// pager position, so it moves with the finger during a swipe and animates on a tap.
struct AppShellGlassTabBar: View {
    @Bindable var navigation: AppShellNavigation
    let pager: AppShellPagerState
    let onSelect: (AppShellTab) -> Void

    private static let barHeight: CGFloat = 60
    private static let inset: CGFloat = 4

    var body: some View {
        let tabs: [AppShellTab] = AppShellTab.barTabs
        let index: Int = AppShellPagerMath.index(of: self.navigation.selection)
        let position: CGFloat = AppShellPagerMath.position(
            index: index,
            dragX: self.pager.dragX,
            width: self.pager.pageWidth)
        return GeometryReader { (proxy: GeometryProxy) in
            self.bar(tabs: tabs, position: position, width: proxy.size.width)
        }
        .frame(height: Self.barHeight)
        .padding(.horizontal, OpenClawSpace.lg)
        .padding(.bottom, OpenClawSpace.xs)
        .allowsHitTesting(!self.pager.isDragging)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("AppShell.TabBar")
    }

    private func bar(tabs: [AppShellTab], position: CGFloat, width: CGFloat) -> some View {
        let count: CGFloat = CGFloat(max(tabs.count, 1))
        let itemWidth: CGFloat = max((width - Self.inset * 2) / count, 1)
        let indicatorHeight: CGFloat = Self.barHeight - Self.inset * 2
        let active: Int = Int(position.rounded())
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(OpenClawBrand.accent.opacity(0.18))
                .frame(width: itemWidth, height: indicatorHeight)
                .offset(x: Self.inset + position * itemWidth)
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element) { (offset: Int, tab: AppShellTab) in
                    self.item(tab, isActive: offset == active, width: itemWidth)
                }
            }
            .padding(.horizontal, Self.inset)
        }
        .frame(width: width, height: Self.barHeight)
        .openClawGlassCapsule(interactive: false)
    }

    private func item(_ tab: AppShellTab, isActive: Bool, width: CGFloat) -> some View {
        let tint: Color = isActive ? OpenClawBrand.accent : OpenClawPalette.texteAtténué
        let traits: AccessibilityTraits = isActive ? .isSelected : []
        return Button(action: { self.onSelect(tab) }) {
            VStack(spacing: OpenClawSpace.xxs) {
                Image(systemName: tab.systemImage)
                    .font(OpenClawType.subheadSemiBold)
                Text(tab.title)
                    .font(OpenClawType.captionSemiBold)
            }
            .foregroundStyle(tint)
            .frame(width: width, height: Self.barHeight - Self.inset * 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }
}
