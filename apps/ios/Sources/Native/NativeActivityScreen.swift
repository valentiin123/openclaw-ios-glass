import Charts
import Observation
import SwiftUI
import UIKit

// MARK: - Model types

struct NativeActivityEvent: Identifiable, Equatable {
    let id: String
    let action: String
    let kind: String
    let status: String
    let agentId: String?
    let channel: String?
    let sessionKey: String?
    let runId: String?
    let toolName: String?
    let direction: String?
    let errorCode: String?
    let occurredAtMs: Int?

    init(json e: [String: Any], index: Int) {
        let kind: String = e.string("kind") ?? e.string("eventType") ?? "event"
        let action: String = e.string("action") ?? kind
        self.id = e.string("eventId") ?? "event-\(index)"
        self.action = action
        self.kind = kind
        self.status = e.string("status") ?? "unknown"
        self.agentId = e.string("agentId")
        self.channel = e.string("channel")
        self.sessionKey = e.string("sessionKey")
        self.runId = e.string("runId")
        self.toolName = e.string("toolName")
        self.direction = e.string("direction")
        self.errorCode = e.string("errorCode")
        self.occurredAtMs = e.int("occurredAt")
    }

    var title: String {
        if let toolName, !toolName.isEmpty { return toolName }
        return NativeFormat.humanized(self.action)
    }

    var subtitle: String? {
        NativeFormat.joined([self.agentId, self.channel])
    }

    var symbol: String {
        switch self.kind {
        case "agent_run": return "sparkles"
        case "tool_action": return "wrench.and.screwdriver"
        case "message":
            return self.direction == "inbound" ? "arrow.down.left.circle" : "arrow.up.right.circle"
        default: return "waveform.path.ecg"
        }
    }

    var kindLabel: String {
        switch self.kind {
        case "agent_run": return String(localized: "Run")
        case "tool_action": return String(localized: "Tool")
        case "message": return String(localized: "Message")
        default: return NativeFormat.humanized(self.kind).capitalized
        }
    }

    var statusColor: Color {
        switch self.status {
        case "succeeded": return OpenClawBrand.ok
        case "failed", "blocked", "timed_out": return OpenClawBrand.danger
        case "cancelled": return OpenClawBrand.warn
        case "started": return OpenClawBrand.info
        default: return .secondary
        }
    }

    /// Every status has its own symbol so state never relies on color alone.
    var statusSymbol: String {
        switch self.status {
        case "succeeded": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        case "blocked": return "hand.raised.fill"
        case "timed_out": return "clock.badge.exclamationmark"
        case "cancelled": return "slash.circle"
        case "started": return "play.circle.fill"
        default: return "questionmark.circle"
        }
    }

    var statusLabel: String {
        NativeFormat.humanized(self.status).capitalized
    }

    var isFailure: Bool {
        self.status == "failed" || self.status == "blocked" || self.status == "timed_out"
    }

    var date: Date? {
        NativeFormat.date(ms: self.occurredAtMs)
    }

    func matches(_ query: String) -> Bool {
        let haystack: [String?] = [self.title, self.action, self.agentId, self.channel, self.sessionKey, self.toolName]
        for value in haystack {
            if let value, value.localizedCaseInsensitiveContains(query) { return true }
        }
        return false
    }
}

extension NativeActivityEvent: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

struct NativeActivityDay: Identifiable {
    let id: String
    let date: Date
    let events: [NativeActivityEvent]

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self.date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(self.date) { return String(localized: "Yesterday") }
        return self.date.formatted(.dateTime.weekday(.wide).month().day())
    }
}

enum NativeActivityGrouping {
    static func days(_ events: [NativeActivityEvent]) -> [NativeActivityDay] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [NativeActivityEvent]] = [:]
        for event in events {
            let date: Date = event.date ?? Date.distantPast
            let day: Date = calendar.startOfDay(for: date)
            if buckets[day] == nil {
                order.append(day)
                buckets[day] = []
            }
            buckets[day]?.append(event)
        }
        var result: [NativeActivityDay] = []
        for day in order {
            let items: [NativeActivityEvent] = buckets[day] ?? []
            result.append(NativeActivityDay(id: "\(day.timeIntervalSince1970)", date: day, events: items))
        }
        return result
    }
}

// MARK: - Model

