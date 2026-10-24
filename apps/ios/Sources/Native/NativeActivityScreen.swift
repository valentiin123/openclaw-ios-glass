import Charts
import Observation
import SwiftUI
import UIKit

// MARK: - Model

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

    var statusColor: Color {
        switch self.status {
        case "succeeded": return OpenClawBrand.ok
        case "failed", "blocked", "timed_out": return OpenClawBrand.danger
        case "cancelled": return OpenClawBrand.warn
        case "started": return OpenClawBrand.info
        default: return .secondary
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

struct NativeActivityDay: Identifiable {
    let id: String
    let date: Date
    let events: [NativeActivityEvent]
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

@MainActor
@Observable
final class NativeActivityModel {
    var state: NativeLoadState<[NativeActivityEvent]> = .idle
    var kind: String?
    var failedOnly = false
    private(set) var nextCursor: String?
    private(set) var isLoadingMore = false

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(NativeGateway.offlineMessage)
            return
        }
        if showSpinner { self.state = .loading }
        do {
            let page = try await self.fetch(appModel: appModel, cursor: nil, base: 0)
            self.nextCursor = page.cursor
            self.state = .loaded(page.events)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    func loadMore(appModel: NodeAppModel) async {
        guard !self.isLoadingMore, let cursor = self.nextCursor else { return }
        guard case let .loaded(current) = self.state else { return }
        self.isLoadingMore = true
        defer { self.isLoadingMore = false }
        do {
            let page = try await self.fetch(appModel: appModel, cursor: cursor, base: current.count)
            self.nextCursor = page.cursor
            self.state = .loaded(current + page.events)
        } catch {
            self.nextCursor = nil
        }
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
        let obj = try await NativeGateway.send(appModel: appModel, method: "audit.activity.list", params: params)
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
    @State private var model = NativeActivityModel()
    @State private var search = ""
    @State private var kindSelection: String = "all"
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    private static let kindSegments: [NativeSegment<String>] = [
        NativeSegment(id: "all", title: String(localized: "All")),
        NativeSegment(id: "agent_run", title: String(localized: "Runs")),
        NativeSegment(id: "tool_action", title: String(localized: "Tools")),
        NativeSegment(id: "message", title: String(localized: "Messages")),
    ]

    var body: some View {
        NavigationStack {
            NativeStateView(
                state: self.model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No recent activity",
                emptyIcon: "waveform.path.ecg",
                retry: { await self.model.load(appModel: self.appModel, showSpinner: true) })
            { events in
                self.list(events)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                NativeSegmentedBar(segments: Self.kindSegments, selection: self.$kindSelection)
            }
            .nativeChrome(title: self.title, sidebar: self.headerSidebarAction)
            .toolbar { self.filterToolbar }
            .searchable(text: self.$search, prompt: Text("Search activity"))
            .navigationDestination(for: NativeActivityEvent.self) { event in
                NativeActivityDetailView(event: event)
            }
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        .onChange(of: self.kindSelection) { _, newValue in
            self.model.kind = (newValue == "all") ? nil : newValue
            Task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        }
        .onChange(of: self.model.failedOnly) { _, _ in
            Task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        }
    }

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: self.$model.failedOnly) {
                    Label("Failures only", systemImage: "exclamationmark.triangle")
                }
            } label: {
                Image(systemName: self.filterSymbol)
            }
            .accessibilityLabel(Text("Filter"))
        }
    }

    private var filterSymbol: String {
        self.model.failedOnly
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }

    private func filtered(_ events: [NativeActivityEvent]) -> [NativeActivityEvent] {
        let query = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return events }
        return events.filter { $0.matches(query) }
    }

    @ViewBuilder
    private func list(_ events: [NativeActivityEvent]) -> some View {
        let visible: [NativeActivityEvent] = self.filtered(events)
        let days: [NativeActivityDay] = NativeActivityGrouping.days(visible)
        List {
            if days.count > 0 {
                Section {
                    NativeActivityChart(days: days)
                } header: {
                    Text("Activity per day")
                }
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.events) { event in
                        NavigationLink(value: event) {
                            NativeActivityRow(event: event)
                        }
                        .contextMenu { self.menu(for: event) }
                        .swipeActions(edge: .leading) { self.copyAction(for: event) }
                    }
                } header: {
                    Text(verbatim: day.date.formatted(.dateTime.weekday(.wide).month().day()))
                }
            }
            if self.model.nextCursor != nil {
                self.loadMoreRow
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await self.model.load(appModel: self.appModel, showSpinner: false) }
        .overlay {
            if days.isEmpty {
                ContentUnavailableView.search(text: self.search)
            }
        }
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowBackground(Color.clear)
        .task { await self.model.loadMore(appModel: self.appModel) }
        .accessibilityLabel(Text("Loading"))
    }

    @ViewBuilder
    private func menu(for event: NativeActivityEvent) -> some View {
        if let runId = event.runId {
            Button {
                UIPasteboard.general.string = runId
            } label: {
                Label("Copy run ID", systemImage: "doc.on.doc")
            }
        }
        if let sessionKey = event.sessionKey {
            Button {
                UIPasteboard.general.string = sessionKey
            } label: {
                Label("Copy session key", systemImage: "key")
            }
        }
    }

    @ViewBuilder
    private func copyAction(for event: NativeActivityEvent) -> some View {
        if let runId = event.runId ?? event.sessionKey {
            Button {
                UIPasteboard.general.string = runId
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.blue)
        }
    }
}

