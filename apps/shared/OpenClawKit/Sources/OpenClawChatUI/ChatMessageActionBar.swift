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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-message-action-bar")
    }
}

/// 44 pt hit target around a 32 pt tinted chip (coral icon on a soft coral fill, opaque, no glass).
/// Pressed: deeper tint, hairline and a small scale through `OpenClawChatMotion` (fade only under
/// Reduce Motion). Selected: stronger tint and accent hairline. Disabled: dimmed.
struct ChatMessageActionButtonStyle: ButtonStyle {
    static let touchSize: CGFloat = 44
    static let chipSize: CGFloat = 32
    static let cornerRadius: CGFloat = 10

    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ChatMessageActionButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: self.isSelected)
    }
}

private struct ChatMessageActionButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.isEnabled) private var isEnabled: Bool

    var body: some View {
        self.label
            .foregroundStyle(self.isSelected ? OpenClawChatTheme.brandAccent : OpenClawChatTheme.inkMuted)
            .frame(width: ChatMessageActionButtonStyle.chipSize, height: ChatMessageActionButtonStyle.chipSize)
            .background(self.chipFill, in: self.chipShape)
            .overlay(self.chipShape.strokeBorder(self.chipStroke, lineWidth: 0.5))
            .scaleEffect(self.isPressed && !self.reduceMotion ? 0.92 : 1)
            .opacity(self.isEnabled ? 1 : 0.4)
            .frame(width: ChatMessageActionButtonStyle.touchSize, height: ChatMessageActionButtonStyle.touchSize)
            .contentShape(Rectangle())
            .animation(OpenClawChatMotion.animation(reduceMotion: self.reduceMotion), value: self.isPressed)
            .animation(OpenClawChatMotion.animation(reduceMotion: self.reduceMotion), value: self.isSelected)
    }

    private var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatMessageActionButtonStyle.cornerRadius, style: .continuous)
    }

    private var chipFill: Color {
        if self.isPressed { return OpenClawChatTheme.brandAccent.opacity(0.22) }
        if self.isSelected { return OpenClawChatTheme.brandAccent.opacity(0.16) }
        return OpenClawChatTheme.brandAccent.opacity(0.08)
    }

    private var chipStroke: Color {
        if self.isSelected || self.isPressed { return OpenClawChatTheme.brandAccent.opacity(0.45) }
        return OpenClawChatTheme.hairline
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
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(ChatMessageActionButtonStyle(isSelected: self.copiedAt != nil))
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