/// Loads the audit activity feed. Method `audit.activity.list` (scope operator.read) is declared in
/// packages/gateway-protocol/src/schema/audit-activity.ts; filters: kind, status, cursor, limit (<= 500).
@MainActor
@Observable
final class NativeActivityModel {
    var state: NativeLoadState<[NativeActivityEvent]> = .idle
    var kind: String?
    var failedOnly = false
    var unavailable = false
    private(set) var nextCursor: String?
    private(set) var isLoadingMore = false
    private var generation = 0

    static let listMethod: String = "audit.activity.list"

    /// Automatic load: waits for the operator connection (shows the loading state, no error) and retries
    /// up to `maxRetries` times with a short delay after a failure.
    func loadWithRetry(appModel: NodeAppModel, maxRetries: Int = 2) async {
        var attempt: Int = 0
        while true {
            await self.load(appModel: appModel, showSpinner: true)
            guard case .failed = self.state, attempt < maxRetries, !Task.isCancelled else { return }
            attempt += 1
            self.state = .loading
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
            if Task.isCancelled { return }
        }
    }

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            // Not connected yet: keep what is shown, otherwise show loading (no network error at startup).
            self.unavailable = false
            if case .loaded = self.state { return }
            self.state = .loading
            return
        }
        self.generation += 1
        let current: Int = self.generation
        if showSpinner { self.state = .loading }

        if await Self.isAdvertisedMissing(appModel: appModel) {
            guard current == self.generation else { return }
            self.unavailable = true
            self.state = .idle
            return
        }
        do {
            let page = try await self.fetch(appModel: appModel, cursor: nil, base: 0)
            guard current == self.generation else { return }
            self.unavailable = false
            self.nextCursor = page.cursor
            self.state = .loaded(page.events)
        } catch is CancellationError {
            return
        } catch {
            guard current == self.generation else { return }
            if WorkboardErrors.isUnknownMethod(error) {
                self.unavailable = true
                self.state = .idle
                return
            }
            self.unavailable = false
            self.state = .failed(error.localizedDescription)
        }
    }

    func loadMore(appModel: NodeAppModel) async {
        guard !self.isLoadingMore, let cursor = self.nextCursor else { return }
        guard case let .loaded(existing) = self.state else { return }
        let current: Int = self.generation
        self.isLoadingMore = true
        defer { self.isLoadingMore = false }
        do {
            let page = try await self.fetch(appModel: appModel, cursor: cursor, base: existing.count)
            guard current == self.generation else { return }
            self.nextCursor = page.cursor
            self.state = .loaded(existing + page.events)
        } catch {
            self.nextCursor = nil
        }
    }

    /// True only when the Gateway positively says it does not advertise the method.
    private static func isAdvertisedMissing(appModel: NodeAppModel) async -> Bool {
        let session = appModel.operatorSession
        guard let route = await session.currentRoute() else { return false }
        let listed: Bool? = await session.supportsServerMethod(Self.listMethod, ifCurrentRoute: route)
        return listed == false
    }

    private func fetch(
        appModel: NodeAppModel,
        cursor: String?,
        base: Int) async throws -> (events: [NativeActivityEvent], cursor: String?)
    {
        var params: [String: Any] = ["limit": 100]
        if let kind = self.kind { params["kind"] = kind }
        if self.failedOnly { params["status"] = "failed" }
        if let cursor { params["cursor"] = cursor }
        let obj = try await NativeGateway.send(appModel: appModel, method: Self.listMethod, params: params)
        let root = obj as? [String: Any]
        let raw: [[String: Any]] = root?.array("events") ?? []
        var events: [NativeActivityEvent] = []
        for (offset, item) in raw.enumerated() {
            events.append(NativeActivityEvent(json: item, index: base + offset))
        }
        return (events, root?.string("nextCursor"))
    }
}

// MARK: - Screen

