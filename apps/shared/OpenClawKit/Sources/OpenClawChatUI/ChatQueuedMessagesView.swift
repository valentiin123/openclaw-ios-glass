import SwiftUI

/// Messages waiting for the current response to finish, shown above the draft.
/// Opaque palette rows (no Liquid Glass). Each row can be cancelled on its own before it is sent.
struct ChatQueuedMessagesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let queue: ChatSendQueue

    private static let rowHeight: CGFloat = 44
    private static let cornerRadius: CGFloat = 10

    var body: some View {
        let items: [ChatQueuedMessage] = self.queue.items
        if !items.isEmpty {
            VStack(spacing: 4) {
                ForEach(items) { item in
                    self.row(item)
                        .transition(.opacity)
                }
            }
            .openClawChatAnimation(value: items.count)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat-queued-messages")
        }
    }

    private func row(_ item: ChatQueuedMessage) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        let attachmentCount: Int = item.attachments.count
        return HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(OpenClawChatTypography.caption)
                .foregroundStyle(OpenClawChatTheme.inkMuted)
                .accessibilityHidden(true)
            Text(verbatim: item.summary)
                .font(OpenClawChatTypography.caption)
                .foregroundStyle(OpenClawChatTheme.inkStrong)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if attachmentCount > 0, !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(systemName: "paperclip")
                    .font(OpenClawChatTypography.caption)
                    .foregroundStyle(OpenClawChatTheme.inkMuted)
                    .accessibilityHidden(true)
            }
            Button {
                OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
                    self.queue.cancel(id: item.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(OpenClawChatTypography.captionSemiBold)
                    .foregroundStyle(OpenClawChatTheme.inkMuted)
                    .frame(width: Self.rowHeight, height: Self.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Cancel queued message"))
            .accessibilityIdentifier("chat-queued-message-cancel")
        }
        .padding(.leading, 12)
        .frame(minHeight: Self.rowHeight)
        .background(OpenClawChatTheme.surfaceCard, in: shape)
        .overlay(shape.strokeBorder(OpenClawChatTheme.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
