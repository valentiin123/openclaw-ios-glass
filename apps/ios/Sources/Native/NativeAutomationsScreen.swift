import Charts
import Foundation
import Observation
import OpenClawKit
import SwiftUI
import UIKit

// MARK: - Model types

/// One cron job, parsed tolerantly from `cron.list` (schema/cron.ts: CronJobSchema).
struct NativeCronJob: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let detail: String?
    let enabled: Bool
    let scheduleText: String
    let agentId: String?
    let nextRunAtMs: Int?
    let lastRunAtMs: Int?
    let lastStatus: String?
    let lastError: String?
    let lastDurationMs: Int?
    let consecutiveErrors: Int
    let isRunning: Bool

    var isFailing: Bool {
        self.lastStatus == "error" || self.lastStatus == "failed" || self.consecutiveErrors > 0
    }

    /// Single display phase so color, icon and label always agree.
    var phase: NativeCronPhase {
        if !self.enabled { return .paused }
        if self.isRunning { return .running }
        if self.isFailing { return .failing }
        return .healthy
    }

    func matches(_ query: String) -> Bool {
        let haystack: String = [self.name, self.detail ?? "", self.scheduleText, self.agentId ?? ""]
            .joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }

    static func parse(_ raw: [String: Any]) -> NativeCronJob? {
        guard let id = raw.string("id"), !id.isEmpty else { return nil }
        let state: [String: Any] = raw.dict("state") ?? [:]
        let name: String = raw.string("displayName") ?? raw.string("name") ?? id
        let status: String? = raw.string("lastRunStatus") ?? state.string("lastRunStatus")
        let lastError: String? = raw.string("lastRunError") ?? state.string("lastError")
        let schedule: [String: Any] = raw.dict("schedule") ?? [:]
        return NativeCronJob(
            id: id,
            name: name,
            detail: raw.string("description"),
            enabled: raw.bool("enabled") ?? true,
            scheduleText: Self.describe(schedule),
            agentId: raw.string("agentId"),
            nextRunAtMs: raw.int("nextRunAtMs") ?? state.int("nextRunAtMs"),
            lastRunAtMs: raw.int("lastRunAtMs") ?? state.int("lastRunAtMs"),
            lastStatus: status,
            lastError: lastError,
            lastDurationMs: state.int("lastDurationMs"),
            consecutiveErrors: state.int("consecutiveErrors") ?? 0,
            isRunning: state.int("runningAtMs") != nil)
    }

    static func describe(_ schedule: [String: Any]) -> String {
        let kind: String = schedule.string("kind") ?? ""
        switch kind {
        case "every":
            let everyMs: Int = schedule.int("everyMs") ?? 0
            let span: String = NativeFormat.duration(ms: everyMs)
            return String(localized: "Every \(span)")
        case "cron":
            let expr: String = schedule.string("expr") ?? "-"
            if let tz = schedule.string("tz"), !tz.isEmpty {
                return "\(expr) (\(tz))"
            }
            return expr
        case "at":
            return schedule.string("at") ?? "-"
        case "event":
            let source: String = schedule.string("source") ?? "-"
            return String(localized: "On event \(source)")
        case "on-exit":
            return String(localized: "When a command exits")
        case "stream":
            return String(localized: "On stream output")
        default:
            return kind.isEmpty ? "-" : kind
        }
    }
}

enum NativeCronPhase {
    case healthy
    case running
    case failing
    case paused

    var label: String {
        switch self {
        case .healthy: String(localized: "Healthy")
        case .running: String(localized: "Running")
        case .failing: String(localized: "Failing")
        case .paused: String(localized: "Paused")
        }
    }

    var systemImage: String {
        switch self {
        case .healthy: "checkmark.circle"
        case .running: "play.circle"
        case .failing: "exclamationmark.triangle"
        case .paused: "pause.circle"
        }
    }

    var tint: Color {
        switch self {
        case .healthy: OpenClawBrand.ok
        case .running: OpenClawBrand.info
        case .failing: OpenClawBrand.danger
        case .paused: OpenClawBrand.warn
        }
    }
}

/// One entry of `cron.runs`. The result shape is parsed tolerantly (`entries`, `runs` or `items`).
struct NativeCronRun: Identifiable, Equatable {
    let id: String
    let status: String
    let summary: String?
    let error: String?
    let runAtMs: Int?
    let durationMs: Int?

