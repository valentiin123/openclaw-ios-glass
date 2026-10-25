import OpenClawChatUI
import SwiftUI
import UIKit

// Native screens: agents list -> agent detail (sessions) -> subagent tree -> launch / run detail.
// Content sits on system opaque List surfaces. Glass is only used by the system toolbar and the
// `.glass` button styles on controls (never behind rows).
// Compiler hygiene: no nested trailing closures in swipe actions, heavy expressions are hoisted
// into typed properties, and ViewBuilders only reference properties/methods.

// MARK: - Agents list

struct AgentsHubListView: View {
    @Bindable var model: AgentsHubViewModel

    @State private var showCreate = false

    var body: some View {
        List {
            errorSection
            agentsSection
        }
        .overlay { listOverlay }
        .navigationTitle("Agents")
        .toolbar { createToolbar }
        .sheet(isPresented: $showCreate) {
            CreateAgentSheet(model: model)
        }
        .navigationDestination(for: OpenClawChatAgentChoice.self) { agent in
            AgentDetailView(model: model, agent: agent)
        }
        .refreshable { await model.loadAgents() }
        .task { if model.agents.isEmpty { await model.loadAgents() } }
        .agentsHubAnimation(value: model.agents)
    }

    @ToolbarContentBuilder
    private var createToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: openCreate) {
                Label("New agent", systemImage: "plus")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!model.canCreateAgent)
        }
    }

    private func openCreate() {
        showCreate = true
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = model.agentsError {
            Section {
                AgentsHubErrorRow(message: error, retry: retryAgents)
            }
        }
    }

    private var agentsSection: some View {
        Section {
            ForEach(model.agents) { agent in
                agentLink(agent)
            }
        }
    }

    private func agentLink(_ agent: OpenClawChatAgentChoice) -> some View {
        let isDefault: Bool = agent.id == model.defaultAgentID
        return NavigationLink(value: agent) {
            AgentRow(agent: agent, isDefault: isDefault)
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var listOverlay: some View {
        if model.agents.isEmpty, model.isLoadingAgents {
            ProgressView().accessibilityLabel(Text("Loading agents"))
        } else if model.agents.isEmpty, model.agentsError == nil {
            ContentUnavailableView("No agents", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private func retryAgents() {
        Task { await model.loadAgents() }
    }
}

private struct AgentRow: View {
    let agent: OpenClawChatAgentChoice
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(agent.avatarText)
                .font(OpenClawType.title3)
                .frame(width: 44, height: 44)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName).font(OpenClawType.headline)
                secondaryID
            }
            Spacer(minLength: 0)
            defaultTag
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var secondaryID: some View {
        if agent.displayName != agent.id {
            Text(agent.id).font(OpenClawType.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var defaultTag: some View {
        if isDefault {
            Text("Default")
                .font(OpenClawType.caption2SemiBold)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Agent detail

struct AgentDetailView: View {
    @Bindable var model: AgentsHubViewModel
    let agent: OpenClawChatAgentChoice

    var body: some View {
        List {
            infoSection
            sessionsSection
        }
        .navigationTitle(agent.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: OpenClawChatSessionEntry.self) { session in
            SubagentTreeView(model: model, root: session)
        }
        .refreshable { await model.loadSessions(agentID: agent.id) }
        .task(id: agent.id) { await model.loadSessions(agentID: agent.id) }
        .agentsHubAnimation(value: model.sessions)
    }

    private var infoSection: some View {
        Section("Agent") {
            LabeledContent("ID", value: agent.id)
            workspaceRow
        }
    }

    @ViewBuilder
    private var workspaceRow: some View {
        if let workspace = agent.workspace {
            LabeledContent("Workspace", value: workspace)
        }
    }

    private var sessionsSection: some View {
        Section("Sessions") {
            ForEach(model.sessions) { session in
                sessionLink(session)
            }
            emptySessions
        }
    }

    private func sessionLink(_ session: OpenClawChatSessionEntry) -> some View {
        let status: AgentsHubRunStatus = AgentsHubRunStatus(session)
        let title: String = sessionTitle(session)
        return NavigationLink(value: session) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(OpenClawType.body)
                AgentsHubStatusBadge(status: status)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var emptySessions: some View {
        if model.sessions.isEmpty {
            Text("No sessions").foregroundStyle(.secondary)
        }
    }

    private func sessionTitle(_ s: OpenClawChatSessionEntry) -> String {
        let candidates: [String?] = [s.label, s.displayName, s.derivedTitle]
        for c in candidates {
            if let t = c?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        }
        return s.key
    }
}

// MARK: - Subagent tree

struct SubagentTreeView: View {
    @Bindable var model: AgentsHubViewModel
    let root: OpenClawChatSessionEntry

    @State private var showLaunch = false
    @State private var detailNode: SubagentNode?
    @State private var confirmStop: SubagentNode?

    var body: some View {
        List {
            messagesSection
            treeSections
        }
        .overlay { treeOverlay }
        .navigationTitle("Subagents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { launchToolbar }
        .refreshable { await model.loadTree(root: root) }
        .task(id: root.key) { await model.loadTree(root: root) }
        .sheet(isPresented: $showLaunch) {
            LaunchSubagentSheet(model: model, parent: root)
        }
        .sheet(item: $detailNode) { node in
            SubagentResultSheet(model: model, node: node)
        }
        .confirmationDialog(
            "Stop this subagent and its descendants?",
            isPresented: confirmStopBinding,
            titleVisibility: .visible,
            actions: { stopDialogActions })
        .agentsHubAnimation(value: model.collapsed)
        .agentsHubAnimation(value: model.visibleRows)
    }

    // MARK: Bindings and helpers

    private var confirmStopBinding: Binding<Bool> {
        Binding<Bool>(
            get: { confirmStop != nil },
            set: { newValue in if !newValue { confirmStop = nil } })
    }

    private func requestStop(_ node: SubagentNode) {
        confirmStop = node
    }

    private func showDetail(_ node: SubagentNode) {
        detailNode = node
    }

    private func confirmStopNow() {
        guard let node = confirmStop else { return }
        confirmStop = nil
        Task { await model.stop(node) }
    }

    private func cancelStop() {
        confirmStop = nil
    }

    private func reloadTree() {
        Task { await model.loadTree(root: root) }
    }

    private func openLaunch() {
        showLaunch = true
    }

    // MARK: Pieces

    @ViewBuilder
    private var stopDialogActions: some View {
        Button("Stop", role: .destructive, action: confirmStopNow)
        Button("Cancel", role: .cancel, action: cancelStop)
    }

    @ToolbarContentBuilder
    private var launchToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: openLaunch) {
                Label("Launch subagent", systemImage: "plus")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!model.canLaunch)
        }
    }

    @ViewBuilder
    private var messagesSection: some View {
        if let error = model.treeError {
            AgentsHubErrorRow(message: error, retry: reloadTree)
        }
        if let error = model.actionError {
            AgentsHubErrorRow(message: error, retry: nil)
        }
    }

    @ViewBuilder
    private var treeSections: some View {
        if let tree = model.tree {
            Section { summary(tree) }
            Section("Subagents") {
                rowsContent(tree)
            }
        }
    }

    @ViewBuilder
    private func rowsContent(_ tree: SubagentNode) -> some View {
        ForEach(model.visibleRows) { row in
            treeRow(row)
        }
        if tree.children.isEmpty {
            Text("No subagents").foregroundStyle(.secondary)
        }
    }

    private func treeRow(_ row: FlatSubagentRow) -> some View {
        let busy: Bool = model.busyKeys.contains(row.node.id)
        let id: String = row.node.id
        return SubagentRowView(
            row: row,
            busy: busy,
            canStop: model.canStop,
            onToggle: { model.toggle(id) },
            onStop: { requestStop(row.node) },
            onResult: { showDetail(row.node) })
    }

    @ViewBuilder
    private var treeOverlay: some View {
        if model.tree == nil, model.isLoadingTree {
            ProgressView().accessibilityLabel(Text("Loading subagents"))
        }
    }

    private func summary(_ tree: SubagentNode) -> some View {
        let isLive: Bool = tree.status.isActive || tree.activeDescendantCount > 0
        let total: Int = tree.descendantCount
        let active: Int = tree.activeDescendantCount
        let failed: Int = tree.failedDescendantCount
        return VStack(alignment: .leading, spacing: 8) {
            AgentsHubStatusBadge(status: tree.status)
            AgentsHubSummaryBar(total: total, active: active, failed: failed, isLive: isLive)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Row

private struct SubagentRowView: View {
    let row: FlatSubagentRow
    let busy: Bool
    let canStop: Bool
    let onToggle: () -> Void
    let onStop: () -> Void
    let onResult: () -> Void

    private var hasActiveRuns: Bool { !row.node.activeRuns.isEmpty }
    private var hasChildren: Bool { !row.node.children.isEmpty }
    private var indent: CGFloat { CGFloat(row.depth) * 16 }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            disclosure
            textColumn
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, indent)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture(perform: onResult)
        .accessibilityAddTraits(.isButton)
        .contextMenu { menuItems }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { stopSwipe }
        .swipeActions(edge: .leading, allowsFullSwipe: false) { toggleSwipe }
        .accessibilityAction(named: Text("View details"), onResult)
        .accessibilityAction(named: Text("Stop"), stopIfAllowed)
    }

    // MARK: Pieces

    @ViewBuilder
    private var disclosure: some View {
        if hasChildren {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(row.isExpanded ? "Collapse" : "Expand"))
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.node.title).font(OpenClawType.body)
            AgentsHubStatusBadge(status: row.node.status)
            metaLine
        }
        .accessibilityElement(children: .combine)
    }

    private var metaText: String {
        let duration: String? = AgentsHubFormat.duration(ms: row.node.session.runtimeMs)
        let count: Int = row.node.descendantCount
        let descendants: String? = hasChildren ? String(localized: "\(count) descendants") : nil
        let parts: [String?] = [duration, descendants]
        let present: [String] = parts.compactMap { $0 }
        return present.joined(separator: " · ")
    }

    @ViewBuilder
    private var metaLine: some View {
        let line: String = metaText
        if !line.isEmpty {
            Text(line).font(OpenClawType.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if busy {
            ProgressView().frame(width: 44, height: 44)
        } else {
            Menu { menuItems } label: { menuLabel }
                .accessibilityLabel(Text("Actions for \(row.node.title)"))
        }
    }

    private var menuLabel: some View {
        Image(systemName: "ellipsis")
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
    }

    /// Shared by the ellipsis menu and the long-press context menu.
    @ViewBuilder
    private var menuItems: some View {
        Button("View details", systemImage: "doc.text", action: onResult)
        Button("Copy session key", systemImage: "doc.on.doc", action: copyKey)
        if hasActiveRuns {
            Button("Stop", systemImage: "stop.circle", role: .destructive, action: onStop)
                .disabled(!canStop)
        }
    }

    // MARK: Swipe actions (one flat Button each, no nested trailing closures)

    @ViewBuilder
    private var stopSwipe: some View {
        if hasActiveRuns {
            Button(role: .destructive, action: onStop) {
                Label("Stop", systemImage: "stop.circle")
            }
            .disabled(!canStop)
        }
    }

    @ViewBuilder
    private var toggleSwipe: some View {
        if hasChildren {
            Button(action: onToggle) {
                toggleSwipeLabel
            }
            .tint(.accentColor)
        }
    }

    @ViewBuilder
    private var toggleSwipeLabel: some View {
        if row.isExpanded {
            Label("Collapse", systemImage: "chevron.up")
        } else {
            Label("Expand", systemImage: "chevron.down")
        }
    }

    // MARK: Actions

    private func copyKey() {
        UIPasteboard.general.string = row.node.session.key
    }

    private func stopIfAllowed() {
        if hasActiveRuns, canStop { onStop() }
    }
}

// MARK: - Launch

struct LaunchSubagentSheet: View {
    @Bindable var model: AgentsHubViewModel
    let parent: OpenClawChatSessionEntry
    @Environment(\.dismiss) private var dismiss

    @State private var agentID = ""
    @State private var label = ""
    @State private var task = ""

    private var trimmedTask: String {
        task.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        let hasAgent: Bool = !agentID.isEmpty
        let hasTask: Bool = !trimmedTask.isEmpty
        let notBusy: Bool = !model.busyKeys.contains(parent.key)
        return model.canLaunch && hasAgent && hasTask && notBusy
    }

    var body: some View {
        NavigationStack {
            Form {
                agentSection
                labelSection
                taskSection
                errorSection
            }
            .navigationTitle("Launch subagent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear(perform: seedAgent)
        }
        .presentationDetents([.medium, .large])
    }

    private var agentSection: some View {
        Section("Agent") {
            Picker("Agent", selection: $agentID) {
                ForEach(model.agents) { agent in
                    Text(agent.displayName).tag(agent.id)
                }
            }
        }
    }

    private var labelSection: some View {
        Section("Label (optional)") {
            TextField("Label", text: $label)
                .frame(minHeight: 44)
        }
    }

    private var taskSection: some View {
        Section("Task") {
            TextEditor(text: $task)
                .font(OpenClawType.body)
                .frame(minHeight: 120)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = model.actionError {
            Section { AgentsHubErrorRow(message: error, retry: nil) }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: close)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Launch", action: submit)
                .disabled(!canSubmit)
        }
    }

    private func close() {
        dismiss()
    }

    private func seedAgent() {
        guard agentID.isEmpty else { return }
        let fallback: String = model.defaultAgentID ?? model.agents.first?.id ?? ""
        agentID = parent.agentId ?? fallback
    }

    private func submit() {
        let chosenAgent: String = agentID
        let chosenLabel: String = label
        let chosenTask: String = task
        Task {
            let created: String? = await model.launch(
                parent: parent, agentID: chosenAgent, label: chosenLabel, task: chosenTask)
            if created != nil { dismiss() }
        }
    }
}

// MARK: - Run detail

struct SubagentResultSheet: View {
    @Bindable var model: AgentsHubViewModel
    let node: SubagentNode
    @Environment(\.dismiss) private var dismiss

    private struct DetailItem: Identifiable {
        let id: String
        let value: String
    }

    private var details: [DetailItem] {
        var items: [DetailItem] = []
        let session: OpenClawChatSessionEntry = node.session
        if let model = session.model, !model.isEmpty {
            items.append(DetailItem(id: String(localized: "Model"), value: model))
        }
        if let started = AgentsHubFormat.date(ms: session.startedAt) {
            items.append(DetailItem(id: String(localized: "Started"), value: started))
        }
        if let ended = AgentsHubFormat.date(ms: session.endedAt) {
            items.append(DetailItem(id: String(localized: "Ended"), value: ended))
        }
        if let duration = AgentsHubFormat.duration(ms: session.runtimeMs) {
            items.append(DetailItem(id: String(localized: "Duration"), value: duration))
        }
        if let tokens = AgentsHubFormat.tokens(session.totalTokens) {
            items.append(DetailItem(id: String(localized: "Tokens"), value: tokens))
        }
        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AgentsHubStatusBadge(status: node.status)
                    errorText
                    detailRows
                    resultBlock
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(node.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneToolbar }
            .task { await model.loadResult(for: node) }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var errorText: some View {
        if let err = node.session.lastRunError, !err.isEmpty {
            Text(err)
                .font(OpenClawType.subhead)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(details) { item in
                LabeledContent(item.id, value: item.value)
                    .font(OpenClawType.subhead)
            }
        }
    }

    @ViewBuilder
    private var resultBlock: some View {
        if model.isLoadingResult {
            ProgressView().accessibilityLabel(Text("Loading result"))
        } else if let text = model.resultText, !text.isEmpty {
            Text(text)
                .font(OpenClawType.body)
                .textSelection(.enabled)
        } else {
            Text("No result available").foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder
    private var doneToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: close)
        }
    }

    private func close() {
        dismiss()
    }
}
