import Foundation

/// A chat whose own turn has ended while a helper session it started is still running.
struct ChatSubagentWait: Equatable {
    struct Child: Equatable, Identifiable {
        let key: String
        let name: String
        var status: OpenClawChatSwarmDotStatus = .running

        var id: String { self.key }
    }

    /// Name a single known unfinished helper; the roster may still be partial.
    let child: Child?

    /// Every known unfinished helper, in roster order. May be shorter than the real count
    /// (or empty) while the roster is still loading; the parent flag alone proves a wait.
    var children: [Child] = []

    static func resolve(
        session: OpenClawChatSessionEntry?,
        sessions: [OpenClawChatSessionEntry],
        runActive: Bool) -> ChatSubagentWait?
    {
        guard let session, !runActive, session.archived != true,
              session.hasActiveSubagentRun == true, !Self.isRunning(session)
        else { return nil }
        let running = sessions.filter { row in
            guard row.key != session.key, row.archived != true,
                  Self.isRunning(row) || row.hasActiveSubagentRun == true
            else { return false }
            if let parent = row.parentSessionKey ?? row.spawnedBy { return parent == session.key }
            return session.childSessions?.contains(row.key) == true
        }
        let rows: [Child] = running.map { row in
            let status: OpenClawChatSwarmDotStatus = SelfContainedSwarmHelpers.status(row) ?? .running
            let name: String = ChatSessionSidebarModel.displayName(for: row)
            return Child(key: row.key, name: name, status: status)
        }
        let single: Child? = rows.count == 1 ? rows.first : nil
        return ChatSubagentWait(child: single, children: rows)
    }

    /// Match src/shared/session-run-state.ts: terminal status wins over stale liveness.
    private static func isRunning(_ session: OpenClawChatSessionEntry) -> Bool {
        if let status = session.status, status != "queued", status != "running" { return false }
        return session.hasActiveRun ?? (session.status == "running" || session.status == "queued")
    }
}

extension OpenClawChatViewModel {
    var subagentWait: ChatSubagentWait? {
        ChatSubagentWait.resolve(
            session: self.currentSessionEntry(),
            sessions: self.sessions,
            runActive: self.hasBlockingRunActivity)
    }
}
