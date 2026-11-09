import Foundation

struct ChatStreamPacing {
    var interval = 0.15
    var pending: String?
    var scheduledID: UUID?

    /// Each flush parses and lays out the whole growing answer, so its cost rises with the text.
    /// Long answers publish less often; the word-by-word reveal still catches up inside its own window.
    func paceInterval(forTextByteCount byteCount: Int) -> TimeInterval {
        if byteCount < 1_500 { return self.interval }
        if byteCount < 5_000 { return self.interval + 0.1 }
        return self.interval + 0.2
    }
}

extension OpenClawChatViewModel {
    /// First output and clearing are immediate. Growing text waits for the default run-loop mode,
    /// which leaves touch tracking free to scroll rather than laying out every arriving word.
    func scheduleStreamingAssistantDisplay(_ text: String?) {
        guard let text, self.displayedStreamingAssistantTextUntracked != nil else {
            self.streamPacing.pending = nil
            self.streamPacing.scheduledID = nil
            self.applyStreamingAssistantDisplay(text)
            return
        }
        self.streamPacing.pending = text
        guard self.streamPacing.scheduledID == nil else { return }
        let scheduledID = UUID()
        self.streamPacing.scheduledID = scheduledID
        let delay: TimeInterval = self.streamPacing.paceInterval(forTextByteCount: text.utf8.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated { self?.flushStreamingAssistantDisplay(scheduledID: scheduledID) }
            }
        }
    }

    func flushStreamingAssistantDisplay(scheduledID: UUID) {
        // A clear/session switch retires the callback, even if another run starts before it fires.
        guard self.streamPacing.scheduledID == scheduledID else { return }
        self.streamPacing.scheduledID = nil
        guard let pending = self.streamPacing.pending else { return }
        self.streamPacing.pending = nil
        self.applyStreamingAssistantDisplay(pending)
    }

    /// Shape of the text on screen. The cached value is trusted only while both the text and the
    /// transcript revision are unchanged, because durable rows can suppress live words.
    func currentDisplayedStreamingShape() -> [Bool] {
        let displayed: String? = self.displayedStreamingAssistantTextUntracked
        if let cache = self.displayedStreamingShapeCache,
           cache.text == displayed,
           cache.revision == self.timelineRevision
        {
            return cache.shape
        }
        return self.streamingTextShape(displayed)
    }
}