    var isFailure: Bool {
        self.status == "error" || self.status == "failed"
    }

    var statusLabel: String {
        switch self.status {
        case "ok": String(localized: "Succeeded")
        case "error", "failed": String(localized: "Failed")
        case "skipped": String(localized: "Skipped")
        default: NativeFormat.humanized(self.status).capitalized
        }
    }

    var systemImage: String {
        switch self.status {
        case "ok": "checkmark.circle.fill"
        case "error", "failed": "xmark.octagon.fill"
        case "skipped": "forward.circle"
        default: "circle.dashed"
        }
    }

    var tint: Color {
        switch self.status {
        case "ok": OpenClawBrand.ok
        case "error", "failed": OpenClawBrand.danger
        case "skipped": OpenClawBrand.warn
        default: Color.secondary
        }
    }

    static func parse(_ raw: [String: Any], index: Int) -> NativeCronRun {
        let at: Int? = raw.int("runAtMs") ?? raw.int("ts")
        let id: String = raw.string("runId") ?? "run-\(at ?? 0)-\(index)"
        return NativeCronRun(
            id: id,
            status: raw.string("status") ?? "unknown",
            summary: raw.string("summary"),
            error: raw.string("error"),
            runAtMs: at,
            durationMs: raw.int("durationMs"))
    }

    static func parseList(_ root: [String: Any]) -> [NativeCronRun] {
        let rows: [[String: Any]]
        let entries: [[String: Any]] = root.array("entries")
        let runs: [[String: Any]] = root.array("runs")
        if !entries.isEmpty {
            rows = entries
        } else if !runs.isEmpty {
            rows = runs
        } else {
            rows = root.array("items")
        }
        var result: [NativeCronRun] = []
        for (offset, row) in rows.enumerated() {
            result.append(NativeCronRun.parse(row, index: offset))
        }
        return result
    }
}

// MARK: - Model

@MainActor
@Observable
final class NativeAutomationsModel {
    var state: NativeLoadState<[NativeCronJob]> = .idle
    var access: NativeOperatorAccess = .none
    var unavailable = false
    var busyIds: Set<String> = []
    var actionError: String?
    var runs: [String: NativeLoadState<[NativeCronRun]>] = [:]
    /// Bumped on every finished action so views can attach haptics.
    var successTick = 0
    var errorTick = 0

    static let listMethod: String = "cron.list"
    static let updateMethod: String = "cron.update"
    static let runMethod: String = "cron.run"
    static let removeMethod: String = "cron.remove"
    static let runsMethod: String = "cron.runs"
    static let methods: [String] = [listMethod, updateMethod, runMethod, removeMethod, runsMethod]
    /// Scopes from src/gateway/methods/core-descriptors.ts: mutations need admin, runs history is read.
    static let mutationScope: String = "operator.admin"
    static let readScope: String = "operator.read"

