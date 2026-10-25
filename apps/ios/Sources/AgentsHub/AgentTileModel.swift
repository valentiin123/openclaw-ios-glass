import Foundation
import OpenClawChatUI
import SwiftUI

// Pure derivation of what an Agents board tile shows, from `OpenClawChatSessionEntry`.
// Reuses `AgentsHubRunStatus` (status / hasActiveRun / subagentRunState / endedAt ...) and adds the
// playful Claude Code style wording on top. No Gateway access here.
//
// "Main" tiles = root conversations of the selected agent: sessions started directly by the user,
// not spawned by another agent or subagent. The OpenClaw system chat (`agent:<id>:main`) is never a tile.

// MARK: - State

enum AgentTileState: Equatable, Sendable {
    case working
    case thinking
    case reading
    case searching
    case writing
    case delegating
    case queued
    case hungry
    case done
    case napping
    case failed
    case stuck

    var label: String {
        switch self {
        case .working: String(localized: "Working")
        case .thinking: String(localized: "Thinking")
        case .reading: String(localized: "Reading")
        case .searching: String(localized: "Searching")
        case .writing: String(localized: "Writing")
        case .delegating: String(localized: "Delegating")
        case .queued: String(localized: "Warming up")
        case .hungry: String(localized: "Hungry")
        case .done: String(localized: "Done")
        case .napping: String(localized: "Napping")
        case .failed: String(localized: "Oops")
        case .stuck: String(localized: "Stuck")
        }
    }

    /// A run is in progress (progress outline loops, colored sprite).
    var isActive: Bool {
        switch self {
        case .working, .thinking, .reading, .searching, .writing, .delegating, .queued: true
        default: false
        }
    }

    /// Greyed sprite with "Zz".
    var isAsleep: Bool {
        self == .done || self == .napping
    }

    var bubble: AgentTileBubbleKind? {
        switch self {
        case .working, .searching, .writing: .speech
        case .thinking, .reading, .delegating, .queued, .hungry: .thought
        case .failed, .stuck: .alert
        case .done, .napping: nil
        }
    }

    var tint: Color {
        switch self {
        case .working, .thinking, .reading, .searching, .writing, .queued: OpenClawBrand.info
        case .delegating, .hungry: OpenClawBrand.warn
        case .done: OpenClawBrand.ok
        case .napping: OpenClawBrand.textSecondary
        case .failed, .stuck: OpenClawBrand.danger
        }
    }
}

// MARK: - Item

struct AgentTileItem: Identifiable, Equatable, Sendable {
    var id: String { session.key }
    let session: OpenClawChatSessionEntry
    /// True for a "main" tile: a root conversation of the agent (always visible, listed first).
    let isMain: Bool
    let name: String
    /// Readable name of the parent conversation when this tile is a subagent whose parent is known.
    let parentName: String?
    let sprite: AgentTileSpriteKind
    let runStatus: AgentsHubRunStatus
    let state: AgentTileState
    let toolLine: String?
    /// Only set while a run is active (drives the live timer).
    let startDate: Date?
    /// Elapsed run time at the moment the item was built.
    let elapsed: TimeInterval?
    /// Known progress 0...1. nil = unknown (looping outline while active).
    let progress: Double?
    /// Sort key: most recent first.
    let recency: Double

    var accessibilityText: String {
        var parts: [String] = [name, state.label]
        if let parentName {
            parts.append(String(localized: "Subagent of \(parentName)"))
        }
        if let elapsed, let spoken = AgentTileFormat.duration(seconds: elapsed, spelledOut: true) {
            parts.append(spoken)
        }
        if let toolLine {
            parts.append(toolLine)
        }
        return parts.joined(separator: ", ")
    }

    var canBeStopped: Bool {
        !(session.activeRunIds ?? []).isEmpty
    }
}

// MARK: - Naming (deterministic)

enum AgentTileNaming {
    static let names: [String] = [
        "Pixel", "Mochi", "Nova", "Pip", "Bean", "Zed", "Echo", "Juno",
        "Kiwi", "Orbit", "Blip", "Cosmo", "Dot", "Fizz", "Gizmo", "Haze",
        "Ziggy", "Lumi", "Miso", "Nimbus", "Otto", "Pogo", "Quill", "Riff",
        "Sprout", "Taco", "Ume", "Vex", "Wisp", "Yuzu", "Zap", "Ash",
        "Bolt", "Cleo", "Dash", "Ember", "Fern", "Gus", "Hugo", "Ivy",
        "Jazz", "Koko", "Luna", "Moss", "Nori", "Olive", "Peep", "Rune",
    ]

