import OpenClawKit
import SwiftUI

// MARK: - Chat

/// System chat (main session with OpenClaw), presented full screen over the shell from the
/// Overview "More" menu. It is not a tab. `ChatProTab` does not own a NavigationStack, so the
/// shell provides one. The full-screen cover hides the tab bar, so the composer (a bottom
/// safe-area inset of the chat view) sits above the keyboard and never overlaps a tab bar.
/// A single close button replaces the sidebar action.
struct AppShellChatView: View {
    @Bindable var navigation: AppShellNavigation

    /// Opens a subagent chat (wait-list rows) full screen over this chat, with no tab bar underneath.
    @State private var subagentPresenter: SubagentChatPresenter = SubagentChatPresenter()

    private var closeAction: OpenClawSidebarHeaderAction {
        OpenClawSidebarHeaderAction(
            systemName: "xmark",
            accessibilityLabel: "Close",
            accessibilityIdentifier: "AppShell.Chat.Close",
            action: self.close)
    }

    var body: some View {
        NavigationStack {
            ChatProTab(
                headerSidebarAction: self.closeAction,
                openSettings: self.openGateway)
        }
        .subagentChatPresentation(presenter: self.subagentPresenter)
        .accessibilityIdentifier("AppShell.Chat")
    }

    private func close() {
        self.navigation.closeChat()
    }

    /// `openSettings` also dismisses the chat (the landing does not present it).
    private func openGateway() {
        self.navigation.openSettings(route: .gateway)
    }
}

// MARK: - Agents

/// Agents tab: only a glass agent selector (top left) and a grid of subagent tiles.
/// The board owns its view model; content stays opaque, glass is limited to the selector.
struct AppShellAgentsView: View {
    @Bindable var navigation: AppShellNavigation

    var body: some View {
        let token: Int = self.navigation.resetToken(for: .agents)
        return AgentsBoardScreen()
            .id("agents-board-\(token)")
            .accessibilityIdentifier("AppShell.Agents")
    }
}

// MARK: - Activity tab (Overview, Activity, Automations)

/// Activity tab: a glass segmented control chooses between Overview, the activity feed and
/// Automations. Each section keeps its own NavigationStack; the system handles the bottom
/// safe area (tab bar) for all of them.
struct AppShellActivityView: View {
    @Bindable var navigation: AppShellNavigation
    let context: AppShellContext

    private var currentSection: AppShellActivitySection {
        AppShellActivitySection(tab: self.navigation.selection)
    }

    private var sectionBinding: Binding<AppShellActivitySection> {
        Binding<AppShellActivitySection>(
            get: { self.currentSection },
            set: { newValue in self.navigation.selectActivitySection(newValue) })
    }

    private var sectionOptions: [OpenClawGlassSegmented<AppShellActivitySection>.Option] {
        var result: [OpenClawGlassSegmented<AppShellActivitySection>.Option] = []
        for section in AppShellActivitySection.allCases {
            let option = OpenClawGlassSegmented<AppShellActivitySection>.Option(
                section,
                title: section.title,
                systemImage: section.systemImage)
            result.append(option)
        }
        return result
    }

    var body: some View {
        self.content
            .safeAreaInset(edge: .top, spacing: 0) {
                self.sectionPicker
            }
            .background(OpenClawProBackground())
            .accessibilityIdentifier("AppShell.Activity")
    }

    private var sectionPicker: some View {
        OpenClawGlassSegmented(
            selection: self.sectionBinding,
            options: self.sectionOptions)
            .padding(.horizontal, OpenClawProMetric.pagePadding)
            .padding(.vertical, 8)
            .accessibilityIdentifier("AppShell.Activity.Sections")
    }

    @ViewBuilder
    private var content: some View {
        switch self.currentSection {
        case .overview:
            AppShellOverviewView(navigation: self.navigation, context: self.context)
        case .activity:
            self.nativeList(
                tab: .activity,
                path: DashboardRouteMap.activityPagePath,
                titleText: String(localized: "Activity"))
        case .automations:
            self.nativeList(
                tab: .automations,
                path: DashboardRouteMap.cronJobsPagePath,
                titleText: String(localized: "Automations"))
        }
    }

    private func nativeList(tab: AppShellTab, path: String, titleText: String) -> some View {
        let token: Int = self.navigation.resetToken(for: tab)
        return AppShellNativeListView(
            tab: tab,
            path: path,
            titleText: titleText,
            resetToken: token,
            context: self.context)
    }
}

// MARK: - Native Gateway list (Activity, Automations)

/// Hosts a dashboard path through `NativeDestinationRouter`, which resolves to native
/// list screens that own their NavigationStack, search and pull-to-refresh.
struct AppShellNativeListView: View {
    let tab: AppShellTab
    let path: String
    let titleText: String
    let resetToken: Int
    let context: AppShellContext

    var body: some View {
        NativeDestinationRouter(
            path: self.path,
            title: self.titleText,
            headerSidebarAction: nil,
            onRouteChange: nil,
            onApprovalNotificationsRoute: self.context.onApprovalNotificationsRoute)
            .id("\(self.tab.rawValue)-\(self.resetToken)")
            .accessibilityIdentifier(self.tab.accessibilityIdentifier)
    }
}

// MARK: - Settings

/// Settings tab. The hub owns its NavigationStack and reports typed pushes through
/// `settingsPath`. A gateway deep link lands on the Gateway screen directly, which is the
/// only place a pending gateway setup request is consumed.
struct AppShellSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var navigation: AppShellNavigation
    let context: AppShellContext

    var body: some View {
        switch self.navigation.settingsPresentation {
        case .hub:
            SettingsHubScreen(
                navigationPath: self.$navigation.settingsPath,
                headerSidebarAction: nil,
                onRouteChange: self.context.onSettingsRouteChange,
                onApprovalNotificationsRoute: self.context.onApprovalNotificationsRoute)
        case .gateway:
            self.gateway
        }
    }

    private var gateway: some View {
        let back = OpenClawSidebarHeaderAction(
            systemName: "chevron.backward",
            accessibilityLabel: "Back",
            accessibilityIdentifier: "AppShell.Settings.Back",
            action: self.showHub)
        return NavigationStack {
            SettingsProTab(
                directRoute: .gateway,
                acceptsGatewaySetupRequests: self.context.acceptsGatewaySetupRequests,
                headerSidebarAction: back,
                onRouteChange: self.context.onSettingsRouteChange,
                onApprovalNotificationsRoute: self.context.onApprovalNotificationsRoute,
                gatewaySetupRequest: self.context.gatewaySetupRequest,
                onGatewaySetupRequestHandled: self.context.onGatewaySetupRequestHandled)
        }
        .appShellSwipeBack()
    }

    private func showHub() {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.navigation.settingsPresentation = .hub
        }
    }
}