/// Activity feed. One column, nothing stacked: [shell header] -> [one filter line] -> [feed].
/// The feed is a plain list grouped by day with sober rows (state glyph, title, detail, time).
/// The summary and the charts sit at the top of the list, charts collapsed by default.
struct NativeActivityScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: NativeActivityModel = NativeActivityModel()
    @State private var search: String = ""
    @State private var kindSelection: String = NGFilterID.all
    @State private var selected: NativeActivityEvent?
    @State private var showInsights: Bool = false
    @State private var toast: GlassToastModel = GlassToastModel()
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    private var chipItems: [ActivityChipItem] {
        let all: ActivityChipItem = ActivityChipItem(
            id: NGFilterID.all,
            title: String(localized: "All"),
            count: nil,
            systemImage: nil)
        let runs: ActivityChipItem = ActivityChipItem(
            id: "agent_run",
            title: String(localized: "Runs"),
            count: nil,
            systemImage: nil)
        let tools: ActivityChipItem = ActivityChipItem(
            id: "tool_action",
            title: String(localized: "Tools"),
            count: nil,
            systemImage: nil)
        let messages: ActivityChipItem = ActivityChipItem(
            id: "message",
            title: String(localized: "Messages"),
            count: nil,
            systemImage: nil)
        return [all, runs, tools, messages]
    }

    var body: some View {
        NavigationStack {
            self.page
                .navigationDestination(item: self.$selected) { (event: NativeActivityEvent) in
                    NativeActivityDetailView(event: event)
                }
        }
        .task(id: self.appModel.isOperatorGatewayConnected) {
            await self.model.loadWithRetry(appModel: self.appModel)
        }
        .onChange(of: self.kindSelection) { _, newValue in
            self.model.kind = (newValue == NGFilterID.all) ? nil : newValue
            Task { await self.reload(spinner: true) }
        }
        .onChange(of: self.model.failedOnly) { _, _ in
            Task { await self.reload(spinner: true) }
        }
        .sensoryFeedback(.selection, trigger: self.model.failedOnly)
    }

    private var page: some View {
        VStack(spacing: 0) {
            ActivityHeaderSlot()
            self.filterLine
            self.content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { OpenClawProBackground() }
        .activityNavigationChrome(title: self.title, sidebar: self.headerSidebarAction)
        .glassToastHost(self.toast)
    }

    // MARK: Filter line

    @ViewBuilder
    private var filterLine: some View {
        if !self.model.unavailable {
            VStack(spacing: 0) {
                ActivityFilterRow(
                    items: self.chipItems,
                    selection: self.$kindSelection,
                    failuresOnly: self.$model.failedOnly,
                    search: self.$search,
                    searchPrompt: "Search activity")
                ActivityHairline()
            }
        }
    }

    // MARK: State

    private func reload(spinner: Bool) async {
        await self.model.load(appModel: self.appModel, showSpinner: spinner)
    }

    private func pullRefresh() async {
        await self.reload(spinner: false)
    }

    @ViewBuilder
    private var content: some View {
        if self.model.unavailable {
            self.unavailableState
        } else {
            switch self.model.state {
            case .idle, .loading:
                ActivitySkeleton()
            case let .failed(message):
                self.errorState(message)
            case let .loaded(events):
                self.feed(events)
            }
        }
    }

    private func actionButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        prominent: Bool,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(ActivityActionButtonStyle(prominent: prominent))
    }

    private func retry() {
        Task { await self.reload(spinner: true) }
    }

    private var unavailableState: some View {
        let title: OpenClawTextValue = .verbatim(String(localized: "Activity unavailable on this Gateway"))
        let message: OpenClawTextValue = .verbatim(String(localized: "This Gateway does not offer the activity feed."))
        return ActivityPlaceholder(refresh: self.pullRefresh) {
            OpenClawEmptyState(systemImage: "waveform.path.ecg", title: title, message: message) {
                self.actionButton("Check again", systemImage: "arrow.clockwise", prominent: false, action: self.retry)
            }
        }
    }

    private func errorState(_ text: String) -> some View {
        let message: OpenClawTextValue = .verbatim(text)
        return ActivityPlaceholder(refresh: self.pullRefresh) {
            OpenClawEmptyState(systemImage: "exclamationmark.triangle", title: "Could not load", message: message) {
                self.actionButton("Retry", systemImage: "arrow.clockwise", prominent: true, action: self.retry)
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if !self.search.isEmpty {
            ContentUnavailableView.search(text: self.search)
        } else if self.model.failedOnly || self.kindSelection != NGFilterID.all {
            OpenClawEmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "Nothing matches these filters",
                message: "Try another kind or include successful events.")
            {
                self.actionButton("Clear filters", systemImage: "xmark.circle", prominent: false, action: self.resetFilters)
            }
        } else {
            OpenClawEmptyState(
                systemImage: "waveform.path.ecg",
                title: "No recent activity",
                message: "Runs, tool calls and messages show up here as they happen.")
        }
    }

    private func resetFilters() {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.kindSelection = NGFilterID.all
            self.model.failedOnly = false
            self.search = ""
        }
    }

    // MARK: Feed

    private func filtered(_ events: [NativeActivityEvent]) -> [NativeActivityEvent] {
        let query: String = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return events }
        return events.filter { $0.matches(query) }
    }

    @ViewBuilder
    private func feed(_ events: [NativeActivityEvent]) -> some View {
        let visible: [NativeActivityEvent] = self.filtered(events)
        if visible.isEmpty {
            ActivityPlaceholder(refresh: self.pullRefresh) {
                self.emptyContent
            }
        } else {
            self.list(visible)
        }
    }

    private func list(_ visible: [NativeActivityEvent]) -> some View {
        let days: [NativeActivityDay] = NativeActivityGrouping.days(visible)
        let lastID: String? = visible.last?.id
        return List {
            self.topBlocks(visible, days: days)
            ForEach(days) { (day: NativeActivityDay) in
                Section {
                    ForEach(Array(day.events.enumerated()), id: \.element.id) { (index: Int, event: NativeActivityEvent) in
                        self.row(event, lastID: lastID, index: index)
                    }
                } header: {
                    ActivitySectionHeader(title: day.title, count: day.events.count)
                }
            }
            self.loadingMoreRow
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await self.pullRefresh() }
        .openClawAnimation(value: visible.count)
        .openClawAnimation(value: self.showInsights)
    }

    @ViewBuilder
    private func topBlocks(_ visible: [NativeActivityEvent], days: [NativeActivityDay]) -> some View {
        ActivitySummaryStrip(stats: self.stats(visible))
            .openClawEntrance(index: 0)
            .activityBlockRow()
        ActivityDisclosureRow(title: "Insights", systemImage: "chart.bar", isExpanded: self.$showInsights)
            .activityBlockRow()
        if self.showInsights {
            NativeActivityChart(days: days)
                .padding(12)
                .activityTile()
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
                .activityBlockRow()
            if NativeActivityAgentChart.hasData(visible) {
                NativeActivityAgentChart(events: visible)
                    .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
                    .activityBlockRow()
            }
        }
    }

    @ViewBuilder
    private var loadingMoreRow: some View {
        if self.model.isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(minHeight: ActivityMetric.minTarget)
            .activityPlainRow()
            .accessibilityLabel(Text("Loading"))
        }
    }

    private func stats(_ events: [NativeActivityEvent]) -> [ActivityStat] {
        let failed: Int = events.filter { $0.isFailure }.count
        let ok: Int = events.filter { $0.status == "succeeded" }.count
        let running: Int = events.filter { $0.status == "started" }.count
        let muted: Color = OpenClawPalette.texteAtténué
        let failedTint: Color = failed > 0 ? OpenClawBrand.danger : muted
        var result: [ActivityStat] = []
        result.append(ActivityStat(id: "total", value: events.count, label: String(localized: "Events"), tint: muted))
        result.append(ActivityStat(id: "ok", value: ok, label: String(localized: "Succeeded"), tint: OpenClawBrand.ok))
        result.append(ActivityStat(id: "failed", value: failed, label: String(localized: "Failed"), tint: failedTint))
        result.append(ActivityStat(
            id: "running",
            value: running,
            label: String(localized: "In progress"),
            tint: OpenClawBrand.info))
        return result
    }

    // MARK: Rows

    private func open(_ event: NativeActivityEvent) {
        self.selected = event
    }

    private func loadMoreIfLast(_ event: NativeActivityEvent, lastID: String?) {
        guard event.id == lastID else { return }
        Task { await self.model.loadMore(appModel: self.appModel) }
    }

    private func row(_ event: NativeActivityEvent, lastID: String?, index: Int) -> some View {
        Button {
            self.open(event)
        } label: {
            NativeActivityRow(event: event)
        }
        .buttonStyle(ActivityRowButtonStyle())
        .openClawEntrance(index: index)
        .activityPlainRow()
        .contextMenu { self.menu(for: event) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) { self.copyAction(for: event) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { self.sessionAction(for: event) }
        .onAppear { self.loadMoreIfLast(event, lastID: lastID) }
    }

    private func copy(_ value: String) {
        GlassClipboard.copy(value, toast: self.toast)
    }

    @ViewBuilder
    private func menu(for event: NativeActivityEvent) -> some View {
        if let runId = event.runId {
            Button {
                self.copy(runId)
            } label: {
                Label("Copy run ID", systemImage: "doc.on.doc")
            }
        }
        if let sessionKey = event.sessionKey {
            Button {
                self.copy(sessionKey)
            } label: {
                Label("Copy session key", systemImage: "key")
            }
        }
        if let agentId = event.agentId {
            Button {
                self.search = agentId
            } label: {
                Label("Filter by agent", systemImage: "person.crop.circle")
            }
        }
        if let channel = event.channel {
            Button {
                self.search = channel
            } label: {
                Label("Filter by channel", systemImage: "bubble.left.and.bubble.right")
            }
        }
        Button {
            self.open(event)
        } label: {
            Label("Details", systemImage: "info.circle")
        }
    }

    @ViewBuilder
    private func copyAction(for event: NativeActivityEvent) -> some View {
        if let runId = event.runId {
            Button {
                self.copy(runId)
            } label: {
                Label("Copy run ID", systemImage: "doc.on.doc")
            }
            .tint(OpenClawBrand.info)
        }
    }

    @ViewBuilder
    private func sessionAction(for event: NativeActivityEvent) -> some View {
        if let sessionKey = event.sessionKey {
            Button {
                self.copy(sessionKey)
            } label: {
                Label("Copy session key", systemImage: "key")
            }
            .tint(OpenClawPalette.accentSecondaire)
        }
    }
}

