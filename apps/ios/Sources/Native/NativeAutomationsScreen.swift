import Foundation
import Observation
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

// MARK: - Model

@MainActor
@Observable
final class NativeAutomationsModel {
    var state: NativeLoadState<[NativeCronJob]> = .idle
    var busyIds: Set<String> = []
    var actionError: String?

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(NativeGateway.offlineMessage)
            return
        }
        if showSpinner { self.state = .loading }
        do {
            let params: [String: Any] = [
                "includeDisabled": true,
                "limit": 200,
                "offset": 0,
                "sortBy": "name",
                "sortDir": "asc",
            ]
            let obj: Any = try await NativeGateway.send(appModel: appModel, method: "cron.list", params: params)
            let root: [String: Any] = (obj as? [String: Any]) ?? [:]
            let jobs: [NativeCronJob] = root.array("jobs").compactMap(NativeCronJob.parse)
            self.state = .loaded(jobs)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    func job(id: String) -> NativeCronJob? {
        guard case let .loaded(jobs) = self.state else { return nil }
        return jobs.first { $0.id == id }
    }

    func setEnabled(_ enabled: Bool, job: NativeCronJob, appModel: NodeAppModel) async {
        let params: [String: Any] = ["id": job.id, "patch": ["enabled": enabled]]
        await self.mutate(id: job.id, method: "cron.update", params: params, appModel: appModel)
    }

    func runNow(job: NativeCronJob, appModel: NodeAppModel) async {
        let params: [String: Any] = ["id": job.id, "mode": "force"]
        await self.mutate(id: job.id, method: "cron.run", params: params, appModel: appModel)
    }

    func remove(job: NativeCronJob, appModel: NodeAppModel) async {
        let params: [String: Any] = ["id": job.id]
        await self.mutate(id: job.id, method: "cron.remove", params: params, appModel: appModel)
    }

    private func mutate(id: String, method: String, params: [String: Any], appModel: NodeAppModel) async {
        guard !self.busyIds.contains(id) else { return }
        self.busyIds.insert(id)
        self.actionError = nil
        do {
            _ = try await NativeGateway.send(appModel: appModel, method: method, params: params, timeoutSeconds: 20)
        } catch is CancellationError {
            self.busyIds.remove(id)
            return
        } catch {
            self.actionError = error.localizedDescription
        }
        self.busyIds.remove(id)
        await self.load(appModel: appModel, showSpinner: false)
    }
}

// MARK: - Screen

