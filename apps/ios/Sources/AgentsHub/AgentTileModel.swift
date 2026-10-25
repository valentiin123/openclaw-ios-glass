import Foundation
import OpenClawChatUI
import SwiftUI

// Pure derivation of what an Agents board tile shows, from `OpenClawChatSessionEntry`.
// Reuses `AgentsHubRunStatus` (status / hasActiveRun / subagentRunState / endedAt ...) and adds the
// playful Claude Code style wording on top. No Gateway access here.

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
    let isMain: Bool
    let name: String
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
    /// Finished subagents disappear this long after they ended.
    static let retention: TimeInterval = 30 * 60
    private static let doneWindow: TimeInterval = 5 * 60
    private static let hungryWindow: TimeInterval = 10 * 60

    private static let readWords: [String] = ["read", "lecture", "lire", "open file", "cat "]
    private static let searchWords: [String] = ["search", "grep", "web", "fetch", "recherch", "browse"]
    private static let writeWords: [String] = ["write", "edit", "patch", "writing", "écri", "ecri"]
    private static let thinkWords: [String] = ["think", "reason", "plan"]

    /// Main first, then active tiles, then the most recent. Outdated subagents are dropped.
    static func items(sessions: [OpenClawChatSessionEntry], agentID: String, now: Date) -> [AgentTileItem] {
        let main: OpenClawChatSessionEntry = findMain(sessions: sessions, agentID: agentID)
        var subagents: [AgentTileItem] = []
        for session in sessions {
            if session.key == main.key { continue }
            if !isSubagent(session) { continue }
            if isOutdated(session, now: now) { continue }
            let item: AgentTileItem = makeItem(session, isMain: false, now: now)
            subagents.append(item)
        }
        subagents.sort(by: AgentTileFactory.isOrderedBefore)
        var result: [AgentTileItem] = [makeItem(main, isMain: true, now: now)]
        result.append(contentsOf: subagents)
        return result
    }

    /// One item for any session (used by the subagent chat header). Same wording as the board tile.
    static func item(for session: OpenClawChatSessionEntry, isMain: Bool, now: Date) -> AgentTileItem {
        makeItem(session, isMain: isMain, now: now)
    }

    /// Detail / stop reuse the existing AgentsHub types.
    static func node(for item: AgentTileItem) -> SubagentNode {
        SubagentNode(session: item.session, status: item.runStatus, children: [])
    }

    // MARK: Selection

    private static func findMain(sessions: [OpenClawChatSessionEntry], agentID: String) -> OpenClawChatSessionEntry {
        let mainKey: String = "agent:\(agentID):main"
        for session in sessions where session.key == mainKey {
            return session
        }
        for session in sessions where session.isMain == true {
            return session
        }
        return OpenClawChatSessionEntry(key: mainKey, agentId: agentID, isMain: true)
    }

    private static func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isSubagent(_ session: OpenClawChatSessionEntry) -> Bool {
        if session.isMain == true { return false }
        if hasText(session.spawnedBy) { return true }
        if hasText(session.parentSessionKey) { return true }
        if hasText(session.subagentRole) { return true }
        return session.key.contains(":subagent:")
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

    /// Non-active subagents older than `retention` (or without any timestamp) are hidden.
    private static func isOutdated(_ session: OpenClawChatSessionEntry, now: Date) -> Bool {
        let status: AgentsHubRunStatus = AgentsHubRunStatus(session)
        if status.isActive { return false }
        guard let reference = referenceDate(session) else { return true }
        return now.timeIntervalSince(reference) > retention
    }

    // MARK: Item

    private static func makeItem(_ session: OpenClawChatSessionEntry, isMain: Bool, now: Date) -> AgentTileItem {
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
        let name: String = isMain ? String(localized: "Main") : AgentTileNaming.name(for: session.key)
        let sprite: AgentTileSpriteKind = isMain ? .robot : AgentTileNaming.sprite(for: session.key)
        return AgentTileItem(
            session: session,
            isMain: isMain,
            name: name,
            sprite: sprite,
            runStatus: status,
            state: state,
            toolLine: tool,
            startDate: runningStart,
            elapsed: elapsed(session, status: status, start: start, now: now),
            progress: progress,
            recency: (start ?? reference)?.timeIntervalSince1970 ?? 0)
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

    static func isOrderedBefore(_ lhs: AgentTileItem, _ rhs: AgentTileItem) -> Bool {
        let left: Int = rank(lhs)
        let right: Int = rank(rhs)
        if left != right { return left < right }
        if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
        return lhs.id < rhs.id
    }
}