    var canToggle: Bool { self.access.allows(method: Self.updateMethod, scope: Self.mutationScope) }
    var canRun: Bool { self.access.allows(method: Self.runMethod, scope: Self.mutationScope) }
    var canDelete: Bool { self.access.allows(method: Self.removeMethod, scope: Self.mutationScope) }
    var canReadRuns: Bool {
        self.access.supportedMethods.contains(Self.runsMethod) && self.access.canRead
    }

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
        if showSpinner { self.state = .loading }
        self.access = await NativeOperatorAccess.load(appModel: appModel, methods: Self.methods)
        if await Self.isAdvertisedMissing(appModel: appModel, method: Self.listMethod) {
            self.unavailable = true
            self.state = .idle
            return
        }
        self.unavailable = false
        do {
            let params: [String: Any] = [
                "includeDisabled": true,
                "limit": 200,
                "offset": 0,
                "sortBy": "name",
                "sortDir": "asc",
            ]
            let obj: Any = try await NativeGateway.send(
                appModel: appModel, method: Self.listMethod, params: params)
            let root: [String: Any] = (obj as? [String: Any]) ?? [:]
            let jobs: [NativeCronJob] = root.array("jobs").compactMap(NativeCronJob.parse)
            self.state = .loaded(jobs)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    /// True only when the Gateway positively answers "not advertised"; unknown stays optimistic.
    private static func isAdvertisedMissing(appModel: NodeAppModel, method: String) async -> Bool {
        let session = appModel.operatorSession
        guard let route = await session.currentRoute() else { return false }
        let listed: Bool? = await session.supportsServerMethod(method, ifCurrentRoute: route)
        return listed == false
    }

    func job(id: String) -> NativeCronJob? {
        guard case let .loaded(jobs) = self.state else { return nil }
        return jobs.first { $0.id == id }
    }

    func setEnabled(_ enabled: Bool, job: NativeCronJob, appModel: NodeAppModel) async {
        guard self.canToggle else { return }
        let params: [String: Any] = ["id": job.id, "patch": ["enabled": enabled]]
        await self.mutate(id: job.id, method: Self.updateMethod, params: params, appModel: appModel)
    }

    func runNow(job: NativeCronJob, appModel: NodeAppModel) async {
        guard self.canRun else { return }
        let params: [String: Any] = ["id": job.id, "mode": "force"]
        await self.mutate(id: job.id, method: Self.runMethod, params: params, appModel: appModel)
        if self.canReadRuns { await self.loadRuns(job: job, appModel: appModel) }
    }

    @discardableResult
    func remove(job: NativeCronJob, appModel: NodeAppModel) async -> Bool {
        guard self.canDelete else { return false }
        let params: [String: Any] = ["id": job.id]
        return await self.mutate(id: job.id, method: Self.removeMethod, params: params, appModel: appModel)
    }

    func loadRuns(job: NativeCronJob, appModel: NodeAppModel) async {
        guard self.canReadRuns else { return }
        if self.runs[job.id] == nil { self.runs[job.id] = .loading }
        do {
            let params: [String: Any] = [
                "id": job.id,
                "limit": 20,
                "sortDir": "desc",
                "view": "summary",
            ]
            let obj: Any = try await NativeGateway.send(
                appModel: appModel, method: Self.runsMethod, params: params)
            let root: [String: Any] = (obj as? [String: Any]) ?? [:]
            self.runs[job.id] = .loaded(NativeCronRun.parseList(root))
        } catch is CancellationError {
            return
        } catch {
            self.runs[job.id] = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    private func mutate(
        id: String,
        method: String,
        params: [String: Any],
        appModel: NodeAppModel) async -> Bool
    {
        guard !self.busyIds.contains(id) else { return false }
        self.busyIds.insert(id)
        self.actionError = nil
        var succeeded = false
        do {
            _ = try await NativeGateway.send(
                appModel: appModel, method: method, params: params, timeoutSeconds: 20)
            succeeded = true
        } catch is CancellationError {
            self.busyIds.remove(id)
            return false
        } catch {
            self.actionError = error.localizedDescription
        }
        if succeeded { self.successTick += 1 } else { self.errorTick += 1 }
        self.busyIds.remove(id)
        await self.load(appModel: appModel, showSpinner: false)
        return succeeded
    }
}

// MARK: - Filter

enum NativeAutomationFilter: String, Hashable {
    case all
    case running
    case failing
    case paused

    init(filterID: String) {
        self = NativeAutomationFilter(rawValue: filterID) ?? .all
    }

    var filterID: String {
        self == .all ? NGFilterID.all : self.rawValue
    }

    func includes(_ job: NativeCronJob) -> Bool {
        switch self {
        case .all: true
        case .running: job.enabled && job.isRunning
        case .failing: job.enabled && job.isFailing
        case .paused: !job.enabled
        }
    }
}

// MARK: - Screen

/// Automations list. Same column as the Activity feed, nothing stacked:
/// [shell header] -> [one filter line] -> [list grouped Active / Paused].
/// Rows are sober (state glyph, name, schedule, next run, state tag when it is not healthy).
struct NativeAutomationsScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: NativeAutomationsModel = NativeAutomationsModel()
    @State private var search: String = ""
    @State private var filterID: String = NGFilterID.all
    @State private var pendingDelete: NativeCronJob?
    @State private var selected: NativeCronJob?
    @State private var toast: GlassToastModel = GlassToastModel()
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    private var filter: NativeAutomationFilter {
        NativeAutomationFilter(filterID: self.filterID)
    }

    var body: some View {
        NavigationStack {
            self.page
                .navigationDestination(item: self.$selected) { (job: NativeCronJob) in
                    NativeAutomationDetailView(jobId: job.id, model: self.model)
                }
        }
        .task(id: self.appModel.isOperatorGatewayConnected) {
            await self.model.loadWithRetry(appModel: self.appModel)
        }
        .nativeErrorAlert(self.$model.actionError)
        .confirmationDialog(
            Text("Delete this automation?"),
            isPresented: self.deleteBinding,
            titleVisibility: .visible,
            presenting: self.pendingDelete)
        { (job: NativeCronJob) in
            Button("Delete", role: .destructive) {
                Task { await self.model.remove(job: job, appModel: self.appModel) }
            }
        } message: { (job: NativeCronJob) in
            Text(verbatim: job.name)
        }
        .sensoryFeedback(.success, trigger: self.model.successTick)
        .sensoryFeedback(.error, trigger: self.model.errorTick)
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

    private var deleteBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.pendingDelete != nil },
            set: { shown in
                if !shown { self.pendingDelete = nil }
            })
    }

