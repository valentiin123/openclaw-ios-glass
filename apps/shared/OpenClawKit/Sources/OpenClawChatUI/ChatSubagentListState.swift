import Foundation

/// Remembers, for the lifetime of the app process, which subagent lists the person tucked away.
/// Keyed by chat session key so a list stays tucked while navigating between chats.
/// Thread-safe and nonisolated: it is read from view initializers.
public final class OpenClawChatSubagentListState: @unchecked Sendable {
    public static let shared: OpenClawChatSubagentListState = OpenClawChatSubagentListState()

    private let lock: NSLock = NSLock()
    private var collapsedKeys: Set<String> = []

    public init() {}

    public func isCollapsed(_ key: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.collapsedKeys.contains(key)
    }

    public func setCollapsed(_ collapsed: Bool, for key: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if collapsed {
            self.collapsedKeys.insert(key)
        } else {
            self.collapsedKeys.remove(key)
        }
    }
}
