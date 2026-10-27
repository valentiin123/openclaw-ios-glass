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

// MARK: - Empty state

/// Copy and sprite of the Agents board empty state (no root conversation and no subagent to show).
/// Computed properties so the strings resolve at display time, in the current locale.
enum AgentTileEmptyContent {
    static var sprite: AgentTileSpriteKind {
        .ghost
    }

    static var title: String {
        String(localized: "Nothing here yet")
    }

    static var message: String {
        String(localized: "Start a conversation with this agent. Its subagents will show up here too.")
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

// MARK: - Assignments (persisted)

/// Name and sprite given to one session key. Persisted so a tile never changes identity.
struct AgentTileAssignment: Codable, Equatable, Sendable {
    var name: String
    /// Raw value of `AgentTileSpriteKind`.
    var sprite: Int
    /// First time the key was assigned (older keys keep their name when two collide).
    var created: Double
    /// Last time the key was displayed (drives the cleanup of vanished keys).
    var seen: Double
}

/// Shared store of `sessionKey -> name / sprite`, backed by UserDefaults. Used by the board tiles,
/// the subagent chat header and the tree screen so they always agree.
/// Thread safety: every access goes through `lock` (no actor hop, callable from any context).
final class AgentTileAssignmentStore: @unchecked Sendable {
    static let shared: AgentTileAssignmentStore = AgentTileAssignmentStore()

    static let defaultsKey: String = "agentsHub.tileAssignments.v1"
    /// Hard bound on the persisted dictionary.
    static let maxEntries: Int = 300
    /// A key not displayed for this long is forgotten.
    static let expiry: TimeInterval = 3 * 24 * 3600
    /// Every sprite except the reserved robot.
    static let spritePool: [Int] = AgentTileAssignmentStore.makeSpritePool()

    private static let touchInterval: TimeInterval = 3600
    private static let recentWindow: TimeInterval = 6 * 3600

    private let lock: NSLock = NSLock()
    private let defaults: UserDefaults
    private var entries: [String: AgentTileAssignment] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = AgentTileAssignmentStore.load(from: defaults)
    }

    /// Unique names and sprites for the tiles displayed together. Older keys keep their identity;
    /// a new key probes linearly from its hashed slot to the next free name / sprite.
    /// `reservedNames` (lowercased) are titles already shown by other tiles: pool names avoid them.
    func assignments(
        for keys: [String],
        reservedNames: Set<String> = [],
        now: Date) -> [String: AgentTileAssignment]
    {
        self.lock.lock()
        defer { self.lock.unlock() }
        let stamp: Double = now.timeIntervalSince1970
        let ordered: [String] = Self.creationOrder(keys, entries: self.entries)
        var usedNames: Set<String> = reservedNames
        var usedSprites: Set<Int> = []
        var result: [String: AgentTileAssignment] = [:]
        var changed: Bool = false
        for key in ordered {
            let previous: AgentTileAssignment? = self.entries[key]
            let spritesFull: Bool = usedSprites.count >= Self.spritePool.count
            let entry: AgentTileAssignment = Self.resolve(
                key: key,
                previous: previous,
                usedNames: usedNames,
                usedSprites: usedSprites,
                spritesFull: spritesFull,
                stamp: stamp)
            if entry != previous {
                self.entries[key] = entry
                changed = true
            }
            usedNames.insert(Self.fold(entry.name))
            usedSprites.insert(entry.sprite)
            result[key] = entry
        }
        let protected: Set<String> = Set<String>(ordered)
        if self.prune(now: stamp, protecting: protected) { changed = true }
        if changed { self.persist() }
        return result
    }

    /// Identity of a single key outside of a grid (chat header, tree). Avoids what was shown recently.
    func assignment(for key: String, now: Date) -> AgentTileAssignment {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let existing = self.entries[key], !existing.name.isEmpty, Self.isPoolSprite(existing.sprite) {
            return existing
        }
        let stamp: Double = now.timeIntervalSince1970
        let cutoff: Double = stamp - Self.recentWindow
        var usedNames: Set<String> = []
        var usedSprites: Set<Int> = []
        for (otherKey, other) in self.entries where otherKey != key && other.seen >= cutoff {
            usedNames.insert(Self.fold(other.name))
            usedSprites.insert(other.sprite)
        }
        let spritesFull: Bool = usedSprites.count >= Self.spritePool.count
        let entry: AgentTileAssignment = Self.resolve(
            key: key,
            previous: self.entries[key],
            usedNames: usedNames,
            usedSprites: usedSprites,
            spritesFull: spritesFull,
            stamp: stamp)
        self.entries[key] = entry
        let protected: Set<String> = [key]
        self.prune(now: stamp, protecting: protected)
        self.persist()
        return entry
    }

    // MARK: Resolution

    private struct OrderedKey {
        let key: String
        let created: Double

        static func isBefore(_ lhs: OrderedKey, _ rhs: OrderedKey) -> Bool {
            if lhs.created != rhs.created { return lhs.created < rhs.created }
            return lhs.key < rhs.key
        }
    }

    private struct PruneCandidate {
        let key: String
        let seen: Double

        static func isOlder(_ lhs: PruneCandidate, _ rhs: PruneCandidate) -> Bool {
            if lhs.seen != rhs.seen { return lhs.seen < rhs.seen }
            return lhs.key < rhs.key
        }
    }

    /// Known keys first (oldest assignment first), then new keys sorted by key. Duplicates removed.
    private static func creationOrder(_ keys: [String], entries: [String: AgentTileAssignment]) -> [String] {
        var seenKeys: Set<String> = []
        var known: [OrderedKey] = []
        var fresh: [String] = []
        for key in keys {
            if seenKeys.contains(key) { continue }
            seenKeys.insert(key)
            if let entry = entries[key] {
                known.append(OrderedKey(key: key, created: entry.created))
            } else {
                fresh.append(key)
            }
        }
        known.sort(by: OrderedKey.isBefore)
        fresh.sort()
        var ordered: [String] = []
        for item in known { ordered.append(item.key) }
        ordered.append(contentsOf: fresh)
        return ordered
    }

    private static func resolve(
        key: String,
        previous: AgentTileAssignment?,
        usedNames: Set<String>,
        usedSprites: Set<Int>,
        spritesFull: Bool,
        stamp: Double) -> AgentTileAssignment
    {
        var name: String = ""
        var sprite: Int = -1
        var created: Double = stamp
        var seen: Double = stamp
        if let previous {
            created = previous.created
            seen = previous.seen
            if stamp - previous.seen > touchInterval { seen = stamp }
            if !previous.name.isEmpty, !usedNames.contains(fold(previous.name)) {
                name = previous.name
            }
            let spriteFree: Bool = spritesFull || !usedSprites.contains(previous.sprite)
            if isPoolSprite(previous.sprite), spriteFree {
                sprite = previous.sprite
            }
        }
        if name.isEmpty { name = freeName(for: key, used: usedNames) }
        if sprite < 0 { sprite = freeSprite(for: key, used: usedSprites) }
        return AgentTileAssignment(name: name, sprite: sprite, created: created, seen: seen)
    }

    /// Linear probe from the hashed slot; numeric suffix ("Pixel 2") once the whole pool is taken.
    private static func freeName(for key: String, used: Set<String>) -> String {
        let pool: [String] = AgentTileNaming.names
        let count: Int = pool.count
        let start: Int = Int((AgentTileNaming.hash(key) >> 11) % UInt64(count))
        for offset in 0..<count {
            let candidate: String = pool[(start + offset) % count]
            if !used.contains(fold(candidate)) { return candidate }
        }
        let base: String = pool[start]
        var suffix: Int = 2
        while true {
            let candidate: String = "\(base) \(suffix)"
            if !used.contains(fold(candidate)) { return candidate }
            suffix += 1
        }
    }

    /// Linear probe over the sprite pool; reuse (hashed slot) once every sprite is taken.
    private static func freeSprite(for key: String, used: Set<Int>) -> Int {
        let pool: [Int] = spritePool
        let count: Int = pool.count
        let start: Int = Int((AgentTileNaming.hash(key) >> 29) % UInt64(count))
        for offset in 0..<count {
            let candidate: Int = pool[(start + offset) % count]
            if !used.contains(candidate) { return candidate }
        }
        return pool[start]
    }

    private static func makeSpritePool() -> [Int] {
        var pool: [Int] = []
        for kind in AgentTileSpriteKind.allCases where kind != .robot {
            pool.append(kind.rawValue)
        }
        return pool
    }

    private static func isPoolSprite(_ raw: Int) -> Bool {
        spritePool.contains(raw)
    }

    static func fold(_ text: String) -> String {
        text.lowercased()
    }

    // MARK: Persistence

    private static func load(from defaults: UserDefaults) -> [String: AgentTileAssignment] {
        guard let data: Data = defaults.data(forKey: defaultsKey) else { return [:] }
        let decoded: [String: AgentTileAssignment]? = try? JSONDecoder().decode(
            [String: AgentTileAssignment].self,
            from: data)
        return decoded ?? [:]
    }

    private func persist() {
        guard let data: Data = try? JSONEncoder().encode(self.entries) else { return }
        self.defaults.set(data, forKey: Self.defaultsKey)
    }

    /// Drops expired keys, then the oldest ones above `maxEntries`. Keys in `protecting` are kept.
    @discardableResult
    private func prune(now: Double, protecting: Set<String>) -> Bool {
        var changed: Bool = false
        let cutoff: Double = now - Self.expiry
        var stale: [String] = []
        for (key, entry) in self.entries where entry.seen < cutoff && !protecting.contains(key) {
            stale.append(key)
        }
        for key in stale {
            self.entries[key] = nil
            changed = true
        }
        let excess: Int = self.entries.count - Self.maxEntries
        if excess > 0 {
            var candidates: [PruneCandidate] = []
            for (key, entry) in self.entries where !protecting.contains(key) {
                candidates.append(PruneCandidate(key: key, seen: entry.seen))
            }
            candidates.sort(by: PruneCandidate.isOlder)
            for candidate in candidates.prefix(excess) {
                self.entries[candidate.key] = nil
                changed = true
            }
        }
        return changed
    }
}

// MARK: - Naming (deterministic, unique, persisted)

enum AgentTileNaming {
    /// Short, easy to read names. Must stay free of duplicates (case-insensitive).
    static let names: [String] = [
        "Pixel", "Mochi", "Nova", "Pip", "Bean", "Zed", "Echo", "Juno",
        "Kiwi", "Orbit", "Blip", "Cosmo", "Dot", "Fizz", "Gizmo", "Haze",
        "Ziggy", "Lumi", "Miso", "Nimbus", "Otto", "Pogo", "Quill", "Riff",
        "Sprout", "Taco", "Ume", "Vex", "Wisp", "Yuzu", "Zap", "Ash",
        "Bolt", "Cleo", "Dash", "Ember", "Fern", "Gus", "Hugo", "Ivy",
        "Jazz", "Koko", "Luna", "Moss", "Nori", "Olive", "Peep", "Rune",
        "Ace", "Bao", "Cory", "Dex", "Elm", "Finn", "Gigi", "Hana",
        "Indy", "Jet", "Kai", "Lola", "Milo", "Nix", "Oak", "Pearl",
        "Remy", "Sage", "Tofu", "Uma", "Vito", "Wren", "Xan", "Yara",
        "Zuzu", "Basil", "Cocoa", "Dune", "Elio", "Flint", "Goji", "Hazel",
        "Iris", "Jade", "Kit", "Lark", "Maple", "Nico", "Opal", "Pico",
        "Quip", "Rio", "Sunny", "Tango", "Umber", "Vale", "Waffle", "Yoyo",
        "Zest", "Alba", "Bruno", "Cinder", "Fable", "Gem", "Honey", "Inky",
        "Jolly", "Kelp", "Lemon", "Mango", "Nugget", "Onyx", "Poppy", "Quartz",
        "Rusty", "Sky", "Toast", "Uno", "Velvet", "Willow", "Yam", "Zen",
        "Pebble", "Clover", "Biscuit", "Comet", "Dingo", "Ripple", "Tulip", "Marble",
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

    /// Sprite of a session. Reads (and creates if needed) the shared persisted assignment.
    static func sprite(for key: String) -> AgentTileSpriteKind {
        let assignment: AgentTileAssignment = AgentTileAssignmentStore.shared.assignment(for: key, now: Date())
        return AgentTileSpriteKind(rawValue: assignment.sprite) ?? .ghost
    }

    /// Name of a session. Reads (and creates if needed) the shared persisted assignment.
    static func name(for key: String) -> String {
        AgentTileAssignmentStore.shared.assignment(for: key, now: Date()).name
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
    /// (active first, then the most recent). Outdated subagents are dropped. Roots and subagents are
    /// never interleaved. Names and sprites come from the persisted assignment store and every displayed
    /// name is unique (case-insensitive).
    static func items(
        sessions: [OpenClawChatSessionEntry],
        agentID: String,
        now: Date,
        pinned: Set<String> = []) -> [AgentTileItem]
    {
        var byKey: [String: OpenClawChatSessionEntry] = [:]
        for session in sessions {
            byKey[session.key] = session
        }
        var seenKeys: Set<String> = []
        var rootSessions: [OpenClawChatSessionEntry] = []
        var subSessions: [OpenClawChatSessionEntry] = []
        for session in sessions {
            if seenKeys.contains(session.key) { continue }
            if isRootConversation(session) {
                seenKeys.insert(session.key)
                rootSessions.append(session)
                continue
            }
            if !isSubagent(session) { continue }
            if isFromExternalParent(session, in: byKey) { continue }
            if !pinned.contains(session.key), isOutdated(session, now: now) { continue }
            seenKeys.insert(session.key)
            subSessions.append(session)
        }

        var keys: [String] = []
        var titleNames: Set<String> = []
        for session in rootSessions {
            keys.append(session.key)
            if let title = readableTitle(session) {
                titleNames.insert(title.lowercased())
            }
        }
        for session in subSessions {
            keys.append(session.key)
        }
        let assigned: [String: AgentTileAssignment] = AgentTileAssignmentStore.shared.assignments(
            for: keys,
            reservedNames: titleNames,
            now: now)
        let names: [String: String] = uniqueNames(roots: rootSessions, subs: subSessions, assigned: assigned)

        var roots: [AgentTileItem] = []
        for session in rootSessions {
            let name: String = names[session.key] ?? AgentTileNaming.name(for: session.key)
            let sprite: AgentTileSpriteKind = resolvedSprite(assigned[session.key], key: session.key)
            let rootItem: AgentTileItem = makeItem(
                session, isMain: true, name: name, sprite: sprite, parentName: nil, now: now)
            roots.append(rootItem)
        }
        var subagents: [AgentTileItem] = []
        for session in subSessions {
            let name: String = names[session.key] ?? AgentTileNaming.name(for: session.key)
            let sprite: AgentTileSpriteKind = resolvedSprite(assigned[session.key], key: session.key)
            let parent: String? = parentName(of: session, in: byKey, names: names)
            let subItem: AgentTileItem = makeItem(
                session, isMain: false, name: name, sprite: sprite, parentName: parent, now: now)
            subagents.append(subItem)
        }
        roots.sort(by: AgentTileFactory.isRootOrderedBefore)
        subagents.sort(by: AgentTileFactory.isOrderedBefore)
        var result: [AgentTileItem] = roots
        result.append(contentsOf: subagents)
        return result
    }

    // MARK: Unique names

    private static func isKeyOrderedBefore(_ lhs: OpenClawChatSessionEntry, _ rhs: OpenClawChatSessionEntry) -> Bool {
        lhs.key < rhs.key
    }

    private static func resolvedSprite(_ assignment: AgentTileAssignment?, key: String) -> AgentTileSpriteKind {
        if let assignment, let kind = AgentTileSpriteKind(rawValue: assignment.sprite) { return kind }
        return AgentTileNaming.sprite(for: key)
    }

    /// Readable title for a root conversation, otherwise the persisted pool name.
    private static func baseName(
        for session: OpenClawChatSessionEntry,
        assigned: [String: AgentTileAssignment]) -> String
    {
        if let title = readableTitle(session) { return title }
        if let assignment = assigned[session.key], !assignment.name.isEmpty { return assignment.name }
        return AgentTileNaming.name(for: session.key)
    }

    /// First free spelling of `base` ("Name", "Name 2", "Name 3"...). Case-insensitive.
    private static func uniqueName(_ base: String, taken: inout Set<String>) -> String {
        var candidate: String = base
        var suffix: Int = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }

    /// One unique display name per displayed session. Claimed in a stable order (roots, then subagents,
    /// each by session key) so a refresh never swaps two names.
    private static func uniqueNames(
        roots: [OpenClawChatSessionEntry],
        subs: [OpenClawChatSessionEntry],
        assigned: [String: AgentTileAssignment]) -> [String: String]
    {
        var ordered: [OpenClawChatSessionEntry] = []
        ordered.append(contentsOf: roots.sorted(by: AgentTileFactory.isKeyOrderedBefore))
        ordered.append(contentsOf: subs.sorted(by: AgentTileFactory.isKeyOrderedBefore))
        var taken: Set<String> = []
        var result: [String: String] = [:]
        for session in ordered {
            let base: String = baseName(for: session, assigned: assigned)
            result[session.key] = uniqueName(base, taken: &taken)
        }
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
        let sprite: AgentTileSpriteKind = spriteKind(for: session)
        return makeItem(session, isMain: isMain, name: name, sprite: sprite, parentName: nil, now: now)
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
        if session.key.contains(":subagent:") { return true }
        if hasText(session.subagentRole) { return true }
        if let depth = session.spawnDepth, depth >= 1 { return true }
        if hasText(session.spawnedBy) { return true }
        // The gateway stamps chats started from the app with `parentSessionKey = agent:<id>:main` and
        // `spawnDepth = 0`: those are the user's own conversations, never subagents.
        if hasText(session.parentSessionKey) {
            if let depth = session.spawnDepth, depth < 1 { return false }
            return true
        }
        return false
    }

    /// A conversation started directly by the user in this agent: not the system chat, not spawned by
    /// another session, not a background / heartbeat run.
    static func isRootConversation(_ session: OpenClawChatSessionEntry) -> Bool {
        if isSystemMain(session) { return false }
        if isSubagent(session) { return false }
        if session.isBackground == true { return false }
        if session.classification == "heartbeat" { return false }
        if isExternalChannel(session) { return false }
        return true
    }

    // MARK: External channels

    /// Messaging channels whose conversations are hidden from the board (they live in those apps).
    private static let externalChannels: Set<String> = [
        "telegram", "whatsapp", "discord", "slack", "signal", "imessage", "bluebubbles",
        "matrix", "msteams", "googlechat", "mattermost", "irc", "email", "sms", "line",
        "feishu", "wechat", "zalo", "twitch", "nostr", "tlon", "nextcloud-talk",
    ]

    private static let peerRouteKinds: Set<String> = ["direct", "dm", "group", "channel", "thread"]

    /// Channel segment of a peer route key `agent:<id>:<channel>[:<account>]:(direct|dm|group|channel|thread):<peer>`.
    /// Nil for in-app keys (`agent:<id>:ios-<uuid>`, `agent:<id>:main`, `...:subagent:...`).
    private static func channelFromKey(_ key: String) -> String? {
        let parts: [Substring] = key.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count < 5 { return nil }
        if parts[0].lowercased() != "agent" { return nil }
        let kindA: String = parts[3].lowercased()
        let kindB: String = parts[4].lowercased()
        let isPeerRoute: Bool = peerRouteKinds.contains(kindA) || peerRouteKinds.contains(kindB)
        if !isPeerRoute { return nil }
        let channel: String = parts[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if channel.isEmpty { return nil }
        return channel
    }

    private static func isExternalName(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let name: String = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.isEmpty { return false }
        return externalChannels.contains(name)
    }

    /// True when the conversation comes from an external messaging channel. Criteria, any of:
    /// 1. `session.channel` is a known external channel (Telegram, WhatsApp, Discord, Slack, Signal, ...);
    /// 2. `session.deliveryContext["channel"]` is a known external channel;
    /// 3. the session key is a peer route (`agent:<id>:<channel>:direct|dm|group|channel|thread:<peer>`)
    ///    whose channel segment is NOT an in-app one (`ios`, `webchat`, `dashboard`, `openclaw-*`).
    /// In-app conversations (`agent:<id>:ios-<uuid>`, webchat, dashboard) never match.
    static func isExternalChannel(_ session: OpenClawChatSessionEntry) -> Bool {
        if isExternalName(session.channel) { return true }
        if let context = session.deliveryContext, let value = context["channel"]?.value as? String {
            if isExternalName(value) { return true }
        }
        guard let routeChannel = channelFromKey(session.key) else { return false }
        if externalChannels.contains(routeChannel) { return true }
        let inApp: Set<String> = ["ios", "webchat", "dashboard", "web", "app", "internal", "main", "subagent", "cron"]
        if inApp.contains(routeChannel) { return false }
        return !routeChannel.hasPrefix("openclaw")
    }

    /// A subagent spawned (directly) by an external channel conversation is hidden with it. Only the route of
    /// the parent session or of the subagent key decides: the delivery metadata of the system chat is not used,
    /// because it can point to a messaging channel without making its subagents external.
    private static func isFromExternalParent(
        _ session: OpenClawChatSessionEntry,
        in byKey: [String: OpenClawChatSessionEntry]) -> Bool
    {
        if let own = channelFromKey(session.key), externalChannels.contains(own) { return true }
        var parentKey: String?
        if hasText(session.spawnedBy) {
            parentKey = session.spawnedBy
        } else if hasText(session.parentSessionKey) {
            parentKey = session.parentSessionKey
        }
        guard let parentKey, let parent = byKey[parentKey] else { return false }
        if isSystemMain(parent) { return false }
        return isExternalChannel(parent)
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
        in byKey: [String: OpenClawChatSessionEntry],
        names: [String: String]) -> String?
    {
        var parentKey: String?
        if hasText(session.spawnedBy) {
            parentKey = session.spawnedBy
        } else if hasText(session.parentSessionKey) {
            parentKey = session.parentSessionKey
        }
        guard let parentKey, let parent = byKey[parentKey] else { return nil }
        if isSystemMain(parent) { return nil }
        if let shown = names[parent.key] { return shown }
        if isRootConversation(parent) { return displayName(for: parent) }
        return AgentTileNaming.name(for: parent.key)
    }

    // MARK: Item

    private static func makeItem(
        _ session: OpenClawChatSessionEntry,
        isMain: Bool,
        name: String,
        sprite: AgentTileSpriteKind,
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

    /// 0 = run in progress (including stuck / waiting on the user), 1 = finished (done, failed, idle, napping).
    /// Based on the real run status as well as the tile state, so an active run never sinks below a finished one.
    private static func rank(_ item: AgentTileItem) -> Int {
        if item.runStatus.isActive { return 0 }
        if item.state.isActive { return 0 }
        return 1
    }

    /// Subagents: active or in progress first, finished last; most recent first inside each group.
    /// Root conversations never go through this comparator, they are listed before every subagent.
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

// MARK: - Pinned subagents

/// Subagents the user pinned (long press): they stay on the board after the 30 minute retention.
enum AgentPinStore {
    static let defaultsKey: String = "agentsHub.pinnedSubagents.v1"

    static func load() -> Set<String> {
        let stored: [String] = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return Set<String>(stored)
    }

    static func save(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys).sorted(), forKey: defaultsKey)
    }
}


// MARK: - Pinned subagents

/// Subagents the user pinned with a long press: they stay on the board after the 30 minute window.
/// Persisted in UserDefaults, bounded.
final class AgentTilePinStore: @unchecked Sendable {
    static let shared: AgentTilePinStore = AgentTilePinStore()
    static let defaultsKey: String = "agentsHub.pinnedSubagents.v1"
    private static let maxEntries: Int = 200

    private let lock: NSLock = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func keys() -> Set<String> {
        self.lock.lock()
        defer { self.lock.unlock() }
        let stored: [String] = self.defaults.stringArray(forKey: Self.defaultsKey) ?? []
        return Set<String>(stored)
    }

    /// Returns the new pinned state of `key`.
    @discardableResult
    func toggle(_ key: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        var stored: [String] = self.defaults.stringArray(forKey: Self.defaultsKey) ?? []
        if let index = stored.firstIndex(of: key) {
            stored.remove(at: index)
            self.defaults.set(stored, forKey: Self.defaultsKey)
            return false
        }
        stored.append(key)
        if stored.count > Self.maxEntries {
            stored.removeFirst(stored.count - Self.maxEntries)
        }
        self.defaults.set(stored, forKey: Self.defaultsKey)
        return true
    }
}