    private func reload(spinner: Bool) async {
        await self.model.load(appModel: self.appModel, showSpinner: spinner)
    }

    private func pullRefresh() async {
        await self.reload(spinner: false)
    }

    private func retry() {
        Task { await self.reload(spinner: true) }
    }

    // MARK: Filter line

    @ViewBuilder
    private var filterLine: some View {
        if !self.model.unavailable, case let .loaded(jobs) = self.model.state, !jobs.isEmpty {
            VStack(spacing: 0) {
                ActivityFilterRow(
                    items: self.chipItems(jobs),
                    selection: self.$filterID,
                    failuresOnly: nil,
                    search: self.$search,
                    searchPrompt: "Search automations")
                ActivityHairline()
            }
        }
    }

    private func chipItem(_ filter: NativeAutomationFilter, title: String, jobs: [NativeCronJob]) -> ActivityChipItem {
        let count: Int = jobs.filter { filter.includes($0) }.count
        return ActivityChipItem(id: filter.filterID, title: title, count: count, systemImage: nil)
    }

    private func chipItems(_ jobs: [NativeCronJob]) -> [ActivityChipItem] {
        let all: ActivityChipItem = ActivityChipItem(
            id: NativeAutomationFilter.all.filterID,
            title: String(localized: "All"),
            count: jobs.count,
            systemImage: nil)
        let running: ActivityChipItem = self.chipItem(.running, title: String(localized: "Running"), jobs: jobs)
        let failing: ActivityChipItem = self.chipItem(.failing, title: String(localized: "Failing"), jobs: jobs)
        let paused: ActivityChipItem = self.chipItem(.paused, title: String(localized: "Paused"), jobs: jobs)
        return [all, running, failing, paused]
    }

    // MARK: State switch

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
            case let .loaded(jobs):
                if jobs.isEmpty {
                    self.emptyState
                } else {
                    self.list(jobs)
                }
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

    private var unavailableState: some View {
        let title: OpenClawTextValue = .verbatim(String(localized: "Automations unavailable on this Gateway"))
        let message: OpenClawTextValue = .verbatim(String(localized: "The connected Gateway does not offer scheduled jobs."))
        return ActivityPlaceholder(refresh: self.pullRefresh) {
            OpenClawEmptyState(systemImage: "timer", title: title, message: message) {
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

    private var emptyState: some View {
        ActivityPlaceholder(refresh: self.pullRefresh) {
            OpenClawEmptyState(
                systemImage: "timer",
                title: "No automations",
                message: "Scheduled jobs created on the Gateway show up here.")
        }
    }

    @ViewBuilder
    private var noMatches: some View {
        if !self.search.isEmpty {
            ContentUnavailableView.search(text: self.search)
        } else {
            OpenClawEmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "No matching automations",
                message: "Try another filter.")
            {
                self.actionButton("Clear filters", systemImage: "xmark.circle", prominent: false, action: self.resetFilters)
            }
        }
    }

    private func resetFilters() {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.filterID = NGFilterID.all
            self.search = ""
        }
    }

    // MARK: List

    private func searched(_ jobs: [NativeCronJob]) -> [NativeCronJob] {
        let query: String = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return jobs }
        return jobs.filter { $0.matches(query) }
    }

    private func stats(_ jobs: [NativeCronJob]) -> [ActivityStat] {
        let active: Int = jobs.filter { $0.enabled }.count
        let failing: Int = jobs.filter { $0.enabled && $0.isFailing }.count
        let paused: Int = jobs.filter { !$0.enabled }.count
        let muted: Color = OpenClawPalette.texteAtténué
        let failingTint: Color = failing > 0 ? OpenClawBrand.danger : muted
        var result: [ActivityStat] = []
        result.append(ActivityStat(id: "active", value: active, label: String(localized: "Active"), tint: OpenClawBrand.ok))
        result.append(ActivityStat(id: "failing", value: failing, label: String(localized: "Failing"), tint: failingTint))
        result.append(ActivityStat(id: "paused", value: paused, label: String(localized: "Paused"), tint: OpenClawBrand.warn))
        return result
    }

