import OpenClawKit
import SwiftUI

// MARK: - Chat

/// Chat tab. `ChatProTab` does not own a NavigationStack, so the shell provides one.
/// The shell has no sidebar, so there is no header action.
struct AppShellChatView: View {
    @Bindable var navigation: AppShellNavigation

    var body: some View {
        NavigationStack {
            ChatProTab(
                headerSidebarAction: nil,
                openSettings: self.openGateway)
        }
        .accessibilityIdentifier("AppShell.Chat")
    }

    private func openGateway() {
        self.navigation.openSettings(route: .gateway)
    }
}

// MARK: - Agents

/// Agents tab: a glass segmented control chooses between roster, subagents and files.
/// The control is a floating inset above the hosted content; content stays opaque.
struct AppShellAgentsView: View {
    @Bindable var navigation: AppShellNavigation

    private var sectionOptions: [OpenClawGlassSegmented<AppShellAgentsSection>.Option] {
        var result: [OpenClawGlassSegmented<AppShellAgentsSection>.Option] = []
        for section in AppShellAgentsSection.allCases {
            let option = OpenClawGlassSegmented<AppShellAgentsSection>.Option(
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
            .accessibilityIdentifier("AppShell.Agents")
    }

    private var sectionPicker: some View {
        OpenClawGlassSegmented(
            selection: self.$navigation.agentsSection,
            options: self.sectionOptions)
            .padding(.horizontal, OpenClawProMetric.pagePadding)
            .padding(.vertical, 8)
            .accessibilityIdentifier("AppShell.Agents.Sections")
    }

    @ViewBuilder
    private var content: some View {
        let token: Int = self.navigation.resetToken(for: .agents)
        switch self.navigation.agentsSection {
        case .roster:
            NavigationStack {
                AgentProTab(
                    directRoute: .agents,
                    headerSidebarAction: nil,
                    openSettings: self.openGateway)
            }
            .id("roster-\(token)")
        case .files:
            NavigationStack {
                AgentProTab(
                    directRoute: .files,
                    headerSidebarAction: nil,
                    openSettings: self.openGateway)
            }
            .id("files-\(token)")
        case .subagents:
            // AgentsHubScreen owns its NavigationStack.
            AgentsHubScreen(headerSidebarAction: nil)
                .id("subagents-\(token)")
        }
    }

    private func openGateway() {
        self.navigation.openSettings(route: .gateway)
    }
}

// MARK: - Native Gateway list tabs (Activity, Automations)

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
