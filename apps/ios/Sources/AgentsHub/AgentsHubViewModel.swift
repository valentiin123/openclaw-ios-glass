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
    var canCreateAgent = false

    private(set) var isCreatingAgent = false
    private(set) var createAgentError: String?

    /// Agents board (grid of tiles): flat session list of the selected agent plus the direct children of its
    /// root conversations (and of the OpenClaw system chat, whose subagents are still listed as tiles).
    private(set) var boardSessions: [OpenClawChatSessionEntry] = []
    /// Bumped at every write of `boardSessions`. The board view keys its tile list on it instead of comparing
    /// the whole session array (each row is a large struct) at every render.
    private(set) var boardRevision: Int = 0
    private(set) var boardAgentID: String?
    private(set) var isLoadingBoard = false
    private(set) var boardError: String?

    private var trackedAgentID: String?
    private var trackedRoot: OpenClawChatSessionEntry?
    /// Single pending reload requested by `sessions.changed` (see `requestRefresh`). Not observed.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequested: Bool = false

    private let gateway: AgentsHubGateway
    private static let maxDepth = 8
    private static let pageLimit = 200
    private static let maxBoardRoots = 8
    /// Base delay of the automatic retries after a failed initial load (attempt n waits n x this delay).
    private static let retryDelayNanoseconds: UInt64 = 1_000_000_000

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
        if let boardID = boardAgentID { await loadBoard(agentID: boardID) }
    }

    // MARK: Coalesced refresh

    /// Asks for a reload after `sessions.changed`. A burst of events (a run that spawns several subagents
    /// emits many) is collapsed: one short debounce, then a single reload, and one more only if another
    /// event arrived while it was running. Without this every event started its own set of gateway calls.
    func requestRefresh() {
        self.refreshRequested = true
        if self.refreshTask != nil { return }
        self.refreshTask = Task { [weak self] in
            await self?.drainRefreshRequests()
        }
    }

    /// Stops a pending reload (the screen that observed the events went away).
    func cancelRefreshRequests() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.refreshRequested = false
    }

    private func drainRefreshRequests() async {
        while self.refreshRequested, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { break }
            self.refreshRequested = false
            await self.refresh()
        }
        // A cancelled drain was already detached by `cancelRefreshRequests`; clearing here could drop a newer one.
        if !Task.isCancelled { self.refreshTask = nil }
    }

    // MARK: Off-main fetch and decode

    /// One `sessions.list` call. The payload is decoded off the main actor: with 200 rows per page and up to
    /// nine pages per board load, decoding on the main actor was a visible hitch.
    nonisolated private static func fetchSessions(
        request: @Sendable (OpenClawChatGatewayRequest) async throws -> Data,
        agentID: String,
        spawnedBy: String?,
        limit: Int) async throws -> [OpenClawChatSessionEntry]
    {
        let built: OpenClawChatGatewayRequest = OpenClawChatGatewayRequests.sessionsList(
            limit: limit, search: nil, archived: false, agentID: agentID,
            includeGlobal: false, spawnedBy: spawnedBy)
        let data: Data = try await request(built)
        return try await Self.decodeSessions(data)
    }

    nonisolated private static func decodeSessions(_ data: Data) async throws -> [OpenClawChatSessionEntry] {
        let task: Task<[OpenClawChatSessionEntry], Error> = Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(OpenClawChatSessionsListResponse.self, from: data).sessions
        }
        return try await task.value
    }

    /// Child lookups of every parent, side by side. A failed lookup yields an empty page (the base list stays
    /// usable). Pages come back in the order of `parentKeys`, so merging them gives the sequential result.
    nonisolated private static func fetchChildPages(
        request: @escaping @Sendable (OpenClawChatGatewayRequest) async throws -> Data,
        agentID: String,
        parentKeys: [String],
        limit: Int) async -> [[OpenClawChatSessionEntry]]
    {
        await withTaskGroup(
            of: AgentsHubIndexedPage.self,
            returning: [[OpenClawChatSessionEntry]].self)
        { group in
            for (index, parentKey) in parentKeys.enumerated() {
                group.addTask {
                    let rows: [OpenClawChatSessionEntry] = (try? await Self.fetchSessions(
                        request: request, agentID: agentID, spawnedBy: parentKey, limit: limit)) ?? []
                    return AgentsHubIndexedPage(index: index, rows: rows)
                }
            }
            var collected: [AgentsHubIndexedPage] = []
            for await page in group {
                collected.append(page)
            }
            collected.sort { (lhs: AgentsHubIndexedPage, rhs: AgentsHubIndexedPage) -> Bool in
                lhs.index < rhs.index
            }
            return collected.map { (page: AgentsHubIndexedPage) -> [OpenClawChatSessionEntry] in page.rows }
        }
    }

    // MARK: Retry

    /// `loadAgents` with up to `maxRetries` automatic retries (short delay) after a failure. While a retry is
    /// pending the error is hidden and the loading flag stays up; only the last failure remains in `agentsError`.
    func loadAgentsWithRetry(maxRetries: Int = 2) async {
        var attempt: Int = 0
        while true {
            await self.loadAgents()
            guard self.agentsError != nil, attempt < maxRetries, !Task.isCancelled else { return }
            attempt += 1
            self.agentsError = nil
            self.isLoadingAgents = true
            try? await Task.sleep(nanoseconds: UInt64(attempt) * Self.retryDelayNanoseconds)
            self.isLoadingAgents = false
            if Task.isCancelled { return }
        }
    }

    /// `loadBoard` with the same automatic retry policy as `loadAgentsWithRetry`.
    func loadBoardWithRetry(agentID: String, maxRetries: Int = 2) async {
        var attempt: Int = 0
        while true {
            await self.loadBoard(agentID: agentID)
            guard self.boardError != nil, attempt < maxRetries, !Task.isCancelled else { return }
            attempt += 1
            self.boardError = nil
            self.isLoadingBoard = true
            try? await Task.sleep(nanoseconds: UInt64(attempt) * Self.retryDelayNanoseconds)
            self.isLoadingBoard = false
            if Task.isCancelled { return }
        }
    }

    // MARK: Board

    /// Loads the sessions shown by the Agents board: `sessions.list` for the agent, merged with
    /// `sessions.list(spawnedBy: <parent>)` for the system chat and each recent root conversation, so
    /// subagents are found even when the plain list omits them.
    func loadBoard(agentID: String) async {
        if boardAgentID != agentID {
            boardSessions = []
            boardRevision &+= 1
        }
        boardAgentID = agentID
        isLoadingBoard = true
        boardError = nil
        defer { isLoadingBoard = false }
        var rows: [OpenClawChatSessionEntry] = []
        let request: @Sendable (OpenClawChatGatewayRequest) async throws -> Data = gateway.request
        let limit: Int = Self.pageLimit
        do {
            rows = try await Self.fetchSessions(request: request, agentID: agentID, spawnedBy: nil, limit: limit)
        } catch is CancellationError {
            return
        } catch {
            boardError = error.localizedDescription
            return
        }
        var known: Set<String> = []
        for row in rows { known.insert(row.key) }
        var mainKey: String = "agent:\(agentID):main"
        for row in rows where row.isMain == true {
            mainKey = row.key
            break
        }
        var parentKeys: [String] = [mainKey]
        let rootKeys: [String] = AgentTileFactory.rootKeys(rows: rows, agentID: agentID, limit: Self.maxBoardRoots)
        for key in rootKeys where !parentKeys.contains(key) {
            parentKeys.append(key)
        }
        // The child lookups are independent: run them side by side instead of one after the other, then merge
        // in the original parent order so the result is identical to the sequential version.
        let pages: [[OpenClawChatSessionEntry]] = await Self.fetchChildPages(
            request: request, agentID: agentID, parentKeys: parentKeys, limit: limit)
        if Task.isCancelled { return }
        for page in pages {
            for row in page where !known.contains(row.key) {
                known.insert(row.key)
                rows.append(row)
            }
        }
        if boardAgentID == agentID {
            boardSessions = rows
            boardRevision &+= 1
        }
    }

    func loadSessions(agentID: String) async {
        trackedAgentID = agentID
        do {
            let data = try await gateway.request(OpenClawChatGatewayRequests.sessionsList(
                limit: Self.pageLimit, search: nil, archived: false, agentID: agentID,
                includeGlobal: false))
            sessions = try await Self.decodeSessions(data)
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
                    let pageRows: [OpenClawChatSessionEntry] = try await Self.decodeSessions(data)
                    for row in pageRows where all[row.key] == nil {
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

    // MARK: Delete

    /// Deletes a conversation (`sessions.delete`, transcript included) and drops it from the board at once.
    /// Returns true on success; on failure `actionError` explains why and the board is left untouched.
    func deleteSession(_ session: OpenClawChatSessionEntry) async -> Bool {
        busyKeys.insert(session.key)
        actionError = nil
        defer { busyKeys.remove(session.key) }
        do {
            _ = try await gateway.request(OpenClawChatGatewayRequests.deleteSession(
                sessionKey: session.key, agentID: session.agentId))
            boardSessions.removeAll { $0.key == session.key }
            boardRevision &+= 1
            sessions.removeAll { $0.key == session.key }
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: Rename

    /// Sets the conversation label (`sessions.patch`). An empty (trimmed) label clears it.
    /// Updates `boardSessions` / `sessions` locally at once, then reloads the board.
    /// Returns true on success; on failure `actionError` explains why and the board is left untouched.
    func renameSession(_ session: OpenClawChatSessionEntry, label: String) async -> Bool {
        let trimmed: String = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let newLabel: String? = trimmed.isEmpty ? nil : trimmed
        busyKeys.insert(session.key)
        actionError = nil
        defer { busyKeys.remove(session.key) }
        do {
            let request: OpenClawChatGatewayRequest = OpenClawChatGatewayRequests.patchSession(
                sessionKey: session.key,
                agentID: session.agentId,
                label: .some(newLabel),
                category: nil,
                pinned: nil,
                archived: nil,
                unreadPatch: nil)
            _ = try await gateway.request(request)
            if let index = boardSessions.firstIndex(where: { $0.key == session.key }) {
                boardSessions[index].label = newLabel
                boardRevision &+= 1
            }
            if let index = sessions.firstIndex(where: { $0.key == session.key }) {
                sessions[index].label = newLabel
            }
            if let agentID = session.agentId ?? boardAgentID {
                await loadBoard(agentID: agentID)
            }
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    // MARK: Create agent

    /// `agents.create` (scope operator.admin). Built locally because OpenClawChatGatewayRequests has no constructor.
    /// Returns the new agent id on success, nil on failure (see `createAgentError`).
    func createAgent(name: String, agentID: String, emoji: String, modelID: String) async -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        isCreatingAgent = true
        createAgentError = nil
        defer { isCreatingAgent = false }
        var params: [String: AnyCodable] = ["name": AnyCodable(trimmedName)]
        let optional: [(String, String)] = [("agentId", agentID), ("emoji", emoji), ("model", modelID)]
        for (key, raw) in optional {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { params[key] = AnyCodable(value) }
        }
        let request = OpenClawChatGatewayRequest(method: "agents.create", params: params, timeoutMs: 30000)
        do {
            let data = try await gateway.request(request)
            let created = try JSONDecoder().decode(AgentsHubCreatedAgent.self, from: data)
            await loadAgents()
            return created.agentId
        } catch {
            createAgentError = error.localizedDescription
            return nil
        }
    }

    func clearCreateAgentError() { createAgentError = nil }

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

/// One page of child sessions tagged with the position of its parent, so parallel results merge in order.
private struct AgentsHubIndexedPage: Sendable {
    let index: Int
    let rows: [OpenClawChatSessionEntry]
}
