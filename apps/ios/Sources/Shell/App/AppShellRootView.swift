import OpenClawKit
import SwiftUI

// MARK: - Root

/// Root of the native shell.
///
/// - Compact width (iPhone): a custom pager (`AppShellPagerView`) keeps the three tab pages alive
///   side by side, and a Liquid Glass bar (`AppShellGlassTabBar`) follows the drag. A horizontal
///   swipe anywhere on a tab root moves the pages with the finger (`appShellTabSwipe`).
/// - Regular width (iPad): the system `TabView` with the sidebar-adaptable style, no swipe.
/// - Three tabs only, left to right: Agents, Home, Activity. Home is selected at launch
///   (`AppShellTab.launchTab`). Activity hosts Activity and Automations behind a segmented control.
/// - There is no Settings tab (gear button of Home) and no Chat tab ("Talk to OpenClaw" in the
///   Home "More" menu). Chat and Settings share one full-screen cover (`coverKind`).
/// - Glass stays on navigation and controls; hosted screens keep their opaque grouped backgrounds.
struct AppShellRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var navigation: AppShellNavigation
    let context: AppShellContext

    @State private var pager: AppShellPagerState = AppShellPagerState()
    /// Bottom safe area (home indicator), measured so pages can pad their content below the floating bar.
    @State private var bottomSafeInset: CGFloat = 0

    /// The bar only knows three tabs; Automations maps to the Activity tab.
    private var selectionBinding: Binding<AppShellTab> {
        Binding<AppShellTab>(
            get: { self.navigation.selection.barTab },
            set: { newValue in self.navigation.userSelected(newValue) })
    }

    /// True while either the chat or the Settings hub is shown over the shell.
    private var coverBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.navigation.isChatPresented || self.navigation.isSettingsPresented },
            set: { newValue in
                if !newValue {
                    self.navigation.dismissCover()
                }
            })
    }

    private var usesPager: Bool {
        self.horizontalSizeClass != .regular
    }

    var body: some View {
        self.shell
            .sensoryFeedback(.selection, trigger: self.navigation.selection.barTab)
            .fullScreenCover(isPresented: self.coverBinding) {
                self.animatedCover
            }
            .accessibilityIdentifier("AppShell.Root")
    }

    @ViewBuilder
    private var shell: some View {
        if self.usesPager {
            self.pagedShell
        } else {
            self.systemTabs
        }
    }

    // MARK: Compact: pager + glass bar

    private var pagedShell: some View {
        let bottomInset: CGFloat = self.bottomSafeInset + AppShellGlassTabBar.reservedHeight
        return Color.clear
            .background {
                // Measured on a view that ignores the safe area: a view laid out inside it reports 0.
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(
                        for: CGFloat.self,
                        of: { (proxy: GeometryProxy) -> CGFloat in proxy.safeAreaInsets.bottom },
                        action: { (newInset: CGFloat) in
                            self.bottomSafeInset = newInset
                        })
            }
            .overlay {
                AppShellPagerView(
                    navigation: self.navigation,
                    pager: self.pager,
                    context: self.context,
                    bottomInset: bottomInset)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .overlay(alignment: .bottom) {
                AppShellGlassTabBar(
                    navigation: self.navigation,
                    pager: self.pager,
                    onSelect: self.selectFromBar)
                    .padding(.bottom, AppShellGlassTabBar.bottomGap)
            }
            .background { OpenClawProBackground().ignoresSafeArea() }
            .appShellTabSwipe(navigation: self.navigation, pager: self.pager)
    }

    /// Tap on the bar: the indicator and the pages slide with the shared spring.
    private func selectFromBar(_ tab: AppShellTab) {
        self.pager.noteSettle()
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.navigation.userSelected(tab)
        }
    }

    // MARK: Regular: system TabView

    private var systemTabs: some View {
        TabView(selection: self.selectionBinding) {
            Tab(
                AppShellTab.agents.title,
                systemImage: AppShellTab.agents.systemImage,
                value: AppShellTab.agents)
            {
                AppShellAgentsView(navigation: self.navigation)
            }

            Tab(
                AppShellTab.overview.title,
                systemImage: AppShellTab.overview.systemImage,
                value: AppShellTab.overview)
            {
                AppShellOverviewView(navigation: self.navigation, context: self.context)
            }

            Tab(
                AppShellTab.activity.title,
                systemImage: AppShellTab.activity.systemImage,
                value: AppShellTab.activity)
            {
                AppShellActivityView(navigation: self.navigation, context: self.context)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    // MARK: Cover

    /// Switching between Chat and Settings cross-fades (with a light scale) instead of cutting.
    private var animatedCover: some View {
        self.cover
            .openClawAnimation(value: self.navigation.coverKind)
    }

    @ViewBuilder
    private var cover: some View {
        switch self.navigation.coverKind {
        case .chat:
            AppShellChatView(navigation: self.navigation)
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        case .settings:
            AppShellSettingsView(navigation: self.navigation, context: self.context)
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        }
    }
}
