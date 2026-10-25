import Foundation

/// Persistent, per-session composer drafts (text only).
///
/// The draft key is `composerSessionKey(for:)`, i.e. agent + session key. Every change to `input`
/// schedules a debounced save; a change of key, `flushDraftPersistence()` (scene to background, view
/// disappearing) or a send (input becomes empty) settles it immediately. Session switches and
/// `load()` restore the stored text into an empty composer, so a draft survives switching sessions,
/// closing the chat and relaunching the app. Attachments stay in memory only.
extension OpenClawChatViewModel {
    private enum DraftTiming {
        static let debounce: Duration = .milliseconds(400)
    }

    /// Stored draft for a session, or nil. `sessionKey` is resolved like the live composer key.
    public func persistedDraft(forSession sessionKey: String) -> String? {
        self.draftStore.draft(for: self.composerSessionKey(for: sessionKey))
    }

    /// Stores (or, for blank text, removes) the draft of a session.
    public func savePersistedDraft(_ text: String, forSession sessionKey: String) {
        self.draftStore.save(text, for: self.composerSessionKey(for: sessionKey))
    }

    /// Removes the stored draft of a session.
    public func clearPersistedDraft(forSession sessionKey: String) {
        let key: String = self.composerSessionKey(for: sessionKey)
        if self.pendingDraftWrite?.key == key {
            self.pendingDraftWrite = nil
        }
        self.draftStore.remove(for: key)
    }

    /// Writes any debounced draft now. Call when the chat goes away or the app leaves the foreground.
    public func flushDraftPersistence() {
        self.draftSaveTask?.cancel()
        self.draftSaveTask = nil
        guard let pending = self.pendingDraftWrite else { return }
        self.pendingDraftWrite = nil
        self.draftStore.save(pending.text, for: pending.key)
    }

    func scheduleDraftPersistence() {
        // Restores and recalls go through `isApplyingRecalledInput`; they must not erase the stored draft.
        guard !self.isApplyingRecalledInput else { return }
        let key: String = self.composerSessionKey(for: self.sessionKey)
        if let pending = self.pendingDraftWrite, pending.key != key {
            self.flushDraftPersistence()
        }
        self.pendingDraftWrite = PendingDraftWrite(key: key, text: self.input)
        self.draftSaveTask?.cancel()
        self.draftSaveTask = Task { [weak self] in
            guard await (try? Task.sleep(for: DraftTiming.debounce)) != nil else { return }
            self?.flushDraftPersistence()
        }
    }

    /// Fills an empty composer with the stored draft of the current session. Never overwrites typed text.
    func restorePersistedDraftIfNeeded() {
        // Settle a debounced write first so a just-sent (cleared) draft is not resurrected from the store.
        self.flushDraftPersistence()
        guard self.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let key: String = self.composerSessionKey(for: self.sessionKey)
        guard let stored = self.draftStore.draft(for: key) else { return }
        self.isApplyingRecalledInput = true
        self.input = stored
        self.isApplyingRecalledInput = false
        self.draftsBySession[key] = stored
    }
}

struct PendingDraftWrite {
    let key: String
    let text: String
}
