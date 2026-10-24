import Foundation
import Observation
import OpenClawChatUI
import OpenClawKit
import OpenClawProtocol

/// Injected Gateway access. Only uses requests that already exist in `OpenClawChatGatewayRequests`
/// (agents.list, agent.identity.get, sessions.list, sessions.create, chat.abort) plus two closures
/// the host wires to existing transport calls (see AGENTSHUB.md).
struct AgentsHubGateway: Sendable {
    /// Executes a built request on the current Gateway connection and returns the raw payload.
    var request: @Sendable (OpenClawChatGatewayRequest) async throws -> Data
    /// Sends a user message into a session (wire to `OpenClawChatTransport.sendMessage`).
    var sendMessage: @Sendable (_ sessionKey: String, _ agentID: String?, _ message: String) async throws -> Void
    /// Optional: last assistant text of a session (wire to `requestHistory(sessionKey:)`). nil = use preview.
    var fetchResultText: (@Sendable (_ sessionKey: String) async throws -> String?)?
}

@MainActor @Observable
final class AgentsHubViewModel {
    private(set) var agents: [OpenClawChatAgentChoice] = []
    private(set) var defaultAgentID: String?
    private(set) var isLoadingAgents = false
    private(set) var agentsError: String?

    private(set) var sessions: [OpenClawChatSessionEntry] = []
    private(set) var tree: SubagentNode?
    private(set) var isLoadingTree = false
    private(set) var treeError: String?
    var collapsed: Set<String> = []

    private(set) var busyKeys: Set<String> = []
    private(set) var actionError: String?
    private(set) var resultText: String?
    private(set) var isLoadingResult = false

    /// Droits dérivés des scopes opérateur et des méthodes annoncées (voir AgentsHubScreen).
    var canLaunch = false
    var canStop = false

    private var trackedAgentID: String?
    private var trackedRoot: OpenClawChatSessionEntry?

    private let gateway: AgentsHubGateway
    private static let maxDepth = 8
    private static let pageLimit = 200

    init(gateway: AgentsHubGateway) { self.gateway = gateway }

    // MARK: Agents

    func loadAgents() async {
        isLoadingAgents = true
        agentsError = nil
        defer { isLoadingAgents = false }
        do {
            let request = gateway.request
            try await OpenClawChatAgentsListResponse.load(
                request: { try await request($0) },
                isCurrent: { !Task.isCancelled },
                onUpdate: { [weak self] catalog in
                    guard let self, let catalog else { return }
                    self.agents = catalog.agents
                    self.defaultAgentID = catalog.defaultId
                })
        } catch is CancellationError {
        } catch {
            agentsError = error.localizedDescription
        }
    }

    /// Recharge ce qui est affiché (sessions de l'agent courant et arbre ouvert) après `sessions.changed`.
    func refresh() async {
        if let agentID = trackedAgentID { await loadSessions(agentID: agentID) }
        if let root = trackedRoot, !isLoadingTree { await loadTree(root: root) }
    }

    func loadSessions(agentID: String) async {
        trackedAgentID = agentID
        do {
            let data = try await gateway.request(OpenClawChatGatewayRequests.sessionsList(
                limit: Self.pageLimit, search: nil, archived: false, agentID: agentID,
                includeGlobal: false))
            sessions = try JSONDecoder().decode(OpenClawChatSessionsListResponse.self, from: data).sessions
        } catch is CancellationError {
        } catch {
            agentsError = error.localizedDescription
        }
    }

    // MARK: Subagent tree

    /// Breadth-first load of descendants via `sessions.list(spawnedBy:)`.
    func loadTree(root: OpenClawChatSessionEntry) async {
        trackedRoot = root
        isLoadingTree = true
        treeError = nil
        defer { isLoadingTree = false }
        var all: [String: OpenClawChatSessionEntry] = [root.key: root]
        var frontier = [root]
        do {
            for _ in 0..<Self.maxDepth where !frontier.isEmpty {
                var next: [OpenClawChatSessionEntry] = []
                for parent in frontier {
                    try Task.checkCancellation()
                    let data = try await gateway.request(OpenClawChatGatewayRequests.sessionsList(
                        limit: Self.pageLimit, search: nil, archived: false,
                        agentID: parent.agentId, includeGlobal: false, spawnedBy: parent.key))
                    let page = try JSONDecoder().decode(OpenClawChatSessionsListResponse.self, from: data)
                    for row in page.sessions where all[row.key] == nil {
                        all[row.key] = row
                        next.append(row)
                    }
                }
                frontier = next
            }
            tree = SubagentTreeBuilder.build(rootKey: root.key, rows: Array(all.values))
        } catch is CancellationError {
        } catch {
            treeError = error.localizedDescription
        }
    }

    var visibleRows: [FlatSubagentRow] {
        tree.map { SubagentTreeBuilder.flatten($0, collapsed: collapsed) } ?? []
    }

    func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    // MARK: Stop

    /// Aborts every active run in the node and its descendants (chat.abort per runId).
    func stop(_ node: SubagentNode) async {
        let runs = node.activeRuns
        guard !runs.isEmpty else { return }
        busyKeys.insert(node.id)
        actionError = nil
        defer { busyKeys.remove(node.id) }
        for run in runs {
            do {
                _ = try await gateway.request(OpenClawChatGatewayRequests.abortRun(
                    sessionKey: run.sessionKey, agentID: run.agentID, runID: run.runID))
            } catch {
                actionError = error.localizedDescription
            }
        }
        if let tree { await loadTree(root: tree.session) }
    }

    // MARK: Launch

    /// Creates a child session under `parent` (sessions.create with parentSessionKey) then sends the task.
    func launch(parent: OpenClawChatSessionEntry, agentID: String, label: String, task: String) async -> String? {
        let text = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        busyKeys.insert(parent.key)
        actionError = nil
        defer { busyKeys.remove(parent.key) }
        do {
            let key = "agent:\(agentID):subagent:\(UUID().uuidString.lowercased())"
            let data = try await gateway.request(OpenClawChatGatewayRequests.createSession(
                key: key, agentID: agentID, label: label.isEmpty ? nil : label,
                parentSessionKey: parent.key, worktree: nil))
            let created = try JSONDecoder().decode(OpenClawChatCreateSessionResponse.self, from: data)
            try await gateway.sendMessage(created.key, agentID, text)
            await loadTree(root: tree?.session ?? parent)
            return created.key
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    // MARK: Result

    func loadResult(for node: SubagentNode) async {
        isLoadingResult = true
        resultText = nil
        defer { isLoadingResult = false }
        if let fetch = gateway.fetchResultText {
            do { resultText = try await fetch(node.session.key) } catch { actionError = error.localizedDescription }
        }
        if resultText?.isEmpty != false { resultText = node.session.lastMessagePreview }
    }
}
