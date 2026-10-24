import OpenClawKit
import SwiftUI

// MARK: - Root

/// Root of the native shell: an iOS 26 `TabView` (Liquid Glass tab bar drawn by the system).
///
/// - Three tabs only: Agents, Activity, Settings. There is no Chat tab: the system chat
///   (main session) opens full screen from the Overview "More" menu (`isChatPresented`).
/// - Activity hosts Overview, Activity and Automations behind a segmented control; the
///   Overview "More" list holds Usage, Skill Workshop, Instances, Dreaming, Workboard and Docs.
/// - The tab bar is never hidden or inset by hand: every hosted screen lets the system apply
///   the bottom safe area. The full-screen chat covers the tab bar, so its composer never
///   overlaps it and stays above the keyboard.
/// - The tab bar stays in place (no minimise-on-scroll). Glass stays on navigation and
///   controls; hosted screens keep their opaque grouped backgrounds.
struct AppShellRootView: View {
    @Bindable var navigation: AppShellNavigation
    let context: AppShellContext

    /// The bar only knows three tabs; Overview and Automations map to the Activity tab.
    private var selectionBinding: Binding<AppShellTab> {
        Binding<AppShellTab>(
            get: { self.navigation.selection.barTab },
            set: { newValue in self.navigation.userSelected(newValue) })
    }

    var body: some View {
        TabView(selection: self.selectionBinding) {
            Tab(
                AppShellTab.agents.title,
                systemImage: AppShellTab.agents.systemImage,
                value: AppShellTab.agents)
            {
                AppShellAgentsView(navigation: self.navigation)
            }

            Tab(
                AppShellTab.activity.title,
                systemImage: AppShellTab.activity.systemImage,
                value: AppShellTab.activity)
            {
                AppShellActivityView(navigation: self.navigation, context: self.context)
            }

            Tab(
                AppShellTab.settings.title,
                systemImage: AppShellTab.settings.systemImage,
                value: AppShellTab.settings)
            {
                AppShellSettingsView(navigation: self.navigation, context: self.context)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sensoryFeedback(.selection, trigger: self.navigation.selection.barTab)
        .fullScreenCover(isPresented: self.$navigation.isChatPresented) {
            AppShellChatView(navigation: self.navigation)
        }
        .accessibilityIdentifier("AppShell.Root")
    }
}