    /// FNV-1a. Swift's `hashValue` is randomized per launch, so it cannot be used here.
    static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 1_099_511_628_211
        }
        return value
    }

    static func sprite(for key: String) -> AgentTileSpriteKind {
        let all: [AgentTileSpriteKind] = AgentTileSpriteKind.allCases
        let index: Int = Int(hash(key) % UInt64(all.count))
        return all[index]
    }

    static func name(for key: String) -> String {
        let mixed: UInt64 = hash(key) >> 11
        let index: Int = Int(mixed % UInt64(names.count))
        return names[index]
    }
}

// MARK: - Formatting

enum AgentTileFormat {
    static func duration(seconds: TimeInterval, spelledOut: Bool) -> String? {
        guard seconds >= 1 else { return nil }
        let formatter: DateComponentsFormatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = spelledOut ? .full : .abbreviated
        return formatter.string(from: seconds)
    }
}

// MARK: - Factory

enum AgentTileFactory {
    /// Finished subagents disappear this long after they ended. Root conversations never do.
    static let retention: TimeInterval = 30 * 60
    private static let doneWindow: TimeInterval = 5 * 60
    private static let hungryWindow: TimeInterval = 10 * 60
    private static let titleLimit: Int = 28

    private static let readWords: [String] = ["read", "lecture", "lire", "open file", "cat "]
    private static let searchWords: [String] = ["search", "grep", "web", "fetch", "recherch", "browse"]
    private static let writeWords: [String] = ["write", "edit", "patch", "writing", "écri", "ecri"]
    private static let thinkWords: [String] = ["think", "reason", "plan"]

    /// Root conversations first (always shown, most recent activity first), then subagents
    /// (active first, then the most recent). Outdated subagents are dropped.
    static func items(sessions: [OpenClawChatSessionEntry], agentID: String, now: Date) -> [AgentTileItem] {
        var byKey: [String: OpenClawChatSessionEntry] = [:]
        for session in sessions {
            byKey[session.key] = session
        }
        var roots: [AgentTileItem] = []
        var subagents: [AgentTileItem] = []
        for session in sessions {
            if isRootConversation(session) {
                let title: String = displayName(for: session)
                let rootItem: AgentTileItem = makeItem(session, isMain: true, name: title, parentName: nil, now: now)
                roots.append(rootItem)
                continue
            }
            if !isSubagent(session) { continue }
            if isOutdated(session, now: now) { continue }
            let name: String = AgentTileNaming.name(for: session.key)
            let parent: String? = parentName(of: session, in: byKey)
            let subItem: AgentTileItem = makeItem(session, isMain: false, name: name, parentName: parent, now: now)
            subagents.append(subItem)
        }
        roots.sort(by: AgentTileFactory.isRootOrderedBefore)
        subagents.sort(by: AgentTileFactory.isOrderedBefore)
        var result: [AgentTileItem] = roots
        result.append(contentsOf: subagents)
        return result
    }

    /// One item for any session (used by the chat header and the tree screen). Same wording as the board tile.
    /// Root conversations get their readable title even when `isMain` is false.
    static func item(for session: OpenClawChatSessionEntry, isMain: Bool, now: Date) -> AgentTileItem {
        let readable: Bool = isMain || isRootConversation(session)
        var name: String = AgentTileNaming.name(for: session.key)
        if readable {
            name = displayName(for: session)
        }
        return makeItem(session, isMain: isMain, name: name, parentName: nil, now: now)
    }

    /// Detail / stop reuse the existing AgentsHub types.
    static func node(for item: AgentTileItem) -> SubagentNode {
        SubagentNode(session: item.session, status: item.runStatus, children: [])
    }

    /// Keys of the most recent root conversations (the view model loads their subagents too).
    static func rootKeys(rows: [OpenClawChatSessionEntry], agentID: String, limit: Int) -> [String] {
        var roots: [OpenClawChatSessionEntry] = []
        for row in rows where isRootConversation(row) {
            roots.append(row)
        }
        roots.sort(by: AgentTileFactory.isSessionMoreRecent)
        var keys: [String] = []
        for root in roots {
            if keys.count >= limit { break }
            keys.append(root.key)
        }
        return keys
    }

    // MARK: Selection

