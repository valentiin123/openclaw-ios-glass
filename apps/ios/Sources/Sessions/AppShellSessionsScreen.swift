import OpenClawChatUI
import OpenClawKit
import SwiftUI

/// Session list of the native shell, pushed from Overview > Sessions.
///
/// Brings back what the former sidebar offered, kept simple:
/// - search field (same `RootSidebarModel.sections` rules as the sidebar),
/// - Pinned / custom groups / recent sections (`SessionsListLayout`),
/// - rightward swipe actions (`SessionSwipeActions.swift`) and the long-press menu
///   (`commandSessionActions`, which also carries group assignment),
/// - a discreet Gateway picker at the top (`RootSidebarGatewayControl`).
///
/// Content stays on opaque surfaces; no glass behind reading content.
struct AppShellSessionsScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: RootSidebarModel
    let headerSidebarAction: OpenClawSidebarHeaderAction?
    let openChat: () -> Void
    let openGateway: () -> Void

    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    // MARK: Derived state

    private var categories: [String] {
        CommandSessionGrouping.categories(from: self.model.sessions, knownGroups: SessionGroupStore.load())
    }

    private var resolvedMainSessionKey: String {
        self.model.resolvedSessionKey(
            current: "main",
            mainSessionKey: self.appModel.mainSessionKey,
            activeAgentID: self.appModel.chatAgentId,
            sessionRoutingContract: self.appModel.chatSessionRoutingContract)
    }

    private var resolvedSelectedSessionKey: String {
        self.model.resolvedSessionKey(
            current: self.appModel.chatSessionKey,
            mainSessionKey: self.appModel.mainSessionKey,
            activeAgentID: self.appModel.chatAgentId,
            sessionRoutingContract: self.appModel.chatSessionRoutingContract)
    }

    private var gatewayName: String {
        RootSidebar.gatewayName(
            serverName: self.appModel.gatewayServerName,
            remoteAddress: self.appModel.gatewayRemoteAddress)
    }

    private var actions: SessionsListActions {
        SessionsListActions(appModel: self.appModel, model: self.model, openChat: self.openChat)
    }

    private func layout(categories: [String]) -> SessionsListLayout {
        var groups: [OpenClawChatSessionGroup] = []
        for (offset, name) in categories.enumerated() {
            groups.append(OpenClawChatSessionGroup(name: name, position: offset))
        }
        let sections: [ChatSessionSidebarModel.Section] = RootSidebarModel.sections(
            sessions: self.model.sessions,
            query: self.searchText,
            currentSessionKey: self.appModel.chatSessionKey,
            mainSessionKey: self.appModel.mainSessionKey,
            activeAgentID: self.appModel.chatAgentId,
            groups: groups,
            sessionRoutingContract: self.appModel.chatSessionRoutingContract,
            now: self.model.now)
        return SessionsListLayout.make(from: sections, searchText: self.searchText)
    }

    // MARK: Body

    var body: some View {
        let categories: [String] = self.categories
        let layout: SessionsListLayout = self.layout(categories: categories)
        let selectedKey: String = self.resolvedSelectedSessionKey
        let mainKey: String = self.resolvedMainSessionKey
        return ZStack {
            OpenClawProBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    self.header
                        .openClawEntrance(index: 0)
                    self.searchField
                        .openClawEntrance(index: 1)
                    self.gatewayRow
                        .openClawEntrance(index: 2)
                    self.statusBlock(layout: layout)
                    ForEach(layout.sections) { (section: SessionsListSection) in
                        self.sectionView(
                            section,
                            selectedKey: selectedKey,
                            mainKey: mainKey,
                            categories: categories)
                    }
                }
                .openClawAnimation(value: layout.isEmpty)
                .openClawAnimation(value: self.model.isRefreshing)
                .openClawAnimation(value: self.model.sessionErrorText)
                .padding(.horizontal, OpenClawProMetric.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .safeAreaPadding(.bottom, OpenClawProMetric.bottomScrollInset)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await self.model.refreshSessions(appModel: self.appModel)
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await self.model.refreshSessions(appModel: self.appModel)
        }
        .accessibilityIdentifier("AppShell.Sessions")
    }

    // MARK: Header and search

    private var header: some View {
        OpenClawAdaptiveHeaderRow(
            title: "Sessions",
            subtitle: .verbatim(self.headerDetail),
            titleFont: OpenClawType.title2,
            subtitleFont: OpenClawType.captionMedium)
        {
            if let headerSidebarAction {
                OpenClawSidebarControlButton(action: headerSidebarAction)
            }
        } accessory: {
            EmptyView()
        }
    }

    private var headerDetail: String {
        let count: Int = self.model.sessions.count
        if self.model.isRefreshing, count == 0 {
            return String(localized: "Loading sessions")
        }
        if count == 0 {
            return String(localized: "No sessions")
        }
        return String(AttributedString(localized: "^[\(count) session](inflect: true)").characters)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawSidebarPalette.muted)
                .accessibilityHidden(true)
            TextField(String(localized: "Search sessions"), text: self.$searchText)
                .font(OpenClawType.subhead)
                .foregroundStyle(OpenClawSidebarPalette.textStrong)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(self.$isSearchFocused)
                .submitLabel(.search)
                .accessibilityIdentifier("AppShell.Sessions.Search")
            if !self.searchText.isEmpty {
                Button(action: self.clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(OpenClawType.subhead)
                        .foregroundStyle(OpenClawSidebarPalette.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear session search"))
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
            }
        }
        .openClawAnimation(value: self.searchText.isEmpty)
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .background(
            OpenClawSidebarPalette.elevated,
            in: RoundedRectangle(cornerRadius: OpenClawProMetric.controlRadius, style: .continuous))
    }

    private func clearSearch() {
        self.searchText = ""
    }

    // MARK: Gateway

    /// Discreet picker: a single line under the search field. With one saved Gateway the
    /// control opens Gateway settings; with several it becomes a menu.
    private var gatewayRow: some View {
        RootSidebarGatewayControl(fallbackName: self.gatewayName, openSettings: self.openGateway)
            .padding(.horizontal, 2)
    }

    // MARK: Status

    @ViewBuilder
    private func statusBlock(layout: SessionsListLayout) -> some View {
        if let errorText = self.model.sessionErrorText {
            Text(verbatim: errorText)
                .font(OpenClawType.captionMedium)
                .foregroundStyle(OpenClawBrand.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(OpenClawMotion.edge(.top, reduceMotion: self.reduceMotion))
        }
        if self.model.isRefreshing, self.model.sessions.isEmpty {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Loading sessions")
                    .font(OpenClawType.captionMedium)
                    .foregroundStyle(OpenClawSidebarPalette.muted)
            }
            .frame(minHeight: 44)
            .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        } else if layout.isEmpty {
            Text(self.emptyText)
                .font(OpenClawType.captionMedium)
                .foregroundStyle(OpenClawSidebarPalette.muted)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        }
    }

    private var emptyText: String {
        let query: String = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "No sessions")
        }
        return String(localized: "No matching sessions")
    }

    // MARK: Sections and rows

    private func sectionView(
        _ section: SessionsListSection,
        selectedKey: String,
        mainKey: String,
        categories: [String]) -> some View
    {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: section.title.uppercased())
                .font(OpenClawType.caption2Bold)
                .foregroundStyle(OpenClawSidebarPalette.muted)
                .tracking(0.5)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            ForEach(Array(section.nodes.enumerated()), id: \.element.id) { (offset: Int, node: ChatSessionSidebarModel.Node) in
                self.row(node, selectedKey: selectedKey, mainKey: mainKey, categories: categories)
                    .openClawEntrance(index: offset)
            }
        }
    }

    private func row(
        _ node: ChatSessionSidebarModel.Node,
        selectedKey: String,
        mainKey: String,
        categories: [String]) -> some View
    {
        let session: OpenClawChatSessionEntry = node.session
        let isSelected: Bool = session.key == selectedKey
        let controlsEnabled: Bool = self.appModel.isOperatorGatewayConnected
        let canArchive: Bool = ChatSessionSidebarModel.canArchiveSession(session, mainSessionKey: mainKey)
        let canDelete: Bool = ChatSessionSidebarModel.canDeleteSession(key: session.key, mainSessionKey: mainKey)
        let actions: SessionsListActions = self.actions
        let swipeActions: [SessionSwipeAction] = actions.swipeActions(for: session, mainSessionKey: mainKey)
        let onOpen: () -> Void = { self.open(session) }
        let onFork: () -> Void = { actions.fork(session) }
        return SessionsListRow(node: node, isSelected: isSelected, onOpen: onOpen)
            .commandSessionActions(
                session: session,
                mainSessionKey: mainKey,
                categories: categories,
                isEnabled: controlsEnabled,
                canArchive: canArchive,
                canDelete: canDelete,
                performMutation: actions.performMutation,
                fork: onFork)
            .sessionSwipeActions(swipeActions, isEnabled: controlsEnabled)
    }

    private func open(_ session: OpenClawChatSessionEntry) {
        self.isSearchFocused = false
        self.appModel.openChat(sessionKey: session.key)
        self.openChat()
    }
}
