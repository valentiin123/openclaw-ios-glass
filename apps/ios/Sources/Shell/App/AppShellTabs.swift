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

/// Activity tab: a glass segmented control chooses between the activity feed and Automations.
/// Each section keeps its own NavigationStack; the system handles the bottom safe area
/// (tab bar) for both of them. The Overview lives in the Home tab, not here.
struct AppShellActivityView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    /// The hosted screens own a NavigationStack, and UIKit draws their bar from the top of the
    /// window, so a `safeAreaInset(.top)` around them never moves that bar and the picker ends
    /// up on top of it. The picker is therefore a regular row of a `VStack`: the hosted stack is
    /// laid out in the space left under it and the two can never overlap. The row has no fill,
    /// only the control itself is glass.
    var body: some View {
        VStack(spacing: 0) {
            self.sectionPicker
            self.content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { OpenClawProBackground().ignoresSafeArea() }
        .accessibilityIdentifier("AppShell.Activity")
    }

    private var sectionPicker: some View {
        self.pickerControl
            .padding(.horizontal, OpenClawProMetric.pagePadding)
            .padding(.top, OpenClawSpace.sm)
            .padding(.bottom, OpenClawSpace.sm)
            .accessibilityIdentifier("AppShell.Activity.Sections")
    }

    /// Two segments with icon and title no longer fit side by side at accessibility text sizes,
    /// so the same choice is offered as a menu picker there (full-width, 44 pt tall).
    @ViewBuilder
    private var pickerControl: some View {
        if self.dynamicTypeSize.isAccessibilitySize {
            self.pickerMenu
        } else {
            OpenClawGlassSegmented(
                selection: self.sectionBinding,
                options: self.sectionOptions)
        }
    }

    private var pickerMenu: some View {
        Picker(selection: self.sectionBinding) {
            ForEach(AppShellActivitySection.allCases) { (section: AppShellActivitySection) in
                self.pickerRow(section)
            }
        } label: {
            self.currentSection.title.text
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum, alignment: .leading)
    }

    private func pickerRow(_ section: AppShellActivitySection) -> some View {
        section.title.text
            .tag(section)
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
