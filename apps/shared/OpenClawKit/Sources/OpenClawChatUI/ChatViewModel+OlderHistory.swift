import Foundation
import OpenClawKit

/// Backward paging over `chat.history`. `offset` counts messages back from the newest row, so each
/// older page starts where the previous page's `nextOffset` stopped.
struct ChatOlderHistoryPaging {
    /// A light first page paints quickly and decodes cheaply on a weak link.
    static let initialPageLimit = 60
    static let slowLinkInitialPageLimit = 30
    static let slowPageLimit = 40
    static let mediumPageLimit = 80
    static let fastPageLimit = 150
    /// Round trips under `fastRoundTrip` justify bigger pages; above `slowRoundTrip` pages shrink.
    static let fastRoundTrip: TimeInterval = 1.0
    static let slowRoundTrip: TimeInterval = 3.0
    /// Pages made only of rows already on screen (the transcript grew since the cursor was set) are skipped.
    static let maxSkippedPages = 6
    static let retryDelay: TimeInterval = 3.0

    var nextOffset: Int?
    var hasMore = false
    /// Rows above the refreshed tail page stay put once paging is active.
    var retainsLoadedRows = false
    var lastRoundTrip: TimeInterval?
    var retryNotBefore: Date?
    /// Bumped on every reset so an in-flight load can tell it was retired.
    var generation: UInt64 = 0
    var task: Task<Void, Never>?

    var firstPageLimit: Int {
        guard let lastRoundTrip, lastRoundTrip >= Self.slowRoundTrip else { return Self.initialPageLimit }
        return Self.slowLinkInitialPageLimit
    }

    var olderPageLimit: Int {
        guard let lastRoundTrip else { return Self.mediumPageLimit }
        if lastRoundTrip < Self.fastRoundTrip { return Self.fastPageLimit }
        return lastRoundTrip < Self.slowRoundTrip ? Self.mediumPageLimit : Self.slowPageLimit
    }
}

extension OpenClawChatViewModel {
    /// True when `loadOlderMessages()` can start: the Gateway reported older rows and nothing is loading.
    public var canLoadOlderMessages: Bool {
        self.hasMoreOlderMessages && !self.isLoadingOlderMessages &&
            !self.isTransportDetached && !self.usesWebConversation
    }