/// Stacked daily bars: succeeded vs failed vs other. Pure content, no glass.
private struct NativeActivityChart: View {
    let days: [NativeActivityDay]

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

    var body: some View {
        Chart(self.buckets) { bucket in
            BarMark(
                x: .value("Day", bucket.date, unit: .day),
                y: .value("Events", bucket.count))
                .foregroundStyle(by: .value("Status", bucket.series))
        }
        .chartForegroundStyleScale([
            self.okName: OpenClawBrand.ok,
            self.failedName: OpenClawBrand.danger,
            self.otherName: Color.secondary.opacity(0.5),
        ])
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(minHeight: 160)
        .padding(.vertical, 6)
        .accessibilityLabel(Text("Activity per day"))
        .accessibilityValue(Text(self.summary))
    }

    private var summary: String {
        let total: Int = self.days.reduce(0) { $0 + $1.events.count }
        let failed: Int = self.days.reduce(0) { $0 + $1.events.filter { $0.isFailure }.count }
        return String(localized: "\(total) events, \(failed) failed")
    }
}

extension NativeActivityEvent: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

// MARK: - Row + detail

private struct NativeActivityRow: View {
    let event: NativeActivityEvent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: self.event.symbol)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(self.event.statusColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.event.title)
                    .font(OpenClawType.body)
                    .lineLimit(2)
                if let subtitle = self.event.subtitle {
                    Text(verbatim: subtitle)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let date = self.event.date {
                    Text(date, format: .dateTime.hour().minute())
                        .font(OpenClawType.caption)
                        .foregroundStyle(.secondary)
                }
                NativeBadge(text: self.event.statusLabel, color: self.event.statusColor)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NativeActivityDetailView: View {
    let event: NativeActivityEvent

    var body: some View {
        List {
            Section {
                self.row("Action", self.event.action)
                self.row("Status", self.event.statusLabel)
                self.row("Kind", NativeFormat.humanized(self.event.kind))
                self.row("Time", NativeFormat.dateTime(ms: self.event.occurredAtMs))
            }
            Section {
                self.row("Agent", self.event.agentId)
                self.row("Channel", self.event.channel)
                self.row("Direction", self.event.direction)
                self.row("Tool", self.event.toolName)
                self.row("Error code", self.event.errorCode)
            }
            Section {
                self.row("Run ID", self.event.runId)
                self.row("Session key", self.event.sessionKey)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(self.event.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent {
                Text(verbatim: value)
                    .font(OpenClawType.subhead)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(label).font(OpenClawType.body)
            }
        }
    }
}
