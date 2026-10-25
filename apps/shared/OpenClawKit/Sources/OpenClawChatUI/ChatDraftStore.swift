import Foundation

/// Local, per-session persistence of the unsent composer text.
///
/// Keys are the composer session keys (`OpenClawChatViewModel.composerSessionKey(for:)`), which already
/// combine agent and session key. Only text is stored; attachments stay in memory (see the view model).
/// The store is a thin wrapper over `UserDefaults`: one JSON blob, capped in entry count and length so
/// it cannot grow without bound. An empty or whitespace-only draft removes its entry.
struct ChatDraftStore {
    private struct Entry: Codable {
        var text: String
        var updatedAt: Date
    }

    static let defaultsKey: String = "openclaw.chat.drafts.v1"
    static let maxEntries: Int = 100
    static let maxCharacters: Int = 20000

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func draft(for key: String) -> String? {
        let entries: [String: Entry] = self.load()
        guard let entry = entries[key], !Self.isBlank(entry.text) else { return nil }
        return entry.text
    }

    func save(_ text: String, for key: String) {
        guard !key.isEmpty else { return }
        var entries: [String: Entry] = self.load()
        if Self.isBlank(text) {
            guard entries.removeValue(forKey: key) != nil else { return }
            self.store(entries)
            return
        }
        let clipped: String = String(text.prefix(Self.maxCharacters))
        if let existing = entries[key], existing.text == clipped { return }
        entries[key] = Entry(text: clipped, updatedAt: Date())
        self.store(Self.trimmed(entries))
    }

    func remove(for key: String) {
        var entries: [String: Entry] = self.load()
        guard entries.removeValue(forKey: key) != nil else { return }
        self.store(entries)
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Keeps the most recently edited drafts when the cap is exceeded.
    private static func trimmed(_ entries: [String: Entry]) -> [String: Entry] {
        guard entries.count > Self.maxEntries else { return entries }
        let newestFirst: [(key: String, value: Entry)] = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }
        var kept: [String: Entry] = [:]
        for pair in newestFirst.prefix(Self.maxEntries) {
            kept[pair.key] = pair.value
        }
        return kept
    }

    private func load() -> [String: Entry] {
        guard let data = self.defaults.data(forKey: Self.defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func store(_ entries: [String: Entry]) {
        if entries.isEmpty {
            self.defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        self.defaults.set(data, forKey: Self.defaultsKey)
    }
}
