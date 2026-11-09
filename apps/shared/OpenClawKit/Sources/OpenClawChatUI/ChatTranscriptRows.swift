import Foundation

enum ChatTranscriptRow: Hashable, Identifiable {
    enum SystemNoticeKind: Hashable {
        case restartRecovery
        case gatewayRestarted
        case injectedContext
        case backgroundTask
        case generic
    }

    struct SystemNotice: Hashable {
        let id: UUID
        let kind: SystemNoticeKind
        let body: String
        let timestamp: Double?

        var label: String {
            switch self.kind {
            case .restartRecovery:
                String(localized: "System · restart recovery")
            case .gatewayRestarted:
                String(localized: "System · gateway restarted")
            case .injectedContext:
                String(localized: "System · injected context")
            case .backgroundTask:
                String(localized: "System · background task")
            case .generic:
                String(localized: "System")
            }
        }

        var systemImage: String {
            "cpu"
        }

        /// Bulky harness payloads (continuation summaries, task output) open on demand, as in the Control UI.
        var collapsesBody: Bool {
            self.kind == .injectedContext || self.kind == .backgroundTask
        }
    }

    enum HistoryDividerKind: Hashable {
        case compaction
        case reset
    }

    struct HistoryDivider: Hashable {
        let id: UUID
        let kind: HistoryDividerKind
        let savedTokens: Double?
        let timestamp: Double?

        var label: String {
            switch self.kind {
            case .compaction:
                String(localized: "Compacted history")
            case .reset:
                String(localized: "Session reset")
            }
        }

        var metric: String? {
            guard self.kind == .compaction, let savedTokens else { return nil }
            return String(
                format: String(localized: "saved %@ tokens"),
                ChatCompactTokenCountFormatter.string(savedTokens))
        }

        var description: String? {
            switch self.kind {
            case .compaction:
                nil
            case .reset:
                String(localized: "The earlier conversation was cleared.")
            }
        }

        var systemImage: String {
            switch self.kind {
            case .compaction:
                "rectangle.compress.vertical"
            case .reset:
                "arrow.counterclockwise"
            }
        }
    }

    case message(OpenClawChatMessage)
    case systemNotice(SystemNotice)
    case historyDivider(HistoryDivider)
    case completedWork(CompletedWork)

    var id: UUID {
        switch self {
        case let .message(message): message.id
        case let .systemNotice(notice): notice.id
        case let .historyDivider(divider): divider.id
        case let .completedWork(work): work.id
        }
    }

    var timestamp: Double? {
        switch self {
        case let .message(message): message.timestamp
        case let .systemNotice(notice): notice.timestamp
        case let .historyDivider(divider): divider.timestamp
        case .completedWork: nil
        }
    }

    var startsTurn: Bool {
        switch self {
        case let .message(message):
            message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "user" ||
                message.turnBoundary == true || message.isForwardedTurnBoundary
        case .systemNotice:
            true
        case .historyDivider, .completedWork:
            false
        }
    }

    init?(_ message: OpenClawChatMessage) {
        let role = message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if role == "system", let marker = message.historyMarker {
            switch marker.kind {
            case "compaction":
                let savedTokens = Self.savedTokens(for: marker)
                self = .historyDivider(HistoryDivider(
                    id: message.id,
                    kind: .compaction,
                    savedTokens: savedTokens,
                    timestamp: message.timestamp))
            case "reset":
                self = .historyDivider(HistoryDivider(
                    id: message.id,
                    kind: .reset,
                    savedTokens: nil,
                    timestamp: message.timestamp))
            default:
                return nil
            }
            return
        }

        if role == "user", message.provenance?.kind == "internal_system" {
            let kind: SystemNoticeKind
            let body: String
            switch message.provenance?.sourceTool {
            case "main_session_restart_recovery":
                kind = .restartRecovery
                body =
                    String(
                        localized: """
                        Turn interrupted by a gateway restart — asked the agent to resume and finish the response.
                        """)
            case "restart-sentinel":
                kind = .gatewayRestarted
                body = Self.strippingSystemPrefix(from: ChatMessageVisibleText.visibleText(in: message))
            case "cli_harness_context":
                kind = .injectedContext
                body = Self.strippingSystemPrefix(from: ChatMessageVisibleText.visibleText(in: message))
            case "claude_cli_task_notification":
                kind = .backgroundTask
                body = Self.strippingSystemPrefix(from: ChatMessageVisibleText.visibleText(in: message))
            default:
                kind = .generic
                body = Self.strippingSystemPrefix(from: ChatMessageVisibleText.visibleText(in: message))
            }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            self = .systemNotice(SystemNotice(
                id: message.id,
                kind: kind,
                body: body,
                timestamp: message.timestamp))
            return
        }

        self = .message(message)
    }