    @ViewBuilder
    private func list(_ jobs: [NativeCronJob]) -> some View {
        let visible: [NativeCronJob] = self.searched(jobs)
        let currentFilter: NativeAutomationFilter = self.filter
        let shown: [NativeCronJob] = visible.filter { currentFilter.includes($0) }
        if shown.isEmpty {
            ActivityPlaceholder(refresh: self.pullRefresh) {
                self.noMatches
            }
        } else {
            self.sections(jobs, shown: shown)
        }
    }

    private func sections(_ jobs: [NativeCronJob], shown: [NativeCronJob]) -> some View {
        let active: [NativeCronJob] = shown.filter { $0.enabled }
        let paused: [NativeCronJob] = shown.filter { !$0.enabled }
        let ids: [String] = shown.map { $0.id }
        return List {
            ActivitySummaryStrip(stats: self.stats(jobs))
                .openClawEntrance(index: 0)
                .activityBlockRow()
            self.section(String(localized: "Active"), jobs: active)
            self.section(String(localized: "Paused"), jobs: paused)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await self.pullRefresh() }
        .openClawAnimation(value: ids)
    }

    @ViewBuilder
    private func section(_ title: String, jobs: [NativeCronJob]) -> some View {
        if !jobs.isEmpty {
            Section {
                ForEach(Array(jobs.enumerated()), id: \.element.id) { (index: Int, job: NativeCronJob) in
                    self.row(job, index: index)
                }
            } header: {
                ActivitySectionHeader(title: title, count: jobs.count)
            }
        }
    }

    private func runNow(_ job: NativeCronJob) {
        Task { await self.model.runNow(job: job, appModel: self.appModel) }
    }

    private func setEnabled(_ enabled: Bool, job: NativeCronJob) {
        Task { await self.model.setEnabled(enabled, job: job, appModel: self.appModel) }
    }

    private func row(_ job: NativeCronJob, index: Int) -> some View {
        let busy: Bool = self.model.busyIds.contains(job.id)
        return Button {
            self.selected = job
        } label: {
            NativeAutomationRow(job: job, isBusy: busy)
        }
        .buttonStyle(ActivityRowButtonStyle())
        .openClawEntrance(index: index)
        .activityPlainRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { self.trailingActions(job) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) { self.leadingAction(job) }
        .contextMenu { self.menu(job) }
        .accessibilityAction(named: Text("Run now")) { self.runNow(job) }
    }

    // MARK: Actions

    private func copy(_ value: String) {
        GlassClipboard.copy(value, toast: self.toast)
    }

    @ViewBuilder
    private func leadingAction(_ job: NativeCronJob) -> some View {
        if self.model.canRun, !self.model.busyIds.contains(job.id) {
            Button {
                self.runNow(job)
            } label: {
                Label("Run now", systemImage: "play.fill")
            }
            .tint(OpenClawBrand.ok)
        }
    }

    @ViewBuilder
    private func toggleButton(_ job: NativeCronJob) -> some View {
        Button {
            self.setEnabled(!job.enabled, job: job)
        } label: {
            if job.enabled {
                Label("Pause", systemImage: "pause.circle")
            } else {
                Label("Resume", systemImage: "play.circle")
            }
        }
    }