    /// Loads the next older page and prepends it. A call while a load is running, or before the Gateway
    /// reported older rows, returns nil. Awaiting the returned task means the rows are already in `messages`.
    @discardableResult
    public func loadOlderMessages() -> Task<Void, Never>? {
        guard self.canLoadOlderMessages, self.olderHistoryPaging.nextOffset != nil else { return nil }
        if let retryNotBefore = self.olderHistoryPaging.retryNotBefore, Date() < retryNotBefore { return nil }
        let session: SessionSnapshot = self.currentSessionSnapshot()
        let generation: UInt64 = self.olderHistoryPaging.generation
        self.isLoadingOlderMessages = true
        self.olderMessagesLoadFailed = false
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.performLoadOlderMessages(session: session, generation: generation)
        }
        self.olderHistoryPaging.task = task
        return task
    }

    /// Retires paging state owned by the current transcript. The measured round trip survives because
    /// it describes the connection, not the session.
    func resetOlderHistoryPaging() {
        self.olderHistoryPaging.task?.cancel()
        var next = ChatOlderHistoryPaging()
        next.generation = self.olderHistoryPaging.generation &+ 1
        next.lastRoundTrip = self.olderHistoryPaging.lastRoundTrip
        self.olderHistoryPaging = next
        if self.hasMoreOlderMessages { self.hasMoreOlderMessages = false }
        if self.isLoadingOlderMessages { self.isLoadingOlderMessages = false }
        if self.olderMessagesLoadFailed { self.olderMessagesLoadFailed = false }
    }

    /// First page of a bootstrap: light, and it carries the cursor for older pages. A transport without
    /// paging, or a Gateway that rejects the paging fields, keeps the single-page behavior.
    func requestFirstHistoryPage(
        sessionKey: String) async throws -> (payload: OpenClawChatHistoryPayload, page: OpenClawChatHistoryPage?)
    {
        let transport: any OpenClawChatTransport = self.transport
        let limit: Int = self.olderHistoryPaging.firstPageLimit
        let started = Date()
        do {
            if let page = try await transport.requestHistoryPage(sessionKey: sessionKey, limit: limit, offset: nil) {
                self.olderHistoryPaging.lastRoundTrip = Date().timeIntervalSince(started)
                return (page.payload, page)
            }
        } catch let error as GatewayResponseError where error.code == "INVALID_REQUEST" {
            chatUILogger.error("history paging rejected \(error.message, privacy: .public)")
        }
        let payload = try await transport.requestHistory(sessionKey: sessionKey)
        return (payload, nil)
    }

    /// Records the cursor of the bootstrap page, once that page was applied to the visible transcript.
    func adoptFirstHistoryPaging(_ page: OpenClawChatHistoryPage?, session: SessionSnapshot) {
        guard self.isCurrentSession(session), let page else { return }
        self.olderHistoryPaging.retainsLoadedRows = true
        let loadedCount: Int = page.payload.messages?.count ?? 0
        let reported: Int? = page.nextOffset ?? (page.hasMore && loadedCount > 0 ? loadedCount : nil)
        guard page.hasMore, let next = reported, next > 0 else {
            self.stopOlderPaging()
            return
        }
        self.olderHistoryPaging.nextOffset = next
        self.olderHistoryPaging.hasMore = true
        if !self.hasMoreOlderMessages { self.hasMoreOlderMessages = true }
    }

    /// A tail refresh replaces the visible page. Rows that were above that page (older pages the reader
    /// loaded, or rows that slid out of the tail) stay in place, but only while the refreshed page still
    /// overlaps what was on screen; otherwise the transcript changed underneath and the page wins.
    /// Also returns the idempotency keys of the retained older rows: they precede a row the Gateway just
    /// proved, so the transcript cache may keep them (it drops user rows whose key it cannot prove).
    func retainingLoadedOlderRows(
        in next: [OpenClawChatMessage],
        incoming: [OpenClawChatMessage]) -> (messages: [OpenClawChatMessage], retainedOlderKeys: Set<String>)
    {
        let unchanged: (messages: [OpenClawChatMessage], retainedOlderKeys: Set<String>) = (next, [])
        guard self.olderHistoryPaging.retainsLoadedRows, !incoming.isEmpty, self.messages.count > 1 else {
            return unchanged
        }
        var incomingKeys = Set<String>()
        for message in incoming {
            if let key = Self.messageIdentityKey(for: message) { incomingKeys.insert(key) }
        }
        guard !incomingKeys.isEmpty else { return unchanged }
        let firstOverlap: Int? = self.messages.firstIndex { message in
            guard let key = Self.messageIdentityKey(for: message) else { return false }
            return incomingKeys.contains(key)
        }
        guard let boundary = firstOverlap else {
            // The transcript grew past the refreshed page: nothing on screen overlaps it, so the page wins and
            // the rows between it and the old ones are no longer loaded. Restart the cursor right under the
            // page. It never moves forward, because an offset past the page would skip rows.
            let restartOffset: Int = min(self.olderHistoryPaging.nextOffset ?? incoming.count, incoming.count)
            self.olderHistoryPaging.nextOffset = restartOffset
            self.olderHistoryPaging.hasMore = true
            if !self.hasMoreOlderMessages { self.hasMoreOlderMessages = true }
            return unchanged
        }
        // The refreshed page can reach deeper than the cursor. Asking again for rows it already holds only
        // returns duplicates, so move the cursor under the page; it never moves back.
        if let cursor = self.olderHistoryPaging.nextOffset, cursor < incoming.count {
            self.olderHistoryPaging.nextOffset = incoming.count
        }
        guard boundary > 0 else { return unchanged }
        let nextIDs = Set(next.map(\.id))
        let localOnlyIDs: Set<UUID> = Set(self.outboxCommandIDsByMessageID.keys)
            .union(self.pendingLocalUserEchoMessageIDsByRunID.values)
        let older: [OpenClawChatMessage] = self.messages[..<boundary].filter { !nextIDs.contains($0.id) }
        guard !older.isEmpty else { return unchanged }
        let olderKeys: Set<String> = Set(older.compactMap { message -> String? in
            localOnlyIDs.contains(message.id) ? nil : message.idempotencyKey
        })
        return (Self.dedupeMessages(older + next), olderKeys)
    }

    private func isOlderLoadCurrent(session: SessionSnapshot, generation: UInt64) -> Bool {
        generation == self.olderHistoryPaging.generation && self.isCurrentSession(session)
    }

    private func stopOlderPaging() {
        self.olderHistoryPaging.nextOffset = nil
        self.olderHistoryPaging.hasMore = false
        if self.hasMoreOlderMessages { self.hasMoreOlderMessages = false }
    }

    private func rowsNotYetLoaded(in decoded: [OpenClawChatMessage]) -> [OpenClawChatMessage] {
        var identityKeys = Set<String>()
        var dedupeKeys = Set<String>()
        for message in self.messages {
            if let key = Self.messageIdentityKey(for: message) { identityKeys.insert(key) }
            if let key = Self.dedupeKey(for: message) { dedupeKeys.insert(key) }
        }
        return decoded.filter { message in
            if let key = Self.messageIdentityKey(for: message), identityKeys.contains(key) { return false }
            if let key = Self.dedupeKey(for: message), dedupeKeys.contains(key) { return false }
            return true
        }
    }

    private func performLoadOlderMessages(session: SessionSnapshot, generation: UInt64) async {
        defer {
            if generation == self.olderHistoryPaging.generation {
                self.olderHistoryPaging.task = nil
                if self.isLoadingOlderMessages { self.isLoadingOlderMessages = false }
            }
        }
        var skippedPages = 0
        while self.isOlderLoadCurrent(session: session, generation: generation),
              let offset = self.olderHistoryPaging.nextOffset
        {
            let limit: Int = self.olderHistoryPaging.olderPageLimit
            let started = Date()
            let fetched: OpenClawChatHistoryPage?
            do {
                fetched = try await self.transport.requestHistoryPage(
                    sessionKey: session.key,
                    limit: limit,
                    offset: offset)
            } catch {
                guard self.isOlderLoadCurrent(session: session, generation: generation) else { return }
                if !(error is CancellationError) {
                    self.olderHistoryPaging.retryNotBefore =
                        Date().addingTimeInterval(ChatOlderHistoryPaging.retryDelay)
                    self.olderMessagesLoadFailed = true
                    self.logDiagnostic(
                        "chat.ui older history failed offset=\(offset) error=\(error.localizedDescription)")
                }
                return
            }
            guard self.isOlderLoadCurrent(session: session, generation: generation) else { return }
            self.olderHistoryPaging.lastRoundTrip = Date().timeIntervalSince(started)
            guard let page = fetched else {
                self.stopOlderPaging()
                return
            }
            // A page from another session id would splice two transcripts together.
            if let current = self.sessionId, let incoming = page.payload.sessionId, current != incoming {
                self.resetOlderHistoryPaging()
                return
            }
            let decoded: [OpenClawChatMessage] = Self.decodeMessages(
                page.payload.messages ?? [],
                activity: page.payload.activity)
            let fresh: [OpenClawChatMessage] = self.rowsNotYetLoaded(in: decoded)
            let loadedCount: Int = page.payload.messages?.count ?? 0
            let next: Int? = page.nextOffset ?? (page.hasMore && loadedCount > 0 ? offset + loadedCount : nil)
            let hasMore: Bool = page.hasMore && (next ?? offset) > offset
            self.olderHistoryPaging.nextOffset = hasMore ? next : nil
            self.olderHistoryPaging.hasMore = hasMore
            if self.hasMoreOlderMessages != hasMore { self.hasMoreOlderMessages = hasMore }
            self.olderHistoryPaging.retryNotBefore = nil
            if self.olderMessagesLoadFailed { self.olderMessagesLoadFailed = false }
            if !fresh.isEmpty {
                self.olderHistoryPaging.retainsLoadedRows = true
                // Older rows do not move the live edge, so this deliberately leaves `timelineRevision` alone.
                self.messages = fresh + self.messages
                // The cached stream shape depends on the transcript tail; older rows can change it.
                self.displayedStreamingShapeCache = nil
                self.seedInputHistory(from: self.messages)
                return
            }
            guard hasMore else { return }
            skippedPages += 1
            if skippedPages >= ChatOlderHistoryPaging.maxSkippedPages { return }
        }
    }
}