// MARK: - Row

/// One event: state glyph, title, detail line (kind, agent, channel, error code) and time.
/// Failures also carry a flat tag, so the state never relies on color alone.
private struct NativeActivityRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let event: NativeActivityEvent

    private var detail: String? {
        NativeFormat.joined([self.event.kindLabel, self.event.agentId, self.event.channel, self.event.errorCode])
    }

    var body: some View {
        HStack(alignment: .top, spacing: OpenClawSpace.md) {
            ActivityGlyph(systemImage: self.event.statusSymbol, tint: self.event.statusColor)
                .symbolEffect(.pulse, options: .repeating, isActive: self.event.status == "started" && !self.reduceMotion)
            self.texts
            Spacer(minLength: OpenClawSpace.sm)
            self.trailing
        }
        .openClawAnimation(value: self.event.status)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: ActivityMetric.minTarget, alignment: .leading)
        .overlay(alignment: .bottom) { ActivityHairline() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: self.event.statusLabel))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: self.event.title)
                .font(OpenClawType.subheadMedium)
                .foregroundStyle(OpenClawPalette.texteFort)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let detail = self.detail {
                Text(verbatim: detail)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(OpenClawPalette.texteAtténué)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let date = self.event.date {
                Text(date, format: .dateTime.hour().minute())
                    .font(OpenClawType.caption)
                    .foregroundStyle(OpenClawPalette.texteAtténué)
                    .monospacedDigit()
            }
            if self.event.isFailure {
                ActivityStatusTag(
                    text: self.event.statusLabel,
                    systemImage: self.event.statusSymbol,
                    tint: self.event.statusColor)
            }
        }
    }
}