    @ViewBuilder
    private func trailingActions(_ job: NativeCronJob) -> some View {
        if self.model.canDelete {
            Button(role: .destructive) {
                self.pendingDelete = job
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        if self.model.canToggle {
            self.toggleButton(job)
                .tint(OpenClawBrand.warn)
        }
    }

    @ViewBuilder
    private func menu(_ job: NativeCronJob) -> some View {
        if self.model.canRun {
            Button {
                self.runNow(job)
            } label: {
                Label("Run now", systemImage: "play.fill")
            }
        }
        if self.model.canToggle {
            self.toggleButton(job)
        }
        Button {
            self.copy(job.id)
        } label: {
            Label("Copy ID", systemImage: "doc.on.doc")
        }
        if self.model.canDelete {
            Divider()
            Button(role: .destructive) {
                self.pendingDelete = job
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Row

/// One automation: state glyph, name, schedule, next run (or last error when failing).
/// A flat tag spells the state out whenever it is not healthy, so it never relies on color alone.
private struct NativeAutomationRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let job: NativeCronJob
    let isBusy: Bool

    private var nextText: String? {
        guard self.job.enabled, let relative = NativeFormat.relative(ms: self.job.nextRunAtMs) else { return nil }
        return String(localized: "Next run \(relative)")
    }

    private var errorText: String? {
        guard self.job.phase == .failing, let error = self.job.lastError, !error.isEmpty else { return nil }
        return error
    }

    var body: some View {
        HStack(alignment: .top, spacing: OpenClawSpace.md) {
            ActivityGlyph(systemImage: self.job.phase.systemImage, tint: self.job.phase.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: self.job.phase == .running && !self.reduceMotion)
            self.texts
            Spacer(minLength: OpenClawSpace.sm)
            self.trailing
        }
        .openClawAnimation(value: self.job.phase)
        .openClawAnimation(value: self.isBusy)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: ActivityMetric.minTarget, alignment: .leading)
        .overlay(alignment: .bottom) { ActivityHairline() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: self.job.phase.label))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: self.job.name)
                .font(OpenClawType.subheadMedium)
                .foregroundStyle(OpenClawPalette.texteFort)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(verbatim: self.job.scheduleText)
                .font(OpenClawType.footnote)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .lineLimit(1)
            if let next = self.nextText {
                Text(verbatim: next)
                    .font(OpenClawType.caption)
                    .foregroundStyle(OpenClawPalette.texteAtténué)
                    .lineLimit(1)
            }
            if let error = self.errorText {
                Text(verbatim: error)
                    .font(OpenClawType.caption)
                    .foregroundStyle(OpenClawBrand.danger)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if self.isBusy {
            ProgressView()
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        } else if self.job.phase != .healthy {
            ActivityStatusTag(
                text: self.job.phase.label,
                systemImage: self.job.phase.systemImage,
                tint: self.job.phase.tint)
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        }
    }
}


// MARK: - Detail

struct NativeAutomationDetailView: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmDelete = false
    @State private var copiedTick = 0
    let jobId: String
    let model: NativeAutomationsModel

    var body: some View {
        Group {
            if let job = self.model.job(id: self.jobId) {
                self.content(job)
            } else {
                OpenClawEmptyState(
                    systemImage: "timer",
                    title: "Automation not found",
                    message: "It may have been removed on the Gateway.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { OpenClawProBackground() }
        .sensoryFeedback(.success, trigger: self.copiedTick)
        .navigationTitle(self.model.job(id: self.jobId)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { self.toolbarContent }
        .task(id: self.jobId) {
            if let job = self.model.job(id: self.jobId) {
                await self.model.loadRuns(job: job, appModel: self.appModel)
            }
        }
        .confirmationDialog(
            Text("Delete this automation?"),
            isPresented: self.$confirmDelete,
            titleVisibility: .visible)
        {
            Button("Delete", role: .destructive) { self.delete() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    UIPasteboard.general.string = self.jobId
                    self.copiedTick += 1
                } label: {
                    Label("Copy ID", systemImage: "doc.on.doc")
                }
                if self.model.canDelete {
                    Divider()
                    Button(role: .destructive) {
                        self.confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").nativeMinimumTapTarget()
            }
            .accessibilityLabel(Text("More"))
        }
    }

    private func delete() {
        guard let job = self.model.job(id: self.jobId) else { return }
        Task {
            let removed: Bool = await self.model.remove(job: job, appModel: self.appModel)
            if removed { self.dismiss() }
        }
    }

    private func content(_ job: NativeCronJob) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                self.header(job)
                    .openClawEntrance(index: 0)
                self.controls(job)
                    .openClawEntrance(index: 1)
                self.facts(job)
                    .openClawEntrance(index: 2)
                self.errorCard(job)
                self.history(job)
                    .openClawEntrance(index: 3)
            }
            .padding(.horizontal, OpenClawProMetric.pagePadding)
            .padding(.vertical, 12)
        }
        .refreshable {
            await self.model.load(appModel: self.appModel, showSpinner: false)
            await self.model.loadRuns(job: job, appModel: self.appModel)
        }
        .openClawAnimation(value: job)
    }

    private func header(_ job: NativeCronJob) -> some View {
        HStack(alignment: .top, spacing: 12) {
            NGIconBadge(systemImage: job.phase.systemImage, tint: job.phase.tint, size: 48)
            VStack(alignment: .leading, spacing: 6) {
                NGPill(text: job.phase.label, systemImage: job.phase.systemImage, tint: job.phase.tint)
                if let detail = job.detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(OpenClawType.subhead)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func controls(_ job: NativeCronJob) -> some View {
        let busy: Bool = self.model.busyIds.contains(job.id)
        if self.model.canRun || self.model.canToggle {
            OpenClawGlassControlGroup {
                HStack(spacing: 12) {
                    if self.model.canRun {
                        Button {
                            Task { await self.model.runNow(job: job, appModel: self.appModel) }
                        } label: {
                            self.controlLabel(
                                busy: busy,
                                text: String(localized: "Run now"),
                                systemImage: "play.fill")
                        }
                        .nativeGlassButtonStyle(prominent: true)
                        .disabled(busy)
                    }
                    if self.model.canToggle {
                        Button {
                            Task { await self.model.setEnabled(!job.enabled, job: job, appModel: self.appModel) }
                        } label: {
                            self.controlLabel(
                                busy: false,
                                text: job.enabled ? String(localized: "Pause") : String(localized: "Resume"),
                                systemImage: job.enabled ? "pause.circle" : "play.circle")
                        }
                        .nativeGlassButtonStyle()
                        .disabled(busy)
                    }
                }
            }
        }
    }

    private func controlLabel(busy: Bool, text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            if busy {
                ProgressView()
            } else {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(verbatim: text)
        }
        .font(OpenClawType.subheadSemiBold)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func facts(_ job: NativeCronJob) -> some View {
        let lastStatus: String? = job.lastStatus.map { NativeFormat.humanized($0).capitalized }
        let duration: String? = job.lastDurationMs.map { NativeFormat.duration(ms: $0) }
        return VStack(alignment: .leading, spacing: 0) {
            self.fact("Schedule", job.scheduleText)
            self.fact("Agent", job.agentId)
            self.fact("Next run", job.enabled ? NativeFormat.dateTime(ms: job.nextRunAtMs) : nil)
            self.fact("Last run", NativeFormat.dateTime(ms: job.lastRunAtMs))
            self.fact("Last status", lastStatus)
            self.fact("Duration", duration)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCardSurface()
    }

    @ViewBuilder
    private func fact(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent {
                Text(verbatim: value)
                    .font(OpenClawType.subhead)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            } label: {
                Text(label).font(OpenClawType.body)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func errorCard(_ job: NativeCronJob) -> some View {
        if let error = job.lastError, !error.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Last error", systemImage: "exclamationmark.triangle.fill")
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(OpenClawBrand.danger)
                Text(verbatim: error)
                    .font(OpenClawType.subhead)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ngCardSurface()
            .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        }
    }

    @ViewBuilder
    private func history(_ job: NativeCronJob) -> some View {
        if self.model.canReadRuns {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent runs")
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                self.historyBody(job)
            }
        }
    }

    @ViewBuilder
    private func historyBody(_ job: NativeCronJob) -> some View {
        switch self.model.runs[job.id] ?? .idle {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 60)
                .accessibilityLabel(Text("Loading"))
        case let .failed(message):
            NativeInlineNotice(message: message)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ngCardSurface()
        case let .loaded(runs):
            if runs.isEmpty {
                Text("No runs recorded yet.")
                    .font(OpenClawType.subhead)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ngCardSurface()
            } else {
                NativeCronReliabilityCard(runs: runs)
                NativeCronRunsChart(runs: runs)
                VStack(spacing: 0) {
                    ForEach(Array(runs.enumerated()), id: \.element.id) { (index: Int, run: NativeCronRun) in
                        NativeCronRunRow(run: run)
                            .openClawEntrance(index: index)
                        if run.id != runs.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .ngCardSurface()
            }
        }
    }
}

/// Run durations, oldest to newest. Bars carry the run status color; hidden when fewer than two runs have a duration.
private struct NativeCronRunsChart: View {
    let runs: [NativeCronRun]

    @State private var selectedID: String?

    private var timed: [NativeCronRun] {
        Array(self.runs.filter { ($0.durationMs ?? 0) > 0 }.prefix(20).reversed())
    }

    private func selectedRun(in points: [NativeCronRun]) -> NativeCronRun? {
        guard let id = self.selectedID else { return nil }
        return points.first { $0.id == id }
    }

    var body: some View {
        let points: [NativeCronRun] = self.timed
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Run duration")
                    .font(OpenClawType.subheadSemiBold)
                    .accessibilityAddTraits(.isHeader)
                let selected: NativeCronRun? = self.selectedRun(in: points)
                Chart {
                    ForEach(points) { run in
                        BarMark(
                            x: .value("Run", run.id),
                            y: .value("Seconds", Double(run.durationMs ?? 0) / 1000))
                            .foregroundStyle(run.tint.opacity(selected == nil || selected?.id == run.id ? 1 : 0.4))
                            .cornerRadius(3)
                    }
                    if let selected {
                        RuleMark(x: .value("Run", selected.id))
                            .foregroundStyle(Color.secondary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(
                                position: .top,
                                spacing: 4,
                                overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .disabled))
                            {
                                ChartSelectionTooltip(
                                    title: selected.statusLabel,
                                    value: NativeFormat.duration(ms: selected.durationMs ?? 0))
                            }
                    }
                }
                .chartXSelection(value: self.$selectedID)
                .chartXAxis(.hidden)
                .frame(height: 110)
                .openClawChartReveal()
                .openClawAnimation(value: self.selectedID)
                .sensoryFeedback(.selection, trigger: self.selectedID)
            }
            .padding(12)
            .ngCardSurface()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Run duration"))
            .accessibilityValue(Text(self.summary(points)))
        }
    }

    private func summary(_ points: [NativeCronRun]) -> String {
        let failed: Int = points.filter { $0.isFailure }.count
        return String(localized: "\(points.count) runs, \(failed) failed")
    }
}

/// Success rate over the recent runs: circular gauge plus a strip of the last outcomes (oldest to newest).
/// Status never relies on color alone: the percentage and the counts are spelled out.
private struct NativeCronReliabilityCard: View {
    let runs: [NativeCronRun]

    private var recent: [NativeCronRun] {
        Array(self.runs.prefix(20).reversed())
    }

    private var failedCount: Int {
        self.recent.filter { $0.isFailure }.count
    }

    private var rate: Double {
        let total: Int = self.recent.count
        guard total > 0 else { return 0 }
        return Double(total - self.failedCount) / Double(total)
    }

    private var gaugeTint: Color {
        if self.rate >= 0.9 { return OpenClawBrand.ok }
        if self.rate >= 0.6 { return OpenClawBrand.warn }
        return OpenClawBrand.danger
    }

    private var summary: String {
        let total: Int = self.recent.count
        let failed: Int = self.failedCount
        let percent: String = self.rate.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(percent) success, \(total) runs, \(failed) failed")
    }

    var body: some View {
        let items: [NativeCronRun] = self.recent
        return HStack(spacing: 14) {
            Gauge(value: self.rate) {
                Text("Success rate")
            } currentValueLabel: {
                Text(self.rate, format: .percent.precision(.fractionLength(0)))
                    .font(OpenClawType.captionSemiBold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(self.gaugeTint)
            .openClawAnimation(value: self.rate)
            VStack(alignment: .leading, spacing: 8) {
                Text("Reliability")
                    .font(OpenClawType.subheadSemiBold)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 3) {
                    ForEach(items) { run in
                        Capsule()
                            .fill(run.tint)
                            .frame(height: 14)
                    }
                }
                Text(verbatim: self.summary)
                    .font(OpenClawType.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .ngCardSurface()
        .openClawChartReveal()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Reliability"))
        .accessibilityValue(Text(verbatim: self.summary))
    }
}

private struct NativeCronRunRow: View {
    let run: NativeCronRun

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.run.systemImage)
                .foregroundStyle(self.run.tint)
                .frame(width: 24)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.run.statusLabel)
                    .font(OpenClawType.subheadSemiBold)
                Text(verbatim: self.meta)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
                if let text = self.run.error ?? self.run.summary, !text.isEmpty {
                    Text(verbatim: text)
                        .font(OpenClawType.caption)
                        .foregroundStyle(self.run.isFailure ? OpenClawBrand.danger : Color.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            if let text = self.run.error ?? self.run.summary, !text.isEmpty {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        let when: String? = NativeFormat.dateTime(ms: self.run.runAtMs)
        let took: String? = self.run.durationMs.map { NativeFormat.duration(ms: $0) }
        return NativeFormat.joined([when, took]) ?? "-"
    }
}
