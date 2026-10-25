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

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.unavailable = false
            self.state = .failed(NativeGateway.offlineMessage)
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

struct NativeActivityScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = NativeActivityModel()
    @State private var search = ""
    @State private var kindSelection: String = NGFilterID.all
    @State private var selected: NativeActivityEvent?
    @State private var copiedTick = 0
    @State private var showCopied = false
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    private var filterItems: [NGFilterBar.Item] {
        [
            NGFilterBar.Item(id: NGFilterID.all, title: String(localized: "All"), systemImage: "square.grid.2x2"),
            NGFilterBar.Item(id: "agent_run", title: String(localized: "Runs"), systemImage: "sparkles"),
            NGFilterBar.Item(
                id: "tool_action",
                title: String(localized: "Tools"),
                systemImage: "wrench.and.screwdriver"),
            NGFilterBar.Item(id: "message", title: String(localized: "Messages"), systemImage: "bubble.left"),
        ]
    }

    var body: some View {
        NavigationStack {
            self.content
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !self.model.unavailable {
                        NGFilterBar(items: self.filterItems, selection: self.$kindSelection)
                    }
                }
                .background { OpenClawProBackground() }
                .nativeChrome(title: self.title, sidebar: self.headerSidebarAction)
                .toolbar { self.filterToolbar }
                .searchable(text: self.$search, prompt: Text("Search activity"))
                .navigationDestination(item: self.$selected) { event in
                    NativeActivityDetailView(event: event)
                }
                .overlay(alignment: .bottom) { self.copiedToast }
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        .onChange(of: self.kindSelection) { _, newValue in
            self.model.kind = (newValue == NGFilterID.all) ? nil : newValue
            Task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        }
        .onChange(of: self.model.failedOnly) { _, _ in
            Task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        }
        .sensoryFeedback(.selection, trigger: self.model.failedOnly)
        .sensoryFeedback(.success, trigger: self.copiedTick)
    }

    // MARK: State

    @ViewBuilder
    private var content: some View {
        if self.model.unavailable {
            NGUnavailableState(
                systemImage: "waveform.path.ecg",
                title: String(localized: "Activity unavailable on this Gateway"),
                message: String(localized: "This Gateway does not offer the activity feed."),
                retry: { await self.model.load(appModel: self.appModel, showSpinner: true) })
        } else {
            switch self.model.state {
            case .idle, .loading:
                NGSkeletonList()
            case let .failed(message):
                NGErrorState(
                    message: message,
                    retry: { await self.model.load(appModel: self.appModel, showSpinner: true) })
            case let .loaded(events):
                self.feed(events)
            }
        }
    }

    private func filtered(_ events: [NativeActivityEvent]) -> [NativeActivityEvent] {
        let query = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return events }
        return events.filter { $0.matches(query) }
    }

    @ViewBuilder
    private func feed(_ events: [NativeActivityEvent]) -> some View {
        let visible: [NativeActivityEvent] = self.filtered(events)
        let days: [NativeActivityDay] = NativeActivityGrouping.days(visible)
        List {
            if !visible.isEmpty {
                Section {
                    NGSummaryHeader(items: self.metrics(visible))
                        .ngCardRow()
                    NativeActivityChart(days: days)
                        .padding(12)
                        .ngCardSurface()
                        .ngCardRow()
                }
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.events) { event in
                        self.row(event, isLast: event.id == visible.last?.id)
                    }
                } header: {
                    Text(verbatim: day.title)
                        .font(OpenClawType.subheadSemiBold)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            if self.model.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityLabel(Text("Loading"))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await self.model.load(appModel: self.appModel, showSpinner: false) }
        .openClawAnimation(value: visible.count)
        .overlay {
            if days.isEmpty {
                self.emptyState
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !self.search.isEmpty {
            ContentUnavailableView.search(text: self.search)
        } else {
            OpenClawEmptyState(
                systemImage: "waveform.path.ecg",
                title: "No recent activity",
                message: "Runs, tool calls and messages show up here as they happen.")
        }
    }

    private func metrics(_ events: [NativeActivityEvent]) -> [NGMetricItem] {
        let failed: Int = events.filter { $0.isFailure }.count
        let ok: Int = events.filter { $0.status == "succeeded" }.count
        let running: Int = events.filter { $0.status == "started" }.count
        return [
            NGMetricItem(
                id: "total",
                value: events.count,
                label: String(localized: "Events"),
                systemImage: "waveform.path.ecg"),
            NGMetricItem(
                id: "ok",
                value: ok,
                label: String(localized: "Succeeded"),
                systemImage: "checkmark.circle.fill",
                tint: OpenClawBrand.ok),
            NGMetricItem(
                id: "failed",
                value: failed,
                label: String(localized: "Failed"),
                systemImage: "xmark.circle.fill",
                tint: failed > 0 ? OpenClawBrand.danger : Color.secondary),
            NGMetricItem(
                id: "running",
                value: running,
                label: String(localized: "In progress"),
                systemImage: "play.circle.fill",
                tint: OpenClawBrand.info),
        ]
    }

    // MARK: Rows

    private func row(_ event: NativeActivityEvent, isLast: Bool) -> some View {
        Button {
            self.selected = event
        } label: {
            NativeActivityCard(event: event)
        }
        .buttonStyle(.openClawPress)
        .ngCardRow()
        .contextMenu { self.menu(for: event) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) { self.copyAction(for: event) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { self.sessionAction(for: event) }
        .onAppear {
            if isLast {
                Task { await self.model.loadMore(appModel: self.appModel) }
            }
        }
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
        Button {
            self.selected = event
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
            .tint(.indigo)
        }
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        self.copiedTick += 1
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) { self.showCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            OpenClawMotion.perform(reduceMotion: self.reduceMotion) { self.showCopied = false }
        }
    }

    @ViewBuilder
    private var copiedToast: some View {
        if self.showCopied {
            Label("Copied", systemImage: "checkmark")
                .font(OpenClawType.subheadSemiBold)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .openClawGlassCapsule(tint: OpenClawBrand.ok.opacity(0.18))
                .padding(.bottom, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: self.$model.failedOnly) {
                    Label("Failures only", systemImage: "exclamationmark.triangle")
                }
            } label: {
                Image(systemName: self.filterSymbol)
                    .nativeMinimumTapTarget()
            }
            .accessibilityLabel(Text("Filter"))
        }
    }

    private var filterSymbol: String {
        self.model.failedOnly
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }
}

