import OpenClawKit
import SwiftUI

// MARK: - Overview tab

/// Home tab (middle of the bar, selected at launch): `CommandCenterTab` as root of a NavigationStack driven by `homePath`.
/// It hosts only the Overview; Activity and Automations live in the Activity tab.
/// The gear button opens the full Settings hub full screen over the shell (no Settings tab).
/// - Sessions are pushed (edge swipe-back stays enabled through `appShellSwipeBack`).
/// - Secondary screens (Usage, Skill Workshop, Instances, Dreaming, Workboard, Docs) open in a
///   sheet because each hosted screen owns its own NavigationStack.
/// - The header button of the Overview opens the "More" list: "Talk to OpenClaw" first (system
///   chat, main session, full screen over the shell), then Usage, Skill Workshop, Instances,
///   Dreaming, Workboard, Docs. Automations is a section of the Activity tab, not a row here.
struct AppShellOverviewView: View {
    @Environment(NodeAppModel.self) private var appModel
    @Bindable var navigation: AppShellNavigation
    let context: AppShellContext

    @State private var showsMoreList: Bool = false
    @State private var pendingMore: AppShellMoreItem?
    @State private var pendingChat: Bool = false
    /// Chats opened from the Sessions list use the same screen as the Agents tab (sprite header).
    @State private var sessionChatPresenter: SubagentChatPresenter = SubagentChatPresenter()

    private var moreAction: OpenClawSidebarHeaderAction {
        OpenClawSidebarHeaderAction(
            systemName: "ellipsis",
            accessibilityLabel: "More",
            accessibilityIdentifier: "AppShell.Overview.More",
            action: self.openMoreList)
    }

    private var backAction: OpenClawSidebarHeaderAction {
        OpenClawSidebarHeaderAction(
            systemName: "chevron.backward",
            accessibilityLabel: "Back",
            accessibilityIdentifier: "AppShell.Overview.Back",
            action: self.popHome)
    }

    private var presentedMoreBinding: Binding<AppShellMoreItem?> {
        Binding<AppShellMoreItem?>(
            get: { self.navigation.presentedMore },
            set: { newValue in self.navigation.presentedMore = newValue })
    }

    var body: some View {
        NavigationStack(path: self.$navigation.homePath) {
            self.root
                .navigationDestination(for: AppShellHomeRoute.self) { route in
                    self.destination(for: route)
                }
        }
        .sheet(isPresented: self.$showsMoreList, onDismiss: self.moreListDidDismiss) {
            AppShellMoreListView(onSelectMore: self.chooseMore, onSelectChat: self.chooseChat)
        }
        .sheet(item: self.presentedMoreBinding) { item in
            AppShellMoreItemView(
                item: item,
                context: self.context,
                openGateway: self.openGateway,
                close: self.closeMore)
        }
        .subagentChatPresentation(presenter: self.sessionChatPresenter)
        .accessibilityIdentifier("AppShell.Overview")
    }

    private var root: some View {
        CommandCenterTab(
            headerSidebarAction: self.moreAction,
            dashboardModel: self.context.sidebarModel,
            openChat: self.openChat,
            openSettings: self.openSettings,
            openSessions: self.openSessions,
            openApprovals: self.openApprovals,
            openAutomations: self.openAutomations,
            openUsage: self.openUsage,
            openSession: self.openSession)
    }

    @ViewBuilder
    private func destination(for route: AppShellHomeRoute) -> some View {
        switch route {
        case .sessions:
            AppShellSessionsScreen(
                model: self.context.sidebarModel,
                headerSidebarAction: self.backAction,
                openChat: self.openSessionChat,
                openGateway: self.openGateway)
                .appShellSwipeBack()
        case .more:
            // `.more` never stays on the path: the model turns it into a sheet.
            EmptyView()
        }
    }

    // MARK: Actions

    private func openMoreList() {
        self.showsMoreList = true
    }

    private func chooseMore(_ item: AppShellMoreItem) {
        self.pendingMore = item
        self.showsMoreList = false
    }

    private func chooseChat() {
        self.pendingChat = true
        self.showsMoreList = false
    }

    /// Presenting a second sheet while the first is still dismissing is dropped by UIKit.
    /// The choice is applied once the list sheet is fully gone.
    private func moreListDidDismiss() {
        if self.pendingChat {
            self.pendingChat = false
            // nil falls back to the main session key (the system chat).
            self.appModel.focusChatSession(nil)
            self.navigation.openChat()
            return
        }
        if let item = self.pendingMore {
            self.pendingMore = nil
            self.navigation.open(more: item)
        }
    }

