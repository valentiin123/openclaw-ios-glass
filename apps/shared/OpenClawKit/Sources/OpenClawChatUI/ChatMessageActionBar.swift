#if os(iOS)
import SwiftUI

/// Three icon-only actions under an assistant reply: add a reaction, copy, reply.
///
/// - Every control is a 44 pt touch target with a VoiceOver label.
/// - Opaque, discreet surface (`OpenClawChatTheme`): no Liquid Glass. The only fill is a pressed state.
/// - Eligibility is decided by the caller, so the existing reaction/copy/reply rules stay in one place.
@MainActor
struct ChatMessageActionBar: View {
    let copyText: String
    let canReact: Bool
    let onReact: () -> Void
    let onReply: (() -> Void)?

    private enum Metrics {
        static let spacing: CGFloat = 4
    }

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            if self.canReact {
                Button(action: self.onReact) {
                    Image(systemName: "face.smiling")
                }
                .buttonStyle(ChatMessageActionButtonStyle())
                .accessibilityLabel(String(localized: "Add Reaction"))
                .accessibilityIdentifier("chat-add-reaction")
            }
            if !self.copyText.isEmpty {
                ChatMessageCopyActionButton(text: self.copyText)
            }
            if let onReply = self.onReply {
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                .buttonStyle(ChatMessageActionButtonStyle())
                .accessibilityLabel(String(localized: "Reply"))
                .accessibilityIdentifier("chat-reply-message")
            }
        }
        .font(OpenClawChatTypography.callout)
        .foregroundStyle(OpenClawChatTheme.inkMuted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-message-action-bar")
    }
}

/// 44 pt icon button, no glass: transparent at rest, an opaque theme surface while pressed.
struct ChatMessageActionButtonStyle: ButtonStyle {
    static let touchSize: CGFloat = 44
    private static let cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        let pressedFill: Color = configuration.isPressed ? OpenClawChatTheme.surfaceHover : Color.clear
        return configuration.label
            .frame(width: Self.touchSize, height: Self.touchSize)
            .background(
                pressedFill,
                in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

@MainActor
private struct ChatMessageCopyActionButton: View {
    let text: String
    @State private var copiedAt: Date?

    private static let confirmationSeconds: Double = 1.5

    var body: some View {
        Button {
            ChatPasteboard.copy(self.text)
            self.copiedAt = .now
        } label: {
            Image(systemName: self.symbolName)
        }
        .buttonStyle(ChatMessageActionButtonStyle())
        .accessibilityLabel(String(localized: "Copy Message"))
        .accessibilityIdentifier("chat-copy-message")
        .task(id: self.copiedAt) {
            guard let copiedAt = self.copiedAt else { return }
            // A repeat tap changes the id and cancels this task; only clear our own confirmation.
            guard await (try? Task.sleep(for: .seconds(Self.confirmationSeconds))) != nil,
                  self.copiedAt == copiedAt
            else { return }
            self.copiedAt = nil
        }
    }

    private var symbolName: String {
        self.copiedAt == nil ? "doc.on.doc" : "checkmark"
    }
}
#endif