// MARK: - Card

private struct NativeActivityCard: View {
    let event: NativeActivityEvent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            NGIconBadge(systemImage: self.event.symbol, tint: self.event.statusColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: self.event.title)
                    .font(OpenClawType.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle = self.event.subtitle {
                    Text(verbatim: subtitle)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let date = self.event.date {
                    Text(date, format: .dateTime.hour().minute())
                        .font(OpenClawType.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                NGPill(
                    text: self.event.statusLabel,
                    systemImage: self.event.statusSymbol,
                    tint: self.event.statusColor)
            }
        }
        .padding(12)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCardSurface()
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
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

// MARK: - Detail

struct NativeActivityDetailView: View {
    let event: NativeActivityEvent
    @State private var copiedTick = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                self.header
                self.group([
                    ("Action", self.event.action),
                    ("Kind", self.event.kindLabel),
                    ("Time", NativeFormat.dateTime(ms: self.event.occurredAtMs)),
                ])
                self.group([
                    ("Agent", self.event.agentId),
                    ("Channel", self.event.channel),
                    ("Direction", self.event.direction),
                    ("Tool", self.event.toolName),
                    ("Error code", self.event.errorCode),
                ])
                self.group([
                    ("Run ID", self.event.runId),
                    ("Session key", self.event.sessionKey),
                ])
            }
            .padding(OpenClawProMetric.pagePadding)
        }
        .background { OpenClawProBackground() }
        .navigationTitle(self.event.title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: self.copiedTick)
    }

    private var header: some View {
        VStack(spacing: 12) {
            NGIconBadge(systemImage: self.event.symbol, tint: self.event.statusColor, size: 64)
            Text(verbatim: self.event.title)
                .font(OpenClawType.headline)
                .multilineTextAlignment(.center)
            NGPill(
                text: self.event.statusLabel,
                systemImage: self.event.statusSymbol,
                tint: self.event.statusColor)
            if let relative = NativeFormat.relative(ms: self.event.occurredAtMs) {
                Text(verbatim: relative)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .ngCardSurface(radius: 20)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func group(_ rows: [(LocalizedStringKey, String?)]) -> some View {
        let present: [(LocalizedStringKey, String)] = rows.compactMap { item in
            guard let value = item.1, !value.isEmpty else { return nil }
            return (item.0, value)
        }
        if !present.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(present.enumerated()), id: \.offset) { index, item in
                    self.detailRow(item.0, item.1)
                    if index < present.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .ngCardSurface()
        }
    }

    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(OpenClawType.subhead)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(OpenClawType.subhead)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = value
                self.copiedTick += 1
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
