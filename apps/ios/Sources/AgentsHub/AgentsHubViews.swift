import OpenClawChatUI
import SwiftUI

// Native screens: agents list -> agent detail (sessions) -> subagent tree -> launch / result.
// Content sits on system opaque List surfaces. Glass is only used by the system toolbar and the
// `.glass` button styles on controls (never behind rows).

// MARK: - Agents list

struct AgentsHubListView: View {
    @Bindable var model: AgentsHubViewModel

    var body: some View {
        List {
            if let error = model.agentsError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel(Text("Error: \(error)"))
                    Button("Retry") { Task { await model.loadAgents() } }
                        .frame(minHeight: 44)
                }
            }
            Section {
                ForEach(model.agents) { agent in
                    NavigationLink(value: agent) {
                        AgentRow(agent: agent, isDefault: agent.id == model.defaultAgentID)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .overlay {
            if model.agents.isEmpty, model.isLoadingAgents {
                ProgressView().accessibilityLabel(Text("Loading agents"))
            } else if model.agents.isEmpty, model.agentsError == nil {
                ContentUnavailableView("No agents", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle("Agents")
        .navigationDestination(for: OpenClawChatAgentChoice.self) { agent in
            AgentDetailView(model: model, agent: agent)
        }
        .refreshable { await model.loadAgents() }
        .task { if model.agents.isEmpty { await model.loadAgents() } }
        .agentsHubAnimation(value: model.agents)
    }
}

private struct AgentRow: View {
    let agent: OpenClawChatAgentChoice
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(agent.avatarText)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName).font(.headline)
                if agent.displayName != agent.id {
                    Text(agent.id).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isDefault {
                Text("Default")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Agent detail

struct AgentDetailView: View {
    @Bindable var model: AgentsHubViewModel
    let agent: OpenClawChatAgentChoice

    var body: some View {
        List {
            Section("Agent") {
                LabeledContent("ID", value: agent.id)
                if let workspace = agent.workspace {
                    LabeledContent("Workspace", value: workspace)
                }
            }
            Section("Sessions") {
                ForEach(model.sessions) { session in
                    NavigationLink(value: session) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sessionTitle(session)).font(.body)
                            AgentsHubStatusBadge(status: AgentsHubRunStatus(session))
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .frame(minHeight: 44)
                }
                if model.sessions.isEmpty {
                    Text("No sessions").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(agent.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: OpenClawChatSessionEntry.self) { session in
            SubagentTreeView(model: model, root: session)
        }
        .refreshable { await model.loadSessions(agentID: agent.id) }
        .task(id: agent.id) { await model.loadSessions(agentID: agent.id) }
    }

    private func sessionTitle(_ s: OpenClawChatSessionEntry) -> String {
        for c in [s.label, s.displayName, s.derivedTitle] {
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
    @State private var resultNode: SubagentNode?
    @State private var confirmStop: SubagentNode?

    var body: some View {
        List {
            if let error = model.treeError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            if let error = model.actionError {
                Label(error, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red)
            }
            if let tree = model.tree {
                Section {
                    summary(tree)
                }
                Section("Subagents") {
                    ForEach(model.visibleRows) { row in
                        SubagentRowView(
                            row: row,
                            busy: model.busyKeys.contains(row.node.id),
                            onToggle: { model.toggle(row.node.id) },
                            onStop: { confirmStop = row.node },
                            onResult: { resultNode = row.node })
                    }
                    if tree.children.isEmpty {
                        Text("No subagents").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if model.tree == nil, model.isLoadingTree {
                ProgressView().accessibilityLabel(Text("Loading subagents"))
            }
        }
        .navigationTitle("Subagents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showLaunch = true } label: {
                    Label("Launch subagent", systemImage: "plus")
                }
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .refreshable { await model.loadTree(root: root) }
        .task(id: root.key) { await model.loadTree(root: root) }
        .sheet(isPresented: $showLaunch) {
            LaunchSubagentSheet(model: model, parent: root)
        }
        .sheet(item: $resultNode) { node in
            SubagentResultSheet(model: model, node: node)
        }
        .confirmationDialog(
            "Stop this subagent and its descendants?",
            isPresented: Binding(get: { confirmStop != nil }, set: { if !$0 { confirmStop = nil } }),
            titleVisibility: .visible)
        {
            Button("Stop", role: .destructive) {
                if let node = confirmStop { Task { await model.stop(node) } }
                confirmStop = nil
            }
            Button("Cancel", role: .cancel) { confirmStop = nil }
        }
        .agentsHubAnimation(value: model.collapsed)
        .agentsHubAnimation(value: model.visibleRows)
    }

    private func summary(_ tree: SubagentNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AgentsHubStatusBadge(status: tree.status)
            Text("\(tree.descendantCount) descendants · \(tree.activeDescendantCount) active · \(tree.failedDescendantCount) failed")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SubagentRowView: View {
    let row: FlatSubagentRow
    let busy: Bool
    let onToggle: () -> Void
    let onStop: () -> Void
    let onResult: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !row.node.children.isEmpty {
                Button(action: onToggle) {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(row.isExpanded ? "Collapse" : "Expand"))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.node.title).font(.body)
                AgentsHubStatusBadge(status: row.node.status)
                if let d = AgentsHubFormat.duration(ms: row.node.session.runtimeMs) {
                    Text(d).font(.caption).foregroundStyle(.secondary)
                }
                if !row.node.children.isEmpty {
                    Text("\(row.node.descendantCount) descendants")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if busy {
                ProgressView()
            } else {
                Menu {
                    Button("View result", systemImage: "doc.text", action: onResult)
                    if !row.node.activeRuns.isEmpty {
                        Button("Stop", systemImage: "stop.circle", role: .destructive, action: onStop)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Actions for \(row.node.title)"))
            }
        }
        .padding(.leading, CGFloat(row.depth) * 16)
        .frame(minHeight: 44)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    Picker("Agent", selection: $agentID) {
                        ForEach(model.agents) { Text($0.displayName).tag($0.id) }
                    }
                }
                Section("Label (optional)") {
                    TextField("Label", text: $label)
                }
                Section("Task") {
                    TextEditor(text: $task).frame(minHeight: 120)
                }
                if let error = model.actionError {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Launch subagent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Launch") {
                        Task {
                            if await model.launch(parent: parent, agentID: agentID, label: label, task: task) != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(agentID.isEmpty
                        || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.busyKeys.contains(parent.key))
                }
            }
            .onAppear {
                if agentID.isEmpty { agentID = parent.agentId ?? model.defaultAgentID ?? model.agents.first?.id ?? "" }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Result

struct SubagentResultSheet: View {
    @Bindable var model: AgentsHubViewModel
    let node: SubagentNode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AgentsHubStatusBadge(status: node.status)
                    if let err = node.session.lastRunError, !err.isEmpty {
                        Text(err).foregroundStyle(.red)
                    }
                    if model.isLoadingResult {
                        ProgressView().accessibilityLabel(Text("Loading result"))
                    } else if let text = model.resultText, !text.isEmpty {
                        Text(text).textSelection(.enabled)
                    } else {
                        Text("No result available").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(node.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await model.loadResult(for: node) }
        }
        .presentationDetents([.medium, .large])
    }
}
