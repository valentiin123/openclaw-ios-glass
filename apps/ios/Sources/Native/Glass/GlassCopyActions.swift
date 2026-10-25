import SwiftUI
import UIKit

// Copy gestures shared by the Settings screens: trailing swipe and long-press menu.
// Both confirm through the page toast (`GlassToastModel`, injected by `NativeSettingsPage`).
// Outside a toast host they fall back to a plain success haptic, so the gesture never feels dead.

@MainActor
enum GlassClipboard {
    /// Copies `value`, then confirms with the toast (message, VoiceOver announcement, haptic).
    static func copy(_ value: String, toast: GlassToastModel?) {
        UIPasteboard.general.string = value
        if let toast {
            toast.show(String(localized: "Copied"))
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// `nil` for empty or missing values, so callers never offer to copy nothing.
    static func copyable(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private struct GlassCopySwipeModifier: ViewModifier {
    @Environment(GlassToastModel.self) private var toast: GlassToastModel?
    let value: String?

    func body(content: Content) -> some View {
        content.swipeActions(edge: .trailing) {
            if let copyable = GlassClipboard.copyable(self.value) {
                Button {
                    GlassClipboard.copy(copyable, toast: self.toast)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .tint(OpenClawBrand.info)
            }
        }
    }
}

private struct GlassCopyMenuModifier: ViewModifier {
    @Environment(GlassToastModel.self) private var toast: GlassToastModel?
    let value: String?

    func body(content: Content) -> some View {
        content.contextMenu {
            if let copyable = GlassClipboard.copyable(self.value) {
                Button {
                    GlassClipboard.copy(copyable, toast: self.toast)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

private struct GlassActionsMenuModifier<Actions: View>: ViewModifier {
    @Environment(GlassToastModel.self) private var toast: GlassToastModel?
    let value: String?
    let actions: Actions

    func body(content: Content) -> some View {
        content.contextMenu {
            self.actions
            if let copyable = GlassClipboard.copyable(self.value) {
                Button {
                    GlassClipboard.copy(copyable, toast: self.toast)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

extension View {
    /// Long-press menu with extra actions first, then a Copy entry for `value` (toast + haptic).
    /// Use this instead of `glassCopyMenu` when a row needs more than Copy: one menu per row.
    func glassActionsMenu<Actions: View>(
        copying value: String?,
        @ViewBuilder actions: () -> Actions) -> some View
    {
        modifier(GlassActionsMenuModifier(value: value, actions: actions()))
    }

    /// Trailing swipe action that copies `value` and confirms with the toast.
    func glassCopySwipe(_ value: String?) -> some View {
        modifier(GlassCopySwipeModifier(value: value))
    }

    /// Long-press menu entry that copies `value` and confirms with the toast.
    func glassCopyMenu(_ value: String?) -> some View {
        modifier(GlassCopyMenuModifier(value: value))
    }
}
