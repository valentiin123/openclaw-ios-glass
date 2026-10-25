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

// MARK: - Activity tab (Activity, Automations)

/// Activity tab: ONE page header (title + flat section selector) owned by this view and injected
/// into the hosted screens through `\.activityHeader`. Each hosted screen draws it as the first row
/// of its own root content and hides its navigation bar, so the header, the filter line and a
/// navigation bar can never stack. Pushed details keep their own bar (the header is not drawn there).
/// Liquid Glass stays on the system tab bar. The Overview lives in the Home tab, not here.
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

    private var sectionOptions: [ActivitySegmentOption<AppShellActivitySection>] {
        var result: [ActivitySegmentOption<AppShellActivitySection>] = []
        for section in AppShellActivitySection.allCases {
            let option: ActivitySegmentOption<AppShellActivitySection> = ActivitySegmentOption<AppShellActivitySection>(
                value: section,
                title: section.title,
                systemImage: section.systemImage)
            result.append(option)
        }
        return result
    }

    private var pageHeader: AnyView {
        let header: ActivityPageHeader<AppShellActivitySection> = ActivityPageHeader<AppShellActivitySection>(
            title: self.currentSection.title,
            selection: self.sectionBinding,
            options: self.sectionOptions)
        let identified: some View = header.accessibilityIdentifier("AppShell.Activity.Sections")
        return AnyView(identified)
    }

    var body: some View {
        self.content
            .environment(\.activityHeader, self.pageHeader)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { OpenClawProBackground().ignoresSafeArea() }
            .accessibilityIdentifier("AppShell.Activity")
    }

    @ViewBuilder
    private var content: some View {
        switch self.currentSection {
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

/// Full-screen Settings, opened from the gear button of Home (there is no Settings tab).
/// The hub owns its NavigationStack and reports typed pushes through `settingsPath`; a close
/// button replaces the sidebar action at the top left. A gateway deep link lands on the
/// Gateway screen directly, which is the only place a pending gateway setup request is
/// consumed; its back button returns to the hub.
struct AppShellSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var navigation: AppShellNavigation
    let context: AppShellContext

    private var closeAction: OpenClawSidebarHeaderAction {
        OpenClawSidebarHeaderAction(
            systemName: "xmark",
            accessibilityLabel: "Close",
            accessibilityIdentifier: "AppShell.Settings.Close",
            action: self.close)
    }

    var body: some View {
        self.content
            .accessibilityIdentifier("AppShell.Settings")
    }

    @ViewBuilder
    private var content: some View {
        switch self.navigation.settingsPresentation {
        case .hub:
            SettingsHubScreen(
                navigationPath: self.$navigation.settingsPath,
                headerSidebarAction: self.closeAction,
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
            self.navigation.showSettingsHub()
        }
    }

    private func close() {
        self.navigation.closeSettings()
    }
}