// MARK: - Chart

/// Stacked daily bars: succeeded vs failed vs other. Pure content, no glass.
private struct NativeActivityChart: View {
    let days: [NativeActivityDay]
    @State private var selectedDate: Date?

    private struct Bucket: Identifiable {
        let id: String
        let date: Date
        let series: String
        let count: Int
    }

    private var okName: String { String(localized: "Succeeded") }
    private var failedName: String { String(localized: "Failed") }
    private var otherName: String { String(localized: "Other") }

    private var buckets: [Bucket] {
        var result: [Bucket] = []
        for day in self.days where day.events.first?.date != nil {
            let failed: Int = day.events.filter { $0.isFailure }.count
            let ok: Int = day.events.filter { $0.status == "succeeded" }.count
            let other: Int = day.events.count - failed - ok
            let entries: [(String, Int)] = [(self.okName, ok), (self.failedName, failed), (self.otherName, other)]
            for (name, count) in entries where count > 0 {
                result.append(Bucket(id: "\(day.id)-\(name)", date: day.date, series: name, count: count))
            }
        }
        return result
    }

    private var selectedDay: NativeActivityDay? {
        guard let selected = self.selectedDate else { return nil }
        return self.days.first { Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    private func tooltipValue(for day: NativeActivityDay) -> String {
        let failed: Int = day.events.filter { $0.isFailure }.count
        return String(localized: "\(day.events.count) events, \(failed) failed")
    }

    var body: some View {
        let bucketList: [Bucket] = self.buckets
        let selected: NativeActivityDay? = self.selectedDay
        return VStack(alignment: .leading, spacing: 8) {
            Text("Activity per day")
                .font(OpenClawType.subheadSemiBold)
                .accessibilityAddTraits(.isHeader)
            Chart {
                ForEach(bucketList) { bucket in
                    BarMark(
                        x: .value("Day", bucket.date, unit: .day),
                        y: .value("Events", bucket.count))
                        .foregroundStyle(by: .value("Status", bucket.series))
                        .cornerRadius(3)
                }
                if let selected {
                    RuleMark(x: .value("Day", selected.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(
                            position: .top,
                            spacing: 4,
                            overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .disabled))
                        {
                            ChartSelectionTooltip(
                                title: selected.date.formatted(.dateTime.weekday(.abbreviated).month().day()),
                                value: self.tooltipValue(for: selected))
                        }
                }
            }
            .chartXSelection(value: self.$selectedDate)
            .chartForegroundStyleScale([
                self.okName: OpenClawBrand.ok,
                self.failedName: OpenClawBrand.danger,
                self.otherName: Color.secondary.opacity(0.5),
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(minHeight: 150)
            .openClawChartReveal()
            .openClawAnimation(value: self.selectedDate)
            .sensoryFeedback(.selection, trigger: self.selectedDay?.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Activity per day"))
        .accessibilityValue(Text(self.summary))
    }

    private var summary: String {
        let total: Int = self.days.reduce(0) { $0 + $1.events.count }
        let failed: Int = self.days.reduce(0) { $0 + $1.events.filter { $0.isFailure }.count }
        return String(localized: "\(total) events, \(failed) failed")
    }
}

/// Events per agent (top 5), horizontal bars split into succeeded / failed / other. Pure content, no glass.
private struct NativeActivityAgentChart: View {
    let events: [NativeActivityEvent]

    private struct Entry: Identifiable {
        let id: String
        let agent: String
        let series: String
        let count: Int
    }

    private var okName: String { String(localized: "Succeeded") }
    private var failedName: String { String(localized: "Failed") }
    private var otherName: String { String(localized: "Other") }

    static func hasData(_ events: [NativeActivityEvent]) -> Bool {
        var seen: Set<String> = []
        for event in events {
            if let agent = event.agentId, !agent.isEmpty { seen.insert(agent) }
        }
        return seen.count >= 2
    }

    private var topAgents: [String] {
        var totals: [String: Int] = [:]
        for event in self.events {
            guard let agent = event.agentId, !agent.isEmpty else { continue }
            totals[agent, default: 0] += 1
        }
        let ranked: [(key: String, value: Int)] = totals.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        return ranked.prefix(5).map { $0.key }
    }

    private var entries: [Entry] {
        let agents: [String] = self.topAgents
        var result: [Entry] = []
        for agent in agents {
            let mine: [NativeActivityEvent] = self.events.filter { $0.agentId == agent }
            let failed: Int = mine.filter { $0.isFailure }.count
            let ok: Int = mine.filter { $0.status == "succeeded" }.count
            let other: Int = mine.count - failed - ok
            let parts: [(String, Int)] = [(self.okName, ok), (self.failedName, failed), (self.otherName, other)]
            for (name, count) in parts where count > 0 {
                result.append(Entry(id: "\(agent)-\(name)", agent: agent, series: name, count: count))
            }
        }
        return result
    }

    var body: some View {
        let list: [Entry] = self.entries
        let rows: Int = self.topAgents.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Activity per agent")
                .font(OpenClawType.subheadSemiBold)
                .accessibilityAddTraits(.isHeader)
            Chart(list) { (entry: Entry) in
                BarMark(
                    x: .value("Events", entry.count),
                    y: .value("Agent", entry.agent))
                    .foregroundStyle(by: .value("Status", entry.series))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                self.okName: OpenClawBrand.ok,
                self.failedName: OpenClawBrand.danger,
                self.otherName: Color.secondary.opacity(0.5),
            ])
            .chartLegend(.hidden)
            .frame(height: CGFloat(max(rows, 1)) * 30 + 24)
            .openClawChartReveal()
        }
        .padding(12)
        .ngCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Activity per agent"))
        .accessibilityValue(Text(verbatim: self.summary))
    }

    private var summary: String {
        let agents: [String] = self.topAgents
        return agents.joined(separator: ", ")
    }
}


// MARK: - Detail

/// Pushed detail of one event. Same language as the list: opaque tiles, hairlines, square glyph.
/// It keeps its own navigation bar (the shell header is only drawn on the root of each section).
struct NativeActivityDetailView: View {
    @State private var toast: GlassToastModel = GlassToastModel()
    let event: NativeActivityEvent

    private struct Fact: Identifiable {
        let id: Int
        let label: LocalizedStringKey
        let value: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: OpenClawSpace.md) {
                self.header
                    .openClawEntrance(index: 0)
                self.group(self.timingFacts, index: 1)
                self.group(self.originFacts, index: 2)
                self.group(self.referenceFacts, index: 3)
            }
            .padding(.horizontal, OpenClawProMetric.pagePadding)
            .padding(.vertical, OpenClawSpace.md)
        }
        .background { OpenClawProBackground() }
        .navigationTitle(self.event.title)
        .navigationBarTitleDisplayMode(.inline)
        .glassToastHost(self.toast)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: OpenClawSpace.md) {
            ActivityGlyph(systemImage: self.event.statusSymbol, tint: self.event.statusColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: self.event.title)
                    .font(OpenClawType.headline)
                    .foregroundStyle(OpenClawPalette.texteFort)
                    .multilineTextAlignment(.leading)
                ActivityStatusTag(
                    text: self.event.statusLabel,
                    systemImage: self.event.statusSymbol,
                    tint: self.event.statusColor)
                self.relativeLine
            }
            Spacer(minLength: 0)
        }
        .padding(OpenClawSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .activityTile()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var relativeLine: some View {
        if let relative = NativeFormat.relative(ms: self.event.occurredAtMs) {
            Text(verbatim: relative)
                .font(OpenClawType.footnote)
                .foregroundStyle(OpenClawPalette.texteAtténué)
        }
    }

    // MARK: Facts

    private var timingFacts: [Fact] {
        let rows: [(LocalizedStringKey, String?)] = [
            ("Action", self.event.action),
            ("Kind", self.event.kindLabel),
            ("Time", NativeFormat.dateTime(ms: self.event.occurredAtMs)),
        ]
        return self.facts(rows, offset: 0)
    }

    private var originFacts: [Fact] {
        let rows: [(LocalizedStringKey, String?)] = [
            ("Agent", self.event.agentId),
            ("Channel", self.event.channel),
            ("Direction", self.event.direction),
            ("Tool", self.event.toolName),
            ("Error code", self.event.errorCode),
        ]
        return self.facts(rows, offset: 100)
    }

    private var referenceFacts: [Fact] {
        let rows: [(LocalizedStringKey, String?)] = [
            ("Run ID", self.event.runId),
            ("Session key", self.event.sessionKey),
        ]
        return self.facts(rows, offset: 200)
    }

    private func facts(_ rows: [(LocalizedStringKey, String?)], offset: Int) -> [Fact] {
        var result: [Fact] = []
        for (index, row) in rows.enumerated() {
            guard let value = row.1, !value.isEmpty else { continue }
            result.append(Fact(id: offset + index, label: row.0, value: value))
        }
        return result
    }

    @ViewBuilder
    private func group(_ facts: [Fact], index: Int) -> some View {
        if !facts.isEmpty {
            VStack(spacing: 0) {
                ForEach(facts) { (fact: Fact) in
                    self.factRow(fact, isFirst: fact.id == facts.first?.id)
                }
            }
            .activityTile()
            .openClawEntrance(index: index)
        }
    }

    private func factRow(_ fact: Fact, isFirst: Bool) -> some View {
        Button {
            GlassClipboard.copy(fact.value, toast: self.toast)
        } label: {
            self.factLabel(fact)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if !isFirst { ActivityHairline() }
        }
        .accessibilityHint(Text("Copies the value"))
    }

    private func factLabel(_ fact: Fact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OpenClawSpace.md) {
            Text(fact.label)
                .font(OpenClawType.subhead)
                .foregroundStyle(OpenClawPalette.texteAtténué)
            Spacer(minLength: OpenClawSpace.sm)
            Text(verbatim: fact.value)
                .font(OpenClawType.subhead)
                .foregroundStyle(OpenClawPalette.texteFort)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, OpenClawSpace.md)
        .padding(.vertical, OpenClawSpace.md)
        .frame(maxWidth: .infinity, minHeight: ActivityMetric.minTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
