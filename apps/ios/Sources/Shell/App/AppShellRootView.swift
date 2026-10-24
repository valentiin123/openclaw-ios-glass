import OpenClawKit
import SwiftUI

// MARK: - Root

/// Root of the native shell: an iOS 26 `TabView` (Liquid Glass tab bar drawn by the system).
///
/// - Four tabs only: Chat, Agents, Activity, Settings.
/// - Activity hosts Overview, Activity and Automations behind a segmented control; the
///   Overview "More" list holds Usage, Skill Workshop, Instances, Dreaming, Workboard and Docs.
/// - The tab bar is never hidden or inset by hand: every hosted screen lets the system apply
///   the bottom safe area (the chat composer is a bottom safe-area inset of the chat view).
/// - The tab bar minimises on scroll (`tabBarMinimizeBehavior`). Glass stays on navigation and
///   controls; hosted screens keep their opaque grouped backgrounds.
struct AppShellRootView: View {
    @Bindable var navigation: AppShellNavigation
    let context: AppShellContext

    /// The bar only knows four tabs; Overview and Automations map to the Activity tab.
    private var selectionBinding: Binding<AppShellTab> {
        Binding<AppShellTab>(
            get: { self.navigation.selection.barTab },
            set: { newValue in self.navigation.userSelected(newValue) })
    }

    var body: some View {
        TabView(selection: self.selectionBinding) {
            Tab(
                AppShellTab.chat.title,
                systemImage: AppShellTab.chat.systemImage,
                value: AppShellTab.chat)
            {
                AppShellChatView(navigation: self.navigation)
            }

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
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: self.navigation.selection.barTab)
        .accessibilityIdentifier("AppShell.Root")
    }
}
