import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One owner for chat copy actions on both platforms.
enum ChatPasteboard {
    @MainActor
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

/// Compact icon button that copies `text` and briefly confirms with a checkmark.
@MainActor
struct ChatCopyButton: View {
    let text: String
    let label: LocalizedStringKey
    var revealed = true

    // Shared control hit target for inline block controls.
    #if os(macOS)
    static let controlSize: CGFloat = 28
    #else
    static let controlSize: CGFloat = 44
    #endif

    @State private var copiedAt: Date?

    var body: some View {
        Button {
            ChatPasteboard.copy(self.text)
            self.copiedAt = .now
        } label: {
            Image(systemName: self.copiedAt == nil ? "doc.on.doc" : "checkmark")
                .frame(width: Self.controlSize, height: Self.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChatCopyChipButtonStyle(isSelected: self.copiedAt != nil))
        .accessibilityLabel(self.label)
        .contentTransition(.symbolEffect(.replace))
        .task(id: self.copiedAt) {
            guard let copiedAt = self.copiedAt else { return }
            // A repeat tap changes the id and cancels this task; the newer task owns the reset,
            // so bail on cancellation and only clear the confirmation this task scheduled.
            guard await (try? Task.sleep(for: .seconds(1.5))) != nil, self.copiedAt == copiedAt else { return }
            self.copiedAt = nil
        }
        // macOS reveals inline controls on hover or keyboard focus.
        // iOS has no hover, so the controls stay visible.
        #if os(macOS)
        .help(self.label)
        .modifier(ChatHoverAction(revealed: self.revealed || self.copiedAt != nil))
        #endif
    }
}

/// Small coral chip inside the 44 pt (28 pt on macOS) hit target of inline block controls.
/// Pressed: deeper tint and a small scale through `OpenClawChatMotion` (no scale under Reduce Motion).
/// Selected (copied): accent ink and stronger tint. Disabled: dimmed.
struct ChatCopyChipButtonStyle: ButtonStyle {
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ChatCopyChipBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: self.isSelected)
    }
}

private struct ChatCopyChipBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.isEnabled) private var isEnabled: Bool

    private static var chipSize: CGFloat { 24 }

    var body: some View {
        self.label
            .font(OpenClawChatTypography.caption)
            .foregroundStyle(self.isSelected ? OpenClawChatTheme.brandAccent : OpenClawChatTheme.inkMuted)
            .background(alignment: .center) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(self.chipFill)
                    .frame(width: Self.chipSize, height: Self.chipSize)
            }
            .scaleEffect(self.isPressed && !self.reduceMotion ? 0.92 : 1)
            .opacity(self.isEnabled ? 1 : 0.4)
            .animation(OpenClawChatMotion.animation(reduceMotion: self.reduceMotion), value: self.isPressed)
            .animation(OpenClawChatMotion.animation(reduceMotion: self.reduceMotion), value: self.isSelected)
    }

    private var chipFill: Color {
        if self.isPressed { return OpenClawChatTheme.brandAccent.opacity(0.22) }
        if self.isSelected { return OpenClawChatTheme.brandAccent.opacity(0.16) }
        return OpenClawChatTheme.brandAccent.opacity(0.08)
    }
}

#if os(macOS)
struct ChatHoverAction: ViewModifier {
    let revealed: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused(self.$isFocused)
            // Zero opacity removes native controls from keyboard/AX navigation.
            .opacity(self.revealed || self.isFocused || self.voiceOverEnabled ? 1 : 0.01)
    }
}
#endif
