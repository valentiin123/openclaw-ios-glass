import OpenClawChatUI
import OpenClawKit
import SwiftUI

struct CommandCenterTab: View {
    static let recentSessionsFetchLimit = 200

    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let headerTitle = "Overview"
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var dashboardModel: RootSidebarModel
    var openChat: () -> Void
    var openSettings: () -> Void
    var openSessions: () -> Void
    var openApprovals: () -> Void
    var openAutomations: () -> Void
    var openUsage: () -> Void
    /// Opens a session in the full-screen sprite chat (same screen as the Agents tab).
    var openSession: (String) -> Void

    struct WorkItem {
        let icon: String
        let title: String
        let detail: String
        let state: String
        let color: Color
        let isUnread: Bool
        let isPinned: Bool
        var sessionColor: String?
        /// Session key that picks the pixel sprite. nil = the main agent (robot).
        var spriteKey: String?
        /// Playful run state. nil = nothing special going on (idle).
        var runState: AgentTileState?
    }

    var body: some View {
        GeometryReader { geometry in
            self.layout(width: geometry.size.width)
        }
        .navigationTitle(self.headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Layout

    private func layout(width: CGFloat) -> some View {
        let split: Bool = Self.usesSplitSectionsLayout(
            horizontalSizeClass: self.horizontalSizeClass,
            containerWidth: width)
        return ZStack {
            OpenClawProBackground()
            ScrollView {
                self.page(split: split)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func page(split: Bool) -> some View {
        VStack(alignment: .leading, spacing: OverviewMetric.sectionSpacing) {
            self.header
            self.content(split: split)
                .padding(.horizontal, OpenClawProMetric.pagePadding)
        }
        .padding(.top, OpenClawSpace.sm)
        .padding(.bottom, OpenClawSpace.lg)
    }

    private func content(split: Bool) -> some View {
        VStack(alignment: .leading, spacing: OverviewMetric.sectionSpacing) {
            self.attentionTile
                .openClawEntrance(index: 0)
            self.gatewayTile
                .openClawEntrance(index: 1)
            self.statStrip
                .openClawEntrance(index: 2)
            self.sessionBlocks(split: split)
                .openClawEntrance(index: 3)
            self.usageTile
                .openClawEntrance(index: 4)
        }
    }

    @ViewBuilder
    private func sessionBlocks(split: Bool) -> some View {
        if split {
            HStack(alignment: .top, spacing: 12) {
                self.agentSessionSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                self.recentSessions
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: OverviewMetric.sectionSpacing) {
                self.agentSessionSection
                self.recentSessions
            }
        }
    }

    // MARK: Header (opaque surfaces, no glass)

    private var header: some View {
        OverviewHeader(
            title: "Overview",
            subtitle: self.gatewaySubtitle,
            trailing: { self.headerButtons })
            .padding(.horizontal, OpenClawProMetric.pagePadding)
    }

    private var headerButtons: some View {
        HStack(spacing: OpenClawSpace.sm) {
            self.moreButton
            self.settingsButton
        }
    }

    @ViewBuilder
    private var moreButton: some View {
        if let action = self.headerSidebarAction {
            OverviewHeaderButton(
                systemName: "ellipsis",
                label: action.accessibilityLabel.text,
                identifier: action.accessibilityIdentifier ?? "",
                action: action.action)
        }
    }

    private var settingsButton: some View {
        OverviewHeaderButton(
            systemName: "gearshape",
            label: Text("Settings"),
            hint: Text("Opens settings"),
            identifier: "AppShell.Overview.Settings",
            action: self.openSettings)
    }

    // MARK: Summary strip

    private var statStrip: some View {
        OverviewStatStrip(
            stats: self.overviewStats,
            hint: String(localized: "Opens Sessions"),
            action: self.openSessions)
    }

    private var overviewStats: [OverviewStat] {
        let sessions: OverviewStat = OverviewStat(
            id: "sessions",
            title: String(localized: "Sessions"),
            value: self.overviewCountText(self.overviewSessions.count))
        let live: OverviewStat = OverviewStat(
            id: "live",
            title: String(localized: "Live"),
            value: self.overviewCountText(self.overviewLiveCount))
        let unread: OverviewStat = OverviewStat(
            id: "unread",
            title: String(localized: "Unread"),
            value: self.overviewCountText(self.overviewUnreadCount))
        let tokens: OverviewStat = OverviewStat(
            id: "tokens",
            title: String(localized: "Tokens"),
            value: self.overviewTokenText)
        return [sessions, live, unread, tokens]
    }

    // MARK: Gateway

    private var gatewayTile: some View {
        OverviewGatewayTile(
            statusTitle: self.gatewayDisplayState.statusPresentation.title,
            statusColor: self.gatewayStatusColor,
            address: self.gatewayAddressText,
            agents: self.gatewayAgentCountText)
    }

    // MARK: Attention

    @ViewBuilder
    private var attentionTile: some View {
        let items: [OverviewAttentionItem] = self.attentionItems
        if !items.isEmpty {
            OverviewAttentionTile(items: items)
        }
    }

    private var attentionItems: [OverviewAttentionItem] {
        var items: [OverviewAttentionItem] = []
        let approvalCount: Int = self.appModel.pendingExecApprovalCount
        let cronCount: Int = self.dashboardModel.failedCronJobCount
            + self.dashboardModel.overdueCronJobCount
        if approvalCount > 0 {
            let approvals: OverviewAttentionItem = OverviewAttentionItem(
                id: "approvals",
                title: String(localized: "Pending approvals"),
                value: approvalCount.formatted(),
                systemImage: "checkmark.shield",
                action: self.openApprovals)
            items.append(approvals)
        }
        if cronCount > 0 {
            let automations: OverviewAttentionItem = OverviewAttentionItem(
                id: "automations",
                title: String(localized: "Automation issues"),
                value: cronCount.formatted(),
                systemImage: "clock.badge.exclamationmark",
                action: self.openAutomations)
            items.append(automations)
        }
        return items
    }

    // MARK: Usage

    @ViewBuilder
    private var usageTile: some View {
        if let usage = self.dashboardModel.usage {
            OverviewUsageTile(
                title: String(localized: "31-day usage"),
                cost: self.usageCostText(usage.totalCost),
                values: self.usageValues(usage.daily ?? []),
                hint: String(localized: "Opens Usage"),
                action: self.openUsage)
        }
    }

    private func usageValues(_ daily: [CostUsageDailyEntryLite]) -> [Double] {
        let recent: [CostUsageDailyEntryLite] = Array(daily.suffix(14))
        var values: [Double] = []
        for entry in recent {
            let cost: Double = entry.totalCost ?? 0
            values.append(max(0, cost))
        }
        return values
    }

    // MARK: Sessions

    private var agentSessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverviewSectionLabel(title: "Agent session")
            self.sessionButton(item: self.defaultChatWorkItem, key: nil)
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverviewSectionLabel(title: "Recent sessions")
            self.sessionErrorLine
            self.recentSessionList
        }
    }

    @ViewBuilder
    private var sessionErrorLine: some View {
        if let sessionErrorText = self.dashboardModel.sessionErrorText {
            Text(verbatim: sessionErrorText)
                .font(OpenClawType.captionMedium)
                .foregroundStyle(OpenClawBrand.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var recentSessionList: some View {
        let sessions: [OpenClawChatSessionEntry] = self.recentSessionPreviewSessions
        if sessions.isEmpty {
            self.emptyTile
        } else {
            VStack(spacing: 8) {
                ForEach(sessions) { session in
                    self.recentSessionTile(session)
                        .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
                }
                self.viewMoreButton
            }
        }
    }

    private var emptyTile: some View {
        let connected: Bool = self.gatewayConnected
        let title: String = connected
            ? String(localized: "No recent sessions")
            : String(localized: "Gateway offline")
        let detail: String = connected
            ? String(localized: "Start a chat and it will appear here.")
            : String(localized: "Connect to the gateway.")
        return OverviewEmptyTile(title: title, detail: detail)
    }

    private func sessionButton(item: WorkItem, key: String?) -> some View {
        Button {
            self.openSessionKey(key)
        } label: {
            CommandSessionRow(item: item)
                .overviewTile()
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
    }

    private func recentSessionTile(_ session: OpenClawChatSessionEntry) -> some View {
        let item: WorkItem = Self.sessionWorkItem(
            for: session,
            currentSessionKey: self.appModel.chatSessionKey)
        let canArchive: Bool = ChatSessionSidebarModel.canArchiveSession(
            session,
            mainSessionKey: self.appModel.mainSessionKey)
        return self.sessionButton(item: item, key: session.key)
            .commandSessionActions(
                session: session,
                mainSessionKey: self.appModel.mainSessionKey,
                categories: self.sessionCategories,
                isEnabled: self.sessionControlsAvailable,
                canArchive: canArchive,
                performMutation: self.performSessionMutation,
                fork: { self.forkSession(session) })
    }

    @ViewBuilder
    private var viewMoreButton: some View {
        if self.hasMoreRecentSessions {
            Button(action: self.openSessions) {
                HStack(spacing: 6) {
                    Text("View More")
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                }
                .font(OpenClawType.subheadBold)
                .foregroundStyle(OpenClawBrand.accent)
                .frame(maxWidth: .infinity, minHeight: OverviewMetric.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }


    private func usageCostText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: "USD"))
    }

    private var overviewSessions: [OpenClawChatSessionEntry] {
        Self.visibleOverviewSessions(self.dashboardModel.sessions, now: self.dashboardModel.now)
    }

    static func visibleOverviewSessions(
        _ sessions: [OpenClawChatSessionEntry],
        now: Date = .now) -> [OpenClawChatSessionEntry]
    {
        sessions.filter {
            SessionStatusScope.active.includes($0, at: now) &&
                !ChatSessionSidebarModel.isHiddenInternalSession($0.key)
        }
    }

    private var overviewLiveCount: Int {
        self.overviewSessions.count { session in
            session.hasActiveRun == true || session.hasActiveSubagentRun == true ||
                session.status?.lowercased() == "running"
        }
    }

    private var overviewUnreadCount: Int {
        self.overviewSessions.count { $0.unread == true }
    }

    private func overviewCountText(_ count: Int) -> String {
        "\(count.formatted())\(self.dashboardModel.isSessionRosterComplete ? "" : "+")"
    }

    private var overviewTokenText: String {
        let summary = RootSidebarModel.tokenUsageSummary(
            for: self.overviewSessions,
            rosterIsComplete: self.dashboardModel.isSessionRosterComplete)
        guard let total = summary.total else { return "n/a" }
        return "\(summary.isPartial ? "~" : "")\(total.formatted(.number.notation(.compactName)))"
    }

    static func usesSplitSectionsLayout(
        horizontalSizeClass: UserInterfaceSizeClass?,
        containerWidth: CGFloat) -> Bool
    {
        guard horizontalSizeClass == .regular else { return false }
        return containerWidth >= 1000
    }

    private var gatewayConnected: Bool {
        self.gatewayDisplayState == .connected
    }

    private var gatewayDisplayState: GatewayDisplayState {
        GatewayStatusBuilder.build(appModel: self.appModel)
    }

    private var gatewayStatusColor: Color {
        let state = self.gatewayDisplayState
        return state == .disconnected ? .secondary : state.statusPresentation.tone.color
    }

    private var gatewayAddressText: String {
        self.appModel.gatewayRemoteAddress?.trimmedNonEmpty
            ?? self.appModel.gatewayServerName?.trimmedNonEmpty
            ?? String(localized: "Unknown")
    }

    private var gatewayAgentCountText: String {
        guard self.gatewayConnected else { return "—" }
        return self.appModel.gatewayAgents.count.formatted()
    }

    private var defaultChatWorkItem: WorkItem {
        let isOpen: Bool = self.appModel.chatSessionKey == self.appModel.mainSessionKey
        let entry: OpenClawChatSessionEntry? = self.effectiveDefaultChatSessionEntry
        let icon: String = isOpen ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.fill"
        let state: String = isOpen ? "open" : "default"
        let color: Color = isOpen ? OpenClawBrand.accent : OpenClawBrand.ok
        let run: AgentTileState = OverviewRunState.state(for: entry)
        return WorkItem(
            icon: icon,
            title: self.appModel.activeAgentName,
            detail: self.defaultChatActivityText,
            state: state,
            color: color,
            isUnread: entry?.unread == true,
            isPinned: entry?.pinned == true,
            sessionColor: entry?.color,
            spriteKey: nil,
            runState: run)
    }

    private var defaultChatActivityText: String {
        let activityAt = self.effectiveDefaultChatSessionEntry?.lastActivityAt ??
            self.effectiveDefaultChatSessionEntry?.updatedAt
        guard let activityAt, activityAt > 0 else {
            return String(localized: "No recent activity")
        }
        return Self.relativeTimeText(forMilliseconds: activityAt)
    }

    private var recentSessionPreviewSessions: [OpenClawChatSessionEntry] {
        CommandSessionGrouping.previewSelection(
            self.effectiveRecentChatSessions,
            currentKey: self.appModel.chatSessionKey)
    }

    private var hasMoreRecentSessions: Bool {
        self.effectiveRecentChatSessions.count > self.recentSessionPreviewSessions.count
    }

    private var sessionCategories: [String] {
        CommandSessionGrouping.categories(
            from: self.effectiveRecentChatSessions,
            knownGroups: SessionGroupStore.load())
    }

    private var effectiveDefaultChatSessionEntry: OpenClawChatSessionEntry? {
        let sessions = self.dashboardModel.sessions
        let mainKey = ChatSessionSidebarModel.selectedSessionKey(
            sessions: sessions,
            currentSessionKey: "main",
            mainSessionKey: self.appModel.mainSessionKey,
            activeAgentID: self.appModel.chatAgentId,
            sessionRoutingContract: self.appModel.chatSessionRoutingContract)
        return sessions.first { $0.key == mainKey }
    }

    private var effectiveRecentChatSessions: [OpenClawChatSessionEntry] {
        self.dashboardModel.sessions.filter {
            SessionStatusScope.active.includes($0, at: self.dashboardModel.now) &&
                Self.isRecentChatSession($0.key, defaultSessionKey: self.appModel.mainSessionKey)
        }
    }

    private var sessionControlsAvailable: Bool {
        !self.appModel.isLocalChatFixtureEnabled && self.appModel.isOperatorGatewayConnected
    }

    private func openSessionKey(_ key: String?) {
        // focusChatSession only: `NodeAppModel.openChat(sessionKey:)` also bumps `openChatRequestID`,
        // which RootTabs turns into the legacy chat destination.
        if let key, !key.isEmpty {
            self.appModel.focusChatSession(key)
            self.openSession(key)
        } else {
            // No key: main session (system chat), unchanged.
            self.appModel.openChat(sessionKey: key)
            self.openChat()
        }
    }

    private func forkSession(_ session: OpenClawChatSessionEntry) {
        Task {
            do {
                let key = try await self.appModel.makeChatTransport().forkSession(
                    parentKey: session.key,
                    fromLastCompleted: session.hasActiveRun == true)
                await self.dashboardModel.refreshSessions(appModel: self.appModel)
                self.openSessionKey(key)
            } catch {
                self.dashboardModel.reportSessionError(error)
            }
        }
    }

    private func performSessionMutation(
        resetActiveSessionKey: String? = nil,
        _ operation: @escaping (any OpenClawChatTransport) async throws -> Void)
    {
        Task {
            do {
                try await operation(self.appModel.makeChatTransport())
                if resetActiveSessionKey == self.appModel.chatSessionKey {
                    self.appModel.focusChatSession(nil)
                }
                await self.dashboardModel.refreshSessions(appModel: self.appModel)
            } catch {
                self.dashboardModel.reportSessionError(error)
            }
        }
    }

    static func sessionWorkItem(
        for session: OpenClawChatSessionEntry,
        currentSessionKey: String,
        now: Date = .now) -> WorkItem
    {
        let isCurrent: Bool = session.key == currentSessionKey
        let icon: String = isCurrent ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.fill"
        let state: String = isCurrent ? "open" : "recent"
        let color: Color = isCurrent ? OpenClawBrand.accent : OpenClawBrand.ok
        let run: AgentTileState = OverviewRunState.state(for: session)
        return WorkItem(
            icon: icon,
            title: Self.sessionTitle(session),
            detail: Self.sessionDetail(session, now: now),
            state: state,
            color: color,
            isUnread: session.unread == true,
            isPinned: session.pinned == true,
            sessionColor: session.color,
            spriteKey: session.key,
            runState: run)
    }

    static func sessionTitle(_ session: OpenClawChatSessionEntry) -> String {
        if let label = session.label?.trimmedNonEmpty {
            return label
        }
        if let displayName = session.displayName?.trimmedNonEmpty {
            return Self.redactedSessionTitle(for: displayName) ?? displayName
        }
        if let autoLabel = session.autoLabel?.trimmedNonEmpty {
            return autoLabel
        }
        if let subject = session.subject?.trimmedNonEmpty {
            return Self.redactedSessionTitle(for: subject) ?? subject
        }
        // Generic key placeholders only after real topic names are absent.
        return self.redactedSessionTitle(for: session.key) ?? session.key
    }

    fileprivate static func redactedSessionTitle(for key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        guard !trimmed.isEmpty else { return nil }
        if lowercased.contains(":ios-") {
            return String(localized: "iOS chat")
        }
        if lowercased.hasPrefix("telegram:") {
            return String(localized: "Telegram chat")
        }
        if lowercased.hasPrefix("user:+") {
            return String(localized: "Direct chat")
        }
        if lowercased.hasPrefix("cron:") {
            return Self.humanizedSessionKey(String(trimmed.dropFirst("cron:".count)))
        }
        return nil
    }

    fileprivate static func humanizedSessionKey(_ key: String) -> String? {
        let words = key
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
        guard !words.isEmpty else { return nil }

        return words
            .map { word in
                switch word.lowercased() {
                case "ai", "api", "ios", "qmd", "url":
                    word.uppercased()
                default:
                    word.prefix(1).uppercased() + String(word.dropFirst())
                }
            }
            .joined(separator: " ")
    }

    static func sessionDetail(_ session: OpenClawChatSessionEntry, now: Date = .now) -> String {
        if session.archived != true, session.isSnoozed(at: now), let milliseconds = session.snoozedUntil {
            let wake = OpenClawChatSessionSnooze.wakeDescription(
                Date(timeIntervalSince1970: milliseconds / 1000), now: now)
            return String(format: String(localized: "Wakes %@"), wake)
        }
        let activityAt = session.lastActivityAt ?? session.updatedAt
        if let activityAt, activityAt > 0 {
            return self.relativeTimeText(forMilliseconds: activityAt, relativeTo: now)
        }
        return session.key
    }

    static func relativeTimeText(
        forMilliseconds milliseconds: Double,
        relativeTo now: Date = .now) -> String
    {
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        guard now.timeIntervalSince(date) >= 60 else {
            return String(localized: "just now")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    nonisolated static func isRecentChatSession(_ key: String, defaultSessionKey: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed == defaultSessionKey { return false }
        let normalized = trimmed.lowercased()
        let defaultBase = self.sessionBaseKey(defaultSessionKey)
        if !normalized.contains(":"),
           self.isDirectSessionBase(normalized, defaultBase: defaultBase)
        {
            return false
        }
        if ChatSessionSidebarModel.isHiddenInternalSession(trimmed) { return false }
        return !self.isAgentDeviceSession(trimmed, defaultSessionKey: defaultSessionKey)
    }

    private nonisolated static func isAgentDeviceSession(_ key: String, defaultSessionKey: String) -> Bool {
        let parts = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0].lowercased() == "agent" else { return false }
        guard parts.count == 3 || parts[3].lowercased() == "thread" else { return false }

        let base = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let defaultKey = self.sessionBaseKey(defaultSessionKey)
        return self.isDirectSessionBase(base, defaultBase: defaultKey)
    }

    private nonisolated static func isDirectSessionBase(_ base: String, defaultBase: String) -> Bool {
        base == defaultBase || base == "main" || base == "global" || base.hasPrefix("node-")
    }

    private nonisolated static func sessionBaseKey(_ key: String) -> String {
        let parts = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0].lowercased() == "agent" else {
            return key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var gatewaySubtitle: String {
        if let server = appModel.gatewayServerName?.trimmedNonEmpty {
            return String(
                format: String(localized: "%@ on %@"),
                self.appModel.activeAgentName,
                server)
        }
        if let address = appModel.gatewayRemoteAddress?.trimmedNonEmpty {
            return String(
                format: String(localized: "%@ via %@"),
                self.appModel.activeAgentName,
                address)
        }
        return self.appModel.gatewayDisplayStatusText
    }
}

enum SessionStatusScope: String, CaseIterable {
    case active
    case snoozed
    case archived

    static func available(isConnected: Bool) -> [Self] {
        isConnected ? self.allCases : [.active, .snoozed]
    }

    var title: String {
        switch self {
        case .active: String(localized: "Active")
        case .snoozed: String(localized: "Snoozed")
        case .archived: String(localized: "Archived")
        }
    }

    func includes(_ session: OpenClawChatSessionEntry, at now: Date) -> Bool {
        switch self {
        case .active: session.archived != true && !session.isSnoozed(at: now)
        case .snoozed: session.archived != true && session.isSnoozed(at: now)
        case .archived: session.archived == true
        }
    }
}

struct CommandSessionsScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum GroupEditor: Equatable {
        case rename(String)
        case create
    }

    /// Group mutations need the full session store, not a recency window.
    private static let groupMemberFetchLimit = 10000

    @State private var sessions: [OpenClawChatSessionEntry] = []
    @State private var isLoading = false
    @State private var loadErrorText: String?
    @State private var statusScope: SessionStatusScope = .active
    @State private var now: Date = .now
    @State private var knownGroups = SessionGroupStore.load()
    @State private var groupEditor: GroupEditor?
    @State private var groupDraftText = ""
    @State private var groupPendingDelete: String?
    let headerSidebarAction: OpenClawSidebarHeaderAction?
    let openChat: () -> Void

    var body: some View {
        ZStack {
            OpenClawProBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    self.header
                    self.sessionsPanel
                }
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .safeAreaPadding(.bottom, OpenClawProMetric.bottomScrollInset)
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: self.refreshID) {
            await self.refreshSessions()
        }
        .onChange(of: self.availableStatusScopes, initial: true) { _, scopes in
            if !scopes.contains(self.statusScope) {
                self.statusScope = .active
            }
        }
        .task(id: self.sessions) {
            self.now = .now
            while let wake = OpenClawChatSessionSnooze.nextWake(in: self.sessions, now: self.now) {
                do {
                    try await Task.sleep(for: .seconds(max(0, wake.timeIntervalSinceNow) + 0.001))
                    try Task.checkCancellation()
                } catch {
                    return
                }
                self.now = .now
            }
        }
        .alert(self.groupEditorTitle, isPresented: self.groupEditorBinding) {
            TextField("Group name", text: self.$groupDraftText)
                .font(OpenClawType.body)
            Button {
                self.commitGroupEditor()
            } label: {
                Text(self.groupEditor == .create
                    ? LocalizedStringKey("Create")
                    : LocalizedStringKey("Save"))
                    .font(OpenClawType.subheadSemiBold)
            }
            Button(role: .cancel) {
                self.groupEditor = nil
            } label: {
                Text("Cancel")
                    .font(OpenClawType.subheadSemiBold)
            }
        }
        .alert(
            "Delete Group?",
            isPresented: self.groupDeleteBinding,
            presenting: self.groupPendingDelete)
        { group in
            Button(role: .destructive) {
                self.deleteGroup(group)
            } label: {
                Text("Delete Group")
                    .font(OpenClawType.subheadSemiBold)
            }
            Button(role: .cancel) {} label: {
                Text("Cancel")
                    .font(OpenClawType.subheadSemiBold)
            }
        } message: { group in
            Text(verbatim: String(
                format: String(
                    localized: "Sessions in \u{201C}%@\u{201D} move back to Ungrouped."),
                group))
                .font(OpenClawType.caption)
        }
    }

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
        .padding(.horizontal, OpenClawProMetric.pagePadding)
    }

    private var sessionsPanel: some View {
        Group {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(verbatim: self.panelTitle)
                        .font(OpenClawType.subheadBold)
                    Spacer(minLength: 8)
                    if self.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 6)

                if self.appModel.isCommandSessionListAvailable || !self.sessions.isEmpty {
                    Picker(selection: self.$statusScope) {
                        ForEach(self.availableStatusScopes, id: \.self) { scope in
                            Text(verbatim: scope.title)
                                .font(OpenClawType.captionMedium)
                                .tag(scope)
                                .accessibilityLabel(scope == .archived
                                    ? String(localized: "Show Archived") : scope.title)
                                .accessibilityIdentifier("Sessions.Status.\(scope.rawValue)")
                        }
                    } label: {
                        Text("Session status")
                            .font(OpenClawType.captionMedium)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("Sessions.StatusScope")
                    .padding(.bottom, 10)
                }

                if let loadErrorText {
                    OverviewEmptyTile(
                        title: String(localized: "Sessions unavailable"),
                        detail: loadErrorText)
                } else if self.visibleSessions.isEmpty {
                    OverviewEmptyTile(
                        title: self.emptyTitle,
                        detail: self.emptyDetailText)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(self.sessionSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if section.showsHeader {
                                    self.sectionHeader(section)
                                }
                                ForEach(section.entries) { session in
                                    self.sessionRow(session)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
    }

    private var headerDetail: String {
        if self.isLoading, self.sessions.isEmpty {
            switch self.statusScope {
            case .active: return String(localized: "Loading recent sessions")
            case .snoozed: return String(localized: "Loading snoozed sessions")
            case .archived: return String(localized: "Loading archived sessions")
            }
        }
        let count = self.visibleSessions.count
        if count == 0 {
            return self.emptyTitle
        }
        return String(
            AttributedString(localized: "^[\(count) session](inflect: true)").characters)
    }

    private var visibleSessions: [OpenClawChatSessionEntry] {
        self.sessions
            .filter { CommandCenterTab.isRecentChatSession(
                $0.key,
                defaultSessionKey: self.appModel.mainSessionKey) }
            // A stale list must still obey the selected scope while its replacement loads.
            .filter { self.statusScope.includes($0, at: self.now) }
    }

    private var sessionSections: [CommandSessionSection] {
        CommandSessionGrouping.sections(from: self.visibleSessions, knownGroups: self.knownGroups)
    }

    private var sessionCategories: [String] {
        CommandSessionGrouping.categories(from: self.sessions, knownGroups: self.knownGroups)
    }

    private var sessionControlsAvailable: Bool {
        !self.appModel.isLocalChatFixtureEnabled && self.appModel.isOperatorGatewayConnected
    }

    private var availableStatusScopes: [SessionStatusScope] {
        SessionStatusScope.available(isConnected: self.appModel.isOperatorGatewayConnected)
    }

    private var emptyTitle: String {
        guard self.appModel.isCommandSessionListAvailable else {
            return String(localized: "Gateway offline")
        }
        switch self.statusScope {
        case .active: return String(localized: "No recent sessions")
        case .snoozed: return String(localized: "No snoozed sessions")
        case .archived: return String(localized: "No archived sessions")
        }
    }

    private var emptyDetailText: String {
        guard self.appModel.isCommandSessionListAvailable else {
            return String(localized: "Connect to the gateway.")
        }
        return self.emptyDetail
    }

    private var emptyDetail: String {
        switch self.statusScope {
        case .active: String(localized: "Start a chat and it will appear here.")
        case .snoozed: String(localized: "Snoozed sessions will appear here until they wake.")
        case .archived: String(localized: "Archived sessions will appear here.")
        }
    }

    private var panelTitle: String {
        switch self.statusScope {
        case .active: String(localized: "Recent sessions")
        case .snoozed: String(localized: "Snoozed sessions")
        case .archived: String(localized: "Archived sessions")
        }
    }

    private var refreshID: String {
        "\(self.appModel.chatViewModelIdentityID):\(self.statusScope.rawValue)"
    }

    @ViewBuilder
    private func sectionHeader(_ section: CommandSessionSection) -> some View {
        let title = Text(section.title)
            .font(OpenClawType.captionSemiBold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        // Group management only applies to custom categories, never the
        // Pinned/Ungrouped built-ins.
        if case let .category(group) = section.id, self.sessionControlsAvailable {
            title.contextMenu {
                self.groupMenu(for: group)
            }
        } else {
            title
        }
    }

    @ViewBuilder
    private func groupMenu(for group: String) -> some View {
        Button {
            self.groupDraftText = group
            self.groupEditor = .rename(group)
        } label: {
            Label("Rename Group…", systemImage: "pencil")
                .font(OpenClawType.subhead)
        }
        Button {
            self.groupDraftText = ""
            self.groupEditor = .create
        } label: {
            Label("New Group…", systemImage: "folder.badge.plus")
                .font(OpenClawType.subhead)
        }
        Button(role: .destructive) {
            self.groupPendingDelete = group
        } label: {
            Label("Delete Group…", systemImage: "trash")
                .font(OpenClawType.subhead)
        }
    }

    private var groupEditorTitle: String {
        self.groupEditor == .create
            ? String(localized: "New Group")
            : String(localized: "Rename Group")
    }

    private var groupEditorBinding: Binding<Bool> {
        Binding(
            get: { self.groupEditor != nil },
            set: { if !$0 { self.groupEditor = nil } })
    }

    private var groupDeleteBinding: Binding<Bool> {
        Binding(
            get: { self.groupPendingDelete != nil },
            set: { if !$0 { self.groupPendingDelete = nil } })
    }

    private func commitGroupEditor() {
        let editor = self.groupEditor
        self.groupEditor = nil
        let name = self.groupDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch editor {
        case let .rename(group):
            guard name != group else { return }
            self.updateStoredGroups { SessionGroupStore.renaming($0, from: group, to: name) }
            self.patchGroupMembers(group, category: name)
        case .create:
            // Header-created groups start empty: stored-list only, no patches.
            self.updateStoredGroups { SessionGroupStore.adding($0, name) }
        case nil:
            break
        }
    }

    private func deleteGroup(_ group: String) {
        self.groupPendingDelete = nil
        self.updateStoredGroups { SessionGroupStore.removing($0, group) }
        self.patchGroupMembers(group, category: nil)
    }

    private func updateStoredGroups(_ transform: ([String]) -> [String]) {
        let updated = transform(SessionGroupStore.load())
        SessionGroupStore.save(updated)
        self.knownGroups = updated
    }

    /// Reassigns (or clears, when `category` is nil) every member of `group`.
    private func patchGroupMembers(_ group: String, category: String?) {
        self.performMutation { transport in
            // Enumerate every member, not the windowed visible list: archived
            // members must follow a rename so restores land in the new group.
            // The gateway defaults an absent `limit` to 100 rows, so ask for
            // an explicitly high limit to cover the whole store.
            let active = try await transport.listSessions(
                limit: Self.groupMemberFetchLimit,
                archived: false)
            let archived = try await transport.listSessions(
                limit: Self.groupMemberFetchLimit,
                archived: true)
            let members = CommandSessionGrouping.members(
                of: group,
                in: [active.sessions, archived.sessions])
            // Best effort: one failed patch must not abandon the rest of the
            // group; the first error still surfaces via performMutation.
            var firstError: (any Error)?
            for member in members {
                do {
                    try await transport.patchSession(
                        key: member.key,
                        expectedSessionID: nil,
                        label: nil,
                        category: .some(category),
                        color: nil,
                        pinned: nil,
                        archived: nil,
                        unread: nil)
                } catch {
                    firstError = firstError ?? error
                }
            }
            if let firstError {
                throw firstError
            }
        }
    }

    private func sessionRow(_ session: OpenClawChatSessionEntry) -> some View {
        let item = CommandCenterTab.sessionWorkItem(
            for: session,
            currentSessionKey: self.appModel.chatSessionKey,
            now: self.now)
        return Button {
            self.openSessionKey(session.key)
        } label: {
            CommandSessionRow(item: item)
                .overviewTile()
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
        .commandSessionActions(
            session: session,
            mainSessionKey: self.appModel.mainSessionKey,
            categories: self.sessionCategories,
            isArchived: session.archived == true,
            isEnabled: self.sessionControlsAvailable,
            canArchive: ChatSessionSidebarModel.canArchiveSession(
                session,
                mainSessionKey: self.appModel.mainSessionKey),
            archivesSession: { self.statusScope != .archived && session.archived != true },
            performMutation: self.performMutation,
            fork: { self.forkSession(session) })
    }

    private func openSessionKey(_ key: String) {
        self.appModel.focusChatSession(key)
        self.dismiss()
        self.openChat()
    }

    private func forkSession(_ session: OpenClawChatSessionEntry) {
        Task {
            do {
                let key = try await self.appModel.makeChatTransport().forkSession(
                    parentKey: session.key,
                    fromLastCompleted: session.hasActiveRun == true)
                await self.refreshSessions()
                self.openSessionKey(key)
            } catch {
                self.loadErrorText = error.localizedDescription
            }
        }
    }

    private func performMutation(
        resetActiveSessionKey: String? = nil,
        _ operation: @escaping (any OpenClawChatTransport) async throws -> Void)
    {
        Task {
            do {
                try await operation(self.appModel.makeChatTransport())
                if resetActiveSessionKey == self.appModel.chatSessionKey {
                    self.appModel.focusChatSession(nil)
                }
                await self.refreshSessions()
            } catch {
                self.loadErrorText = error.localizedDescription
            }
        }
    }

    private func refreshSessions() async {
        // Pick up groups stored by other surfaces (for example the per-session
        // New Group editor) alongside the fresh session list.
        self.knownGroups = SessionGroupStore.load()
        let requestedScope = self.statusScope
        let requestsArchived = requestedScope == .archived
        let sourceGatewayID = self.appModel.chatTranscriptCacheGatewayID
        let sourceAgentID = self.appModel.chatDeliveryAgentId
        self.isLoading = true
        self.loadErrorText = nil
        defer {
            if requestedScope == self.statusScope { self.isLoading = false }
        }

        do {
            let roster = try await self.appModel.loadChatSessionRoster(
                limit: CommandCenterTab.recentSessionsFetchLimit,
                archived: requestsArchived)
            guard !Task.isCancelled, requestedScope == self.statusScope else { return }
            self.sessions = roster.sessions
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requestedScope == self.statusScope else { return }
            let cached = requestsArchived ? [] : await self.appModel.loadCachedChatSessions(
                gatewayID: sourceGatewayID,
                agentID: sourceAgentID)
            guard !Task.isCancelled, requestedScope == self.statusScope else { return }
            self.sessions = cached
            self.loadErrorText = self.sessions.isEmpty ? "Try again after the gateway reconnects." : nil
        }
    }
}

extension NodeAppModel {
    fileprivate var isCommandSessionListAvailable: Bool {
        self.isLocalChatFixtureEnabled || self.isOperatorGatewayConnected
    }
}
