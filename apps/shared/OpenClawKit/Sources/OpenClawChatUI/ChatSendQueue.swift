import Foundation
import Observation

/// One message waiting for the current response to finish.
struct ChatQueuedMessage: Identifiable {
    let id: UUID
    let text: String
    let attachments: [OpenClawPendingAttachment]

    /// Single-line text for the queue row.
    var summary: String {
        let trimmed: String = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let first: String = self.attachments.first?.fileName ?? ""
        return first
    }
}

extension OpenClawChatViewModel {
    /// A draft may be queued while a response runs. It has the same guards as `canSend`, minus the run check.
    var canQueueSend: Bool {
        !self.usesWebConversation &&
            !self.isSubmittingDraft &&
            !self.isSending &&
            self.attachmentStagingCount == 0 &&
            self.composerModelAvailabilityMessage == nil &&
            self.hasDraftToSend
    }

    /// True once nothing is running or being submitted, so the next queued message may go out.
    var isReadyForQueuedSend: Bool {
        !self.usesWebConversation &&
            !self.isSubmittingDraft &&
            !self.isSending &&
            self.attachmentStagingCount == 0 &&
            !self.hasBlockingRunActivity &&
            self.composerModelAvailabilityMessage == nil
    }
}

/// FIFO of messages sent while a response is running. Owned by the composer.
/// Integration point: when the ViewModel gains stored queue state, move this type there.
@MainActor
@Observable
final class ChatSendQueue {
    private(set) var items: [ChatQueuedMessage] = []
    private var isDispatching: Bool = false

    /// Moves the current draft into the queue and clears the composer. Returns false when it cannot be queued.
    @discardableResult
    func enqueueCurrentDraft(of viewModel: OpenClawChatViewModel) -> Bool {
        guard viewModel.canQueueSend else { return false }
        let message: ChatQueuedMessage = ChatQueuedMessage(
            id: UUID(),
            text: viewModel.input,
            attachments: viewModel.attachments)
        self.items.append(message)
        viewModel.input = ""
        viewModel.attachments = []
        return true
    }

    func cancel(id: UUID) {
        self.items.removeAll { $0.id == id }
    }

    func removeAll() {
        self.items.removeAll()
    }

    /// Sends the oldest queued message when the previous response is done.
    /// A draft the user is typing meanwhile is set aside during the hand-off and put back after it.
    func dispatchNextIfReady(viewModel: OpenClawChatViewModel) async {
        guard !self.isDispatching,
              let next = self.items.first,
              viewModel.isReadyForQueuedSend
        else { return }
        self.isDispatching = true
        defer { self.isDispatching = false }

        let savedInput: String = viewModel.input
        let savedAttachments: [OpenClawPendingAttachment] = viewModel.attachments
        viewModel.input = next.text
        viewModel.attachments = next.attachments

        guard let task = viewModel.send() else {
            // Not accepted: keep the message queued and give the draft back.
            viewModel.input = savedInput
            viewModel.attachments = savedAttachments
            return
        }
        self.items.removeAll { $0.id == next.id }
        await task.value

        let hasSavedDraft: Bool = !savedInput.isEmpty || !savedAttachments.isEmpty
        if hasSavedDraft {
            viewModel.input = savedInput
            viewModel.attachments = savedAttachments
        }
    }
}