struct NativeAutomationsScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model = NativeAutomationsModel()
    @State private var search = ""
    @State private var pendingDelete: NativeCronJob?
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    var body: some View {
        NavigationStack {
            NativeStateView(
                state: self.model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No automations",
                emptyIcon: "timer",
                retry: { await self.model.load(appModel: self.appModel, showSpinner: true) })
            { jobs in
                self.list(jobs)
            }
            .nativeChrome(title: self.title, sidebar: self.headerSidebarAction)
            .searchable(text: self.$search, prompt: Text("Search automations"))
            .navigationDestination(for: NativeCronJob.self) { job in
                NativeAutomationDetailView(jobId: job.id, model: self.model)
            }
            .nativeErrorAlert(self.$model.actionError)
            .confirmationDialog(
                Text("Delete this automation?"),
                isPresented: self.deleteBinding,
                titleVisibility: .visible,
                presenting: self.pendingDelete)
            { job in
                Button("Delete", role: .destructive) {
                    Task { await self.model.remove(job: job, appModel: self.appModel) }
                }
            } message: { job in
                Text(verbatim: job.name)
            }
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
    }

    private var deleteBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.pendingDelete != nil },
            set: { shown in
                if !shown { self.pendingDelete = nil }
            })
    }

    private func filtered(_ jobs: [NativeCronJob]) -> [NativeCronJob] {
        let query: String = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return jobs }
        return jobs.filter { $0.matches(query) }
    }

    @ViewBuilder
    private func list(_ jobs: [NativeCronJob]) -> some View {
        let visible: [NativeCronJob] = self.filtered(jobs)
        let active: [NativeCronJob] = visible.filter { $0.enabled }
        let paused: [NativeCronJob] = visible.filter { !$0.enabled }
        List {
            if !active.isEmpty {
                Section("Active") { self.rows(active) }
            }
            if !paused.isEmpty {
                Section("Paused") { self.rows(paused) }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await self.model.load(appModel: self.appModel, showSpinner: false) }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView.search(text: self.search)
            }
        }
    }

    @ViewBuilder
    private func rows(_ jobs: [NativeCronJob]) -> some View {
        ForEach(jobs) { job in
            NavigationLink(value: job) {
                NativeAutomationRow(job: job, isBusy: self.model.busyIds.contains(job.id))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { self.trailingActions(job) }
            .swipeActions(edge: .leading) { self.leadingActions(job) }
            .contextMenu { self.menu(job) }
        }
    }

    @ViewBuilder
    private func trailingActions(_ job: NativeCronJob) -> some View {
        Button(role: .destructive) {
            self.pendingDelete = job
        } label: {
            Label("Delete", systemImage: "trash")
        }
        Button {
            Task { await self.model.setEnabled(!job.enabled, job: job, appModel: self.appModel) }
        } label: {
            if job.enabled {
                Label("Pause", systemImage: "pause.circle")
            } else {
                Label("Resume", systemImage: "play.circle")
            }
        }
        .tint(.orange)
    }

    @ViewBuilder
    private func leadingActions(_ job: NativeCronJob) -> some View {
        Button {
            Task { await self.model.runNow(job: job, appModel: self.appModel) }
        } label: {
            Label("Run now", systemImage: "play.fill")
        }
        .tint(.green)
    }

    @ViewBuilder
    private func menu(_ job: NativeCronJob) -> some View {
        Button {
            Task { await self.model.runNow(job: job, appModel: self.appModel) }
        } label: {
            Label("Run now", systemImage: "play.fill")
        }
        Button {
            Task { await self.model.setEnabled(!job.enabled, job: job, appModel: self.appModel) }
        } label: {
            if job.enabled {
                Label("Pause", systemImage: "pause.circle")
            } else {
                Label("Resume", systemImage: "play.circle")
            }
        }
        Button {
            UIPasteboard.general.string = job.id
        } label: {
            Label("Copy ID", systemImage: "doc.on.doc")
        }
        Button(role: .destructive) {
            self.pendingDelete = job
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Row

private struct NativeAutomationRow: View {
    let job: NativeCronJob
    let isBusy: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: self.iconName)
                .font(OpenClawType.body)
                .foregroundStyle(self.iconColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.job.name)
                    .font(OpenClawType.body)
                Text(verbatim: self.job.scheduleText)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
                if let next = self.nextText {
                    Text(verbatim: next)
                        .font(OpenClawType.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if self.isBusy {
                ProgressView()
            } else if self.job.isFailing {
                NativeBadge(text: String(localized: "Failing"), color: OpenClawBrand.danger)
            } else if self.job.isRunning {
                NativeBadge(text: String(localized: "Running"), color: OpenClawBrand.info)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        if !self.job.enabled { return "pause.circle" }
        return self.job.isFailing ? "exclamationmark.triangle" : "timer"
    }

    private var iconColor: Color {
        if !self.job.enabled { return OpenClawBrand.warn }
        return self.job.isFailing ? OpenClawBrand.danger : Color.secondary
    }

    private var nextText: String? {
        guard self.job.enabled, let relative = NativeFormat.relative(ms: self.job.nextRunAtMs) else { return nil }
        return String(localized: "Next run \(relative)")
    }
}

// MARK: - Detail

struct NativeAutomationDetailView: View {
    @Environment(NodeAppModel.self) private var appModel
    let jobId: String
    let model: NativeAutomationsModel

    var body: some View {
        Group {
            if let job = self.model.job(id: self.jobId) {
                self.content(job)
            } else {
                ContentUnavailableView("No automations", systemImage: "timer")
            }
        }
        .navigationTitle(self.model.job(id: self.jobId)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ job: NativeCronJob) -> some View {
        List {
            Section {
                self.row("Schedule", job.scheduleText)
                self.row("Agent", job.agentId)
                self.row("Next run", NativeFormat.dateTime(ms: job.nextRunAtMs))
                self.row("Last run", NativeFormat.dateTime(ms: job.lastRunAtMs))
                self.row("Last status", job.lastStatus.map { NativeFormat.humanized($0) })
                if let duration = job.lastDurationMs {
                    self.row("Duration", NativeFormat.duration(ms: duration))
                }
            }
            if let detail = job.detail, !detail.isEmpty {
                Section("Description") {
                    Text(verbatim: detail).font(OpenClawType.body)
                }
            }
            if let error = job.lastError, !error.isEmpty {
                Section("Last error") {
                    Text(verbatim: error)
                        .font(OpenClawType.subhead)
                        .foregroundStyle(OpenClawBrand.danger)
                        .textSelection(.enabled)
                }
            }
            Section {
                self.controls(job)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent {
                Text(verbatim: value)
                    .font(OpenClawType.subhead)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(label).font(OpenClawType.body)
            }
        }
    }

    @ViewBuilder
    private func controls(_ job: NativeCronJob) -> some View {
        let busy: Bool = self.model.busyIds.contains(job.id)
        Button {
            Task { await self.model.runNow(job: job, appModel: self.appModel) }
        } label: {
            Label("Run now", systemImage: "play.fill").frame(minHeight: 44)
        }
        .disabled(busy)
        Button {
            Task { await self.model.setEnabled(!job.enabled, job: job, appModel: self.appModel) }
        } label: {
            if job.enabled {
                Label("Pause", systemImage: "pause.circle").frame(minHeight: 44)
            } else {
                Label("Resume", systemImage: "play.circle").frame(minHeight: 44)
            }
        }
        .disabled(busy)
    }
}