    private func closeMore() {
        self.navigation.presentedMore = nil
    }

    private func popHome() {
        if !self.navigation.homePath.isEmpty {
            self.navigation.homePath.removeLast()
        }
    }

    private func openChat() {
        self.navigation.openChat()
    }

    /// Session tile on the Overview: same full-screen sprite chat as the Agents tab.
    private func openSession(_ key: String) {
        self.sessionChatPresenter.open(key)
    }

    /// Session picked in the Sessions list: `NodeAppModel.openChat(sessionKey:)` already focused it.
    private func openSessionChat() {
        self.sessionChatPresenter.open(self.appModel.chatSessionKey)
    }

    /// Gear button: the full Settings hub, full screen, on its root.
    private func openSettings() {
        self.navigation.presentedMore = nil
        self.navigation.openSettings(route: nil)
    }

    private func openGateway() {
        self.navigation.presentedMore = nil
        self.navigation.openSettings(route: .gateway)
    }

    private func openSessions() {
        self.navigation.openSessions()
    }

    private func openApprovals() {
        self.navigation.openSettings(route: .approvals)
    }

    private func openAutomations() {
        self.navigation.openAutomations()
    }

    private func openUsage() {
        self.navigation.open(more: .usage)
    }
}

// MARK: - More list (sheet)

/// Plain grouped list: opaque content, glass only on the floating Done control.
struct AppShellMoreListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onSelectMore: (AppShellMoreItem) -> Void
    let onSelectChat: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                OpenClawProBackground()
                ScrollView {
                    self.rows
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppShellDoneButton(action: { self.dismiss() })
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(OpenClawBrand.void)
        .accessibilityIdentifier("AppShell.More.List")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.sm) {
            self.chatRow
                .openClawEntrance(index: 0)
            ForEach(Array(AppShellMoreItem.allCases.enumerated()), id: \.element) { (offset: Int, item: AppShellMoreItem) in
                self.moreRow(item)
                    .openClawEntrance(index: offset + 1)
            }
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
        .padding(.vertical, OpenClawSpace.md)
    }

    private var chatRow: some View {
        Button(action: self.onSelectChat) {
            self.row(title: "Talk to OpenClaw", systemImage: "bubble.left")
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
        .accessibilityIdentifier("AppShell.More.chat")
    }

    private func moreRow(_ item: AppShellMoreItem) -> some View {
        Button(action: { self.onSelectMore(item) }) {
            self.row(title: item.title, systemImage: item.systemImage)
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
        .accessibilityIdentifier(item.accessibilityIdentifier)
    }

    private func row(title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: OpenClawSpace.md) {
            self.glyph(systemImage)
            Text(title)
                .font(OpenClawType.body)
                .foregroundStyle(OpenClawPalette.texteFort)
            Spacer(minLength: OpenClawSpace.sm)
            Image(systemName: "chevron.right")
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, OpenClawSpace.md)
        .padding(.vertical, OpenClawSpace.sm)
        .frame(maxWidth: .infinity, minHeight: OverviewMetric.minTarget + OpenClawSpace.sm, alignment: .leading)
        .overviewTile()
        .contentShape(Rectangle())
    }

    private func glyph(_ systemImage: String) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: OpenClawRadius.xs,
            style: .continuous)
        return Image(systemName: systemImage)
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(OpenClawBrand.accent)
            .frame(width: 32, height: 32)
            .background(shape.fill(OpenClawPalette.surfaceInset))
            .overlay(shape.strokeBorder(OpenClawBrand.hairlineBorderStrong, lineWidth: OpenClawProMetric.borderWidth))
            .accessibilityHidden(true)
    }
}

// MARK: - More item (sheet)

/// Hosts one secondary destination. Native screens own their NavigationStack, so this view
/// adds none; the floating Done control closes the sheet.
struct AppShellMoreItemView: View {
    let item: AppShellMoreItem
    let context: AppShellContext
    let openGateway: () -> Void
    let close: () -> Void

    var body: some View {
        self.screen
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppShellDoneButton(action: self.close)
            }
            .accessibilityIdentifier("AppShell.More.\(self.item.rawValue).Sheet")
    }

    @ViewBuilder
    private var screen: some View {
        if let path = self.item.dashboardPath {
            NativeDestinationRouter(
                path: path,
                title: self.item.titleString,
                headerSidebarAction: nil,
                onRouteChange: nil,
                onApprovalNotificationsRoute: self.context.onApprovalNotificationsRoute)
        } else {
            OpenClawDocsScreen(
                headerSidebarAction: nil,
                gatewayAction: self.openGateway)
        }
    }
}
