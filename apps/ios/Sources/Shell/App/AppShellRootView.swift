import OpenClawKit
import SwiftUI

// MARK: - Root

/// Root of the native shell: an iOS 26 `TabView` (Liquid Glass tab bar drawn by the system).
///
/// - iPhone: five tabs (Overview, Chat, Agents, Activity, Settings). Automations is hidden
///   from the bar and reached from the Overview menu.
/// - iPad: `.sidebarAdaptable` shows all six, including Automations.
/// - The tab bar minimises on scroll (`tabBarMinimizeBehavior`). Glass stays on navigation and
///   controls; hosted screens keep their opaque grouped backgrounds.
struct AppShellRootView: View {
    @Bindable var navigation: AppShellNavigation
    let context: AppShellContext

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var selectionBinding: Binding<AppShellTab> {
        Binding<AppShellTab>(
            get: { self.navigation.selection },
            set: { newValue in self.navigation.userSelected(newValue) })
    }

    private var hidesAutomationsTab: Bool {
        self.horizontalSizeClass == .compact
    }

    private var activityTitle: String {
        String(localized: "Activity")
    }

    private var automationsTitle: String {
        String(localized: "Automations")
    }

    var body: some View {
        TabView(selection: self.selectionBinding) {
            Tab(
                AppShellTab.overview.title,
                systemImage: AppShellTab.overview.systemImage,
                value: AppShellTab.overview)
            {
                AppShellOverviewView(navigation: self.navigation, context: self.context)
            }

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
                self.activityScreen
            }

            Tab(
                AppShellTab.automations.title,
                systemImage: AppShellTab.automations.systemImage,
                value: AppShellTab.automations)
            {
                self.automationsScreen
            }
            .hidden(self.hidesAutomationsTab)

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
        .sensoryFeedback(.selection, trigger: self.navigation.selection)
        .accessibilityIdentifier("AppShell.Root")
    }

    private var activityScreen: some View {
        let token: Int = self.navigation.resetToken(for: .activity)
        return AppShellNativeListView(
            tab: .activity,
            path: DashboardRouteMap.activityPagePath,
            titleText: self.activityTitle,
            resetToken: token,
            context: self.context)
    }

    private var automationsScreen: some View {
        let token: Int = self.navigation.resetToken(for: .automations)
        return AppShellNativeListView(
            tab: .automations,
            path: DashboardRouteMap.cronJobsPagePath,
            titleText: self.automationsTitle,
            resetToken: token,
            context: self.context)
    }
}