    private static func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The OpenClaw system chat of an agent (`agent:<id>:main`). Reachable from Home only, never a tile.
    static func isSystemMain(_ session: OpenClawChatSessionEntry) -> Bool {
        if session.isMain == true { return true }
        if session.key == "main" { return true }
        let parts: [Substring] = session.key.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0] == "agent", parts[2] == "main" { return true }
        return false
    }

    static func isSubagent(_ session: OpenClawChatSessionEntry) -> Bool {
        if session.isMain == true { return false }
        if hasText(session.spawnedBy) { return true }
        if hasText(session.parentSessionKey) { return true }
        if hasText(session.subagentRole) { return true }
        return session.key.contains(":subagent:")
    }

    /// A conversation started directly by the user in this agent: not the system chat, not spawned by
    /// another session, not a background / heartbeat run.
    static func isRootConversation(_ session: OpenClawChatSessionEntry) -> Bool {
        if isSystemMain(session) { return false }
        if isSubagent(session) { return false }
        if session.isBackground == true { return false }
        if session.classification == "heartbeat" { return false }
        return true
    }

    private static func date(ms: Double?) -> Date? {
        guard let ms, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// End date when known, otherwise the latest activity timestamp.
    private static func referenceDate(_ session: OpenClawChatSessionEntry) -> Date? {
        let candidates: [Double?] = [
            session.endedAt,
            session.lastActivityAt,
            session.lastInteractionAt,
            session.updatedAt,
            session.startedAt,
        ]
        for candidate in candidates {
            if let found = date(ms: candidate) { return found }
        }
        return nil
    }

    /// Most recent of all known timestamps (used to order root conversations).
    private static func latestActivity(_ session: OpenClawChatSessionEntry) -> Date? {
        let candidates: [Double?] = [
            session.endedAt,
            session.lastActivityAt,
            session.lastInteractionAt,
            session.updatedAt,
            session.startedAt,
            session.createdAt,
        ]
        var best: Double = 0
        for candidate in candidates {
            if let value = candidate, value > best { best = value }
        }
        guard best > 0 else { return nil }
        return Date(timeIntervalSince1970: best / 1000)
    }

    private static func isSessionMoreRecent(_ lhs: OpenClawChatSessionEntry, _ rhs: OpenClawChatSessionEntry) -> Bool {
        let left: Double = latestActivity(lhs)?.timeIntervalSince1970 ?? 0
        let right: Double = latestActivity(rhs)?.timeIntervalSince1970 ?? 0
        if left != right { return left > right }
        return lhs.key < rhs.key
    }

    /// Non-active subagents older than `retention` (or without any timestamp) are hidden.
    private static func isOutdated(_ session: OpenClawChatSessionEntry, now: Date) -> Bool {
        let status: AgentsHubRunStatus = AgentsHubRunStatus(session)
        if status.isActive { return false }
        guard let reference = referenceDate(session) else { return true }
        return now.timeIntervalSince(reference) > retention
    }

    // MARK: Names

    private static func truncated(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let head: String = String(text.prefix(limit)).trimmingCharacters(in: .whitespaces)
        return head + "…"
    }

    /// One usable title line, or nil when the text is empty or only a generic system name.
    private static func titleCandidate(_ raw: String?, key: String) -> String? {
        guard let line = firstLine(raw) else { return nil }
        let lowered: String = line.lowercased()
        if line == key { return nil }
        if lowered == "main" || lowered == "openclaw" { return nil }
        return truncated(line, limit: titleLimit)
    }

    /// Session label, derived title, display name, then the truncated last message preview.
    private static func readableTitle(_ session: OpenClawChatSessionEntry) -> String? {
        let candidates: [String?] = [
            session.label,
            session.derivedTitle,
            session.displayName,
            session.lastMessagePreview,
        ]
        for candidate in candidates {
            if let title = titleCandidate(candidate, key: session.key) { return title }
        }
        return nil
    }

    /// Name of a root conversation tile. Falls back to the deterministic name.
    private static func displayName(for session: OpenClawChatSessionEntry) -> String {
        if isSystemMain(session) { return String(localized: "Main") }
        if let title = readableTitle(session) { return title }
        return AgentTileNaming.name(for: session.key)
    }

    private static func spriteKind(for session: OpenClawChatSessionEntry) -> AgentTileSpriteKind {
        if isSystemMain(session) { return .robot }
        return AgentTileNaming.sprite(for: session.key)
    }

    /// Name of the session that spawned `session`, when it is part of the loaded list.
    private static func parentName(
        of session: OpenClawChatSessionEntry,
        in byKey: [String: OpenClawChatSessionEntry]) -> String?
    {
        var parentKey: String?
        if hasText(session.spawnedBy) {
            parentKey = session.spawnedBy
        } else if hasText(session.parentSessionKey) {
            parentKey = session.parentSessionKey
        }
        guard let parentKey, let parent = byKey[parentKey] else { return nil }
        if isSystemMain(parent) { return nil }
        if isRootConversation(parent) { return displayName(for: parent) }
        return AgentTileNaming.name(for: parent.key)
    }

    // MARK: Item

    private static func makeItem(
        _ session: OpenClawChatSessionEntry,
        isMain: Bool,
        name: String,
        parentName: String?,
        now: Date) -> AgentTileItem
    {
        let status: AgentsHubRunStatus = AgentsHubRunStatus(session)
        let reference: Date? = referenceDate(session)
        var age: TimeInterval?
        if let reference {
            age = now.timeIntervalSince(reference)
        }
        let tool: String? = toolText(session, status: status, now: now)
        let state: AgentTileState = deriveState(session, status: status, tool: tool, age: age)
        let start: Date? = startDate(session)
        var runningStart: Date?
        if status.isActive {
            runningStart = start
        }
        let progress: Double? = (status == .done) ? 1 : nil
        let sprite: AgentTileSpriteKind = spriteKind(for: session)
        var recency: Double = (start ?? reference)?.timeIntervalSince1970 ?? 0
        if isMain, let latest = latestActivity(session) {
            recency = latest.timeIntervalSince1970
        }
        return AgentTileItem(
            session: session,
            isMain: isMain,
            name: name,
            parentName: parentName,
            sprite: sprite,
            runStatus: status,
            state: state,
            toolLine: tool,
            startDate: runningStart,
            elapsed: elapsed(session, status: status, start: start, now: now),
            progress: progress,
            recency: recency)
    }

    private static func startDate(_ session: OpenClawChatSessionEntry) -> Date? {
        if let started = date(ms: session.startedAt) { return started }
        return date(ms: session.createdAt)
    }

    private static func elapsed(
        _ session: OpenClawChatSessionEntry,
        status: AgentsHubRunStatus,
        start: Date?,
        now: Date) -> TimeInterval?
    {
        if status.isActive {
            if let start { return max(0, now.timeIntervalSince(start)) }
            if let runtime = session.runtimeMs, runtime > 0 { return runtime / 1000 }
            return nil
        }
        if let runtime = session.runtimeMs, runtime > 0 { return runtime / 1000 }
        if let start, let ended = date(ms: session.endedAt) { return max(0, ended.timeIntervalSince(start)) }
        return nil
    }

    // MARK: Tool / activity line

    private static func firstLine(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let line: String = trimmed.components(separatedBy: .newlines).first ?? trimmed
        return String(line.prefix(80))
    }

    /// No dedicated "current tool" field exists on the session row. Best available signals while active:
    /// the declared agent status note (until it expires), then the observer digest headline.
    private static func toolText(
        _ session: OpenClawChatSessionEntry,
        status: AgentsHubRunStatus,
        now: Date) -> String?
    {
        if status == .failed {
            return firstLine(session.lastRunError)
        }
        guard status.isActive else { return nil }
        let nowMs: Double = now.timeIntervalSince1970 * 1000
        if let declared = session.agentStatus, declared.expiresAt > nowMs, let line = firstLine(declared.note) {
            return line
        }
        if let digest = session.observerDigest {
            let health: String = digest.health.lowercased()
            if health != "done", health != "failed" { return firstLine(digest.headline) }
        }
        return nil
    }

    // MARK: State

    private static func containsAny(_ text: String, _ words: [String]) -> Bool {
        for word in words where text.contains(word) {
            return true
        }
        return false
    }

    private static func activeState(tool: String?) -> AgentTileState {
        guard let tool else { return .thinking }
        let text: String = tool.lowercased()
        if containsAny(text, thinkWords) { return .thinking }
        if containsAny(text, readWords) { return .reading }
        if containsAny(text, searchWords) { return .searching }
        if containsAny(text, writeWords) { return .writing }
        return .working
    }

    private static func deriveState(
        _ session: OpenClawChatSessionEntry,
        status: AgentsHubRunStatus,
        tool: String?,
        age: TimeInterval?) -> AgentTileState
    {
        let rawStatus: String = session.status?.lowercased() ?? ""
        let health: String = session.observerDigest?.health.lowercased() ?? ""
        if rawStatus == "queued", !status.isActive { return .queued }
        if status.isActive {
            if health == "stuck" { return .stuck }
            if health == "waiting-on-user" { return .hungry }
        }
        switch status {
        case .running:
            return activeState(tool: tool)
        case .waitingOnChildren:
            return .delegating
        case .failed:
            return .failed
        case .done:
            if let age, age < doneWindow { return .done }
            return .napping
        case .idle:
            if let age, age < hungryWindow { return .hungry }
            return .napping
        }
    }

    // MARK: Order

    private static func rank(_ item: AgentTileItem) -> Int {
        if item.state.isActive { return 0 }
        if item.state.isAsleep { return 2 }
        return 1
    }

    /// Subagents: active first, then idle, then asleep; most recent first inside each group.
    static func isOrderedBefore(_ lhs: AgentTileItem, _ rhs: AgentTileItem) -> Bool {
        let left: Int = rank(lhs)
        let right: Int = rank(rhs)
        if left != right { return left < right }
        if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
        return lhs.id < rhs.id
    }

    /// Root conversations: most recent activity first.
    static func isRootOrderedBefore(_ lhs: AgentTileItem, _ rhs: AgentTileItem) -> Bool {
        if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
        return lhs.id < rhs.id
    }
}