    static func build(from messages: [OpenClawChatMessage]) -> [Self] {
        messages.compactMap(Self.init)
    }

    private static func savedTokens(for marker: OpenClawChatHistoryMarker) -> Double? {
        guard let before = marker.tokensBefore,
              before.isFinite,
              let after = marker.tokensAfter,
              after.isFinite,
              before > after
        else {
            return nil
        }
        return floor(before - after)
    }

    private static func strippingSystemPrefix(from text: String) -> String {
        let prefix = "[System] "
        return text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
    }
}

extension ChatTranscriptRow {
    static func mergeToolResults(in messages: [OpenClawChatMessage]) -> [OpenClawChatMessage] {
        var result: [OpenClawChatMessage] = []
        result.reserveCapacity(messages.count)
        var callIndexes: [String: Int] = [:]

        for message in messages {
            // Narration can separate calls from results, but an input or history
            // boundary ends their lookup scope even when a run ID is reused.
            if Self(message)?.startsTurn == true || message.historyMarker != nil {
                callIndexes.removeAll(keepingCapacity: true)
            }
            guard message.isToolResult,
                  let toolCallId = message.toolCallId,
                  let index = callIndexes[toolCallId],
                  (message.workRunID != nil && message.workRunID == result[index].workRunID) ||
                  (index == result.count - 1 &&
                      (message.workRunID == nil || result[index].workRunID == nil))
            else {
                if !message.isForwardedTurnBoundary {
                    for block in message.content where block.isToolCall {
                        if let id = block.id { callIndexes[id] = result.count }
                    }
                    if let id = message.toolCallId { callIndexes[id] = result.count }
                }
                result.append(message)
                continue
            }

            var merged = result[index]
            let toolText = ChatMessageVisibleText.displayText(in: message, includeThinking: false)
            // Preserve empty results too: receiving a result owns the outcome,
            // independently of whether it contains display text.
            merged.content.append(
                OpenClawChatMessageContent(
                    type: "tool_result",
                    text: toolText,
                    id: toolCallId,
                    name: message.toolName,
                    details: message.details,
                    isError: message.isError))

            if let terminal = message.activity {
                merged.activity = (merged.activity ?? []).filter { $0.toolCallId != toolCallId } + terminal
            }
            result[index] = merged
        }

        return result
    }
}

extension ChatTranscriptRow {
    /// One action bar per turn: it belongs under the turn's last completed assistant reply and only
    /// appears once that reply's run is over. Pure so it can be exercised without a view model.
    ///
    /// A turn runs from a user input (or any other turn boundary) to the next one. Intermediate
    /// assistant messages, tool rows and commentary never carry the bar.
    static func isFinalTurnReply(
        _ message: OpenClawChatMessage,
        in messages: [OpenClawChatMessage],
        activeRunIDs: Set<String>,
        runWorking: Bool,
        isMessageVisible: (OpenClawChatMessage) -> Bool) -> Bool
    {
        // Cheap checks first: this runs for every visible assistant row on each render.
        if let runID = message.workRunID, activeRunIDs.contains(runID) { return false }
        guard message.isCompletedReply,
              let index = messages.firstIndex(where: { $0.id == message.id })
        else { return false }
        // Rest of this turn only (bounded work per row), with tool results folded back into their
        // calls exactly like the visible rows, so a resolved call + text counts as a reply here too.
        var end = index + 1
        while end < messages.count,
              messages[end].historyMarker == nil,
              Self(messages[end])?.startsTurn != true
        {
            end += 1
        }
        let isTrailingTurn = end == messages.count
        let rest = Self.mergeToolResults(in: Array(messages[(index + 1)..<end]))
        if rest.contains(where: { $0.isCompletedReply && isMessageVisible($0) }) { return false }
        // Same notion of "still generating" as `footerMetadata`: the trailing turn is live while a run
        // works, unless the reply belongs to a known run that is no longer active.
        if isTrailingTurn, runWorking, activeRunIDs.isEmpty || message.workRunID == nil { return false }
        return true
    }

    @MainActor
    static func isFinalTurnReply(
        _ message: OpenClawChatMessage,
        viewModel: OpenClawChatViewModel,
        isMessageVisible: (OpenClawChatMessage) -> Bool) -> Bool
    {
        // Avoid projecting the whole transcript for rows that can never carry the bar.
        guard message.isCompletedReply else { return false }
        let activeRunIDs = Set(viewModel.liveAdvertisedRunIDs).union(viewModel.liveLocalRunIDs)
        return Self.isFinalTurnReply(
            message,
            in: viewModel.transcriptMessages,
            activeRunIDs: activeRunIDs,
            runWorking: viewModel.hasBlockingRunActivity || viewModel.hasStreamingAssistantText,
            isMessageVisible: isMessageVisible)
    }
}
