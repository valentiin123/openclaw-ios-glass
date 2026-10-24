import Foundation
import OpenClawChatUI

// Pure value types derived from `OpenClawChatSessionEntry` (fields verified in ChatSessions.swift):
// key, parentSessionKey, spawnedBy, childSessions, status, lastRunError, hasActiveRun, activeRunIds,
// hasActiveSubagentRun, subagentRunState, startedAt, endedAt, runtimeMs, totalTokens, model,
// lastMessagePreview, derivedTitle, displayName, label, agentId.

enum AgentsHubRunStatus: Equatable, Sendable {
    case running
    case waitingOnChildren
    case failed
    case done
    case idle

    init(_ s: OpenClawChatSessionEntry) {
        let status = s.status?.lowercased()
        if s.hasActiveRun == true || status == "running" {
            self = .running
        } else if s.hasActiveSubagentRun == true || s.subagentRunState == "active" {
            self = .waitingOnChildren
        } else if s.lastRunError?.isEmpty == false || status == "failed" || status == "error" {
            self = .failed
        } else if s.endedAt != nil || status == "done" || status == "completed" {
            self = .done
        } else {
            self = .idle
        }
    }

    var isActive: Bool { self == .running || self == .waitingOnChildren }

    var label: String {
        switch self {
        case .running: String(localized: "Running")
        case .waitingOnChildren: String(localized: "Waiting on subagents")
        case .failed: String(localized: "Failed")
        case .done: String(localized: "Done")
        case .idle: String(localized: "Idle")
        }
    }

    var symbol: String {
        switch self {
        case .running: "play.circle.fill"
        case .waitingOnChildren: "hourglass.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .done: "checkmark.circle.fill"
        case .idle: "circle.dashed"
        }
    }
}

/// Decoded result of `agents.create` (AgentsCreateResultSchema). Only the fields the UI needs.
struct AgentsHubCreatedAgent: Decodable, Equatable, Sendable {
    let agentId: String
    let name: String
    let workspace: String?
    let model: String?
}

struct SubagentNode: Identifiable, Equatable, Sendable {
    var id: String { session.key }
    let session: OpenClawChatSessionEntry
    let status: AgentsHubRunStatus
    let children: [SubagentNode]

    var descendantCount: Int { children.reduce(children.count) { $0 + $1.descendantCount } }
    var activeDescendantCount: Int {
        children.reduce(0) { $0 + ($1.status.isActive ? 1 : 0) + $1.activeDescendantCount }
    }
    var failedDescendantCount: Int {
        children.reduce(0) { $0 + ($1.status == .failed ? 1 : 0) + $1.failedDescendantCount }
    }

    var title: String {
        for candidate in [session.label, session.displayName, session.derivedTitle] {
            if let t = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        }
        return session.key.split(separator: ":").last.map(String.init) ?? session.key
    }

    /// Every active run id in this node and below (for "stop all").
    var activeRuns: [(sessionKey: String, agentID: String?, runID: String)] {
        let own = (session.activeRunIds ?? []).map { (session.key, session.agentId, $0) }
        return own + children.flatMap(\.activeRuns)
    }
}

struct FlatSubagentRow: Identifiable, Equatable, Sendable {
    var id: String { node.id }
    let node: SubagentNode
    let depth: Int
    let isExpanded: Bool
}

enum SubagentTreeBuilder {
    private static let maxDepth = 16

    /// Builds a forest rooted at `rootKey` from a flat session list. Parent = parentSessionKey ?? spawnedBy;
    /// `childSessions` of the root is used as a fallback link. Cycle- and depth-safe.
    static func build(rootKey: String, rows: [OpenClawChatSessionEntry]) -> SubagentNode? {
        var byKey: [String: OpenClawChatSessionEntry] = [:]
        for row in rows { byKey[row.key] = row }
        guard let root = byKey[rootKey] else { return nil }
        var childrenOf: [String: [String]] = [:]
        for row in rows {
            let parent = (row.parentSessionKey?.nonEmpty ?? row.spawnedBy?.nonEmpty)
            if let parent, parent != row.key { childrenOf[parent, default: []].append(row.key) }
        }
        for key in root.childSessions ?? [] where byKey[key] != nil && key != rootKey {
            if !(childrenOf[rootKey]?.contains(key) ?? false) { childrenOf[rootKey, default: []].append(key) }
        }
        var visited: Set<String> = []
        func make(_ key: String, depth: Int) -> SubagentNode? {
            guard depth <= maxDepth, let entry = byKey[key], visited.insert(key).inserted else { return nil }
            let kids = (childrenOf[key] ?? [])
                .compactMap { make($0, depth: depth + 1) }
                .sorted { ($0.session.startedAt ?? $0.session.createdAt ?? 0) < ($1.session.startedAt ?? $1.session.createdAt ?? 0) }
            return SubagentNode(session: entry, status: AgentsHubRunStatus(entry), children: kids)
        }
        _ = root
        return make(rootKey, depth: 0)
    }

    static func flatten(_ root: SubagentNode, collapsed: Set<String>) -> [FlatSubagentRow] {
        var out: [FlatSubagentRow] = []
        func walk(_ node: SubagentNode, depth: Int) {
            let expanded = !collapsed.contains(node.id)
            out.append(FlatSubagentRow(node: node, depth: depth, isExpanded: expanded))
            if expanded { node.children.forEach { walk($0, depth: depth + 1) } }
        }
        walk(root, depth: 0)
        return out
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
