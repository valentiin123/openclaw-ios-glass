import SwiftUI
import UIKit

// MARK: - Floating glass tab bar

/// Floating Liquid Glass tab bar: ONE glass capsule holding plain items (no glass on glass).
/// Five primary tabs plus a "More" menu for the secondary destinations.
/// Every tap resolves to a `RootTabs.SidebarDestination`, so the existing selection
/// pipeline (`selectSidebarDestination`) stays the single owner of navigation state.
struct ShellTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    let selection: RootTabs.SidebarDestination
    let onSelect: (RootTabs.SidebarDestination) -> Void

    private var selectedTab: ShellTab? {
        ShellTab(destination: self.selection)
    }

    private var landing: ShellLanding {
        ShellLanding(destination: self.selection)
    }

    var body: some View {
        GlassEffectContainer(spacing: OpenClawGlassMetric.containerSpacing) {
            self.bar
        }
        .padding(.horizontal, OpenClawSpace.lg)
        .padding(.bottom, OpenClawSpace.xs)
        .sensoryFeedback(.selection, trigger: self.selection)
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(ShellTab.allCases) { (tab: ShellTab) in
                self.tabButton(tab)
            }
            self.moreMenu
        }
        .padding(.horizontal, OpenClawGlassMetric.toolbarHorizontalPadding)
        .padding(.vertical, OpenClawGlassMetric.toolbarVerticalPadding)
        .openClawGlass(in: Capsule())
        .openClawSwipe(onLeading: self.selectPrevious, onTrailing: self.selectNext)
    }

    private func tabButton(_ tab: ShellTab) -> some View {
        let isSelected: Bool = self.selectedTab == tab
        return Button(action: { self.select(tab.destination) }) {
            self.itemLabel(title: tab.title, systemImage: tab.systemImage, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var moreMenu: some View {
        let isSelected: Bool = self.landing.isSecondary
        return Menu {
            ForEach(ShellSecondaryDestination.allCases) { (item: ShellSecondaryDestination) in
                self.moreItem(item)
            }
        } label: {
            self.itemLabel(title: "More", systemImage: "ellipsis.circle", isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("Shell.Tab.more")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func moreItem(_ item: ShellSecondaryDestination) -> some View {
        Button(action: { self.select(item.destination) }) {
            Label(item.title, systemImage: item.systemImage)
        }
        .accessibilityIdentifier(item.accessibilityIdentifier)
    }

    private func itemLabel(title: LocalizedStringKey, systemImage: String, isSelected: Bool) -> some View {
        let color: Color = isSelected ? OpenClawBrand.accent : Color.secondary
        return VStack(spacing: OpenClawSpace.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background { self.selectionBackground(isSelected: isSelected) }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func selectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            Capsule()
                .fill(OpenClawBrand.accent.opacity(OpenClawOpacity.selectedTint))
                .matchedGeometryEffect(id: "shell.tab.selection", in: self.selectionNamespace)
        }
    }

    // MARK: Selection

    private func select(_ destination: RootTabs.SidebarDestination) {
        guard destination != self.selection else { return }
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.onSelect(destination)
        }
    }

    /// Rightward swipe on the bar goes to the previous tab.
    private func selectPrevious() {
        self.selectNeighbor(offset: -1)
    }

    /// Leftward swipe on the bar goes to the next tab. Tapping stays the accessible path.
    private func selectNext() {
        self.selectNeighbor(offset: 1)
    }

    private func selectNeighbor(offset: Int) {
        let tabs: [ShellTab] = ShellTab.allCases
        guard let current = self.selectedTab,
              let index = tabs.firstIndex(of: current)
        else { return }
        let target: Int = index + offset
        guard tabs.indices.contains(target) else { return }
        self.select(tabs[target].destination)
    }
}

// MARK: - Host modifier

/// Pins `ShellTabBar` to the bottom safe area. The bar steps aside while the keyboard is up
/// so it never floats above the chat composer.
struct ShellTabBarHost: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isKeyboardVisible: Bool = false

    let selection: RootTabs.SidebarDestination
    let isVisible: Bool
    let onSelect: (RootTabs.SidebarDestination) -> Void

    private var showsBar: Bool {
        self.isVisible && !self.isKeyboardVisible
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                self.barSlot
            }
            .onReceive(Self.keyboardWillShow) { (_: Notification) in
                self.isKeyboardVisible = true
            }
            .onReceive(Self.keyboardWillHide) { (_: Notification) in
                self.isKeyboardVisible = false
            }
    }

    private var barSlot: some View {
        ZStack {
            if self.showsBar {
                ShellTabBar(selection: self.selection, onSelect: self.onSelect)
                    .transition(OpenClawMotion.edge(.bottom, reduceMotion: self.reduceMotion))
            }
        }
        .openClawAnimation(value: self.showsBar)
    }

    private static var keyboardWillShow: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
    }

    private static var keyboardWillHide: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
    }
}

extension View {
    /// Adds the floating glass tab bar (Chat, Workboard, Activity, Automations, Usage + More).
    func shellTabBar(
        selection: RootTabs.SidebarDestination,
        isVisible: Bool,
        onSelect: @escaping (RootTabs.SidebarDestination) -> Void) -> some View
    {
        modifier(ShellTabBarHost(selection: selection, isVisible: isVisible, onSelect: onSelect))
    }
}
