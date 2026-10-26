import OpenClawChatUI
import SwiftUI

/// One session row of the shell's list. Content only: context menu and swipe actions are
/// attached by `AppShellSessionsScreen`. Opaque surface; no glass behind reading content.
struct SessionsListRow: View {
    let node: ChatSessionSidebarModel.Node
    let isSelected: Bool
    let onOpen: () -> Void

    private var session: OpenClawChatSessionEntry {
        self.node.session
    }

    var body: some View {
        Button(action: self.onOpen) {
            self.label
        }
        .buttonStyle(.openClawPress)
        .openClawAnimation(value: self.isSelected)
        .background(self.selectionFill, in: RoundedRectangle(
            cornerRadius: OpenClawProMetric.controlRadius,
            style: .continuous))
        .overlay(alignment: .leading) {
            OpenClawSessionColorStripe(color: self.session.color)
        }
        .accessibilityValue(Self.accessibilityValue(
            isPinned: self.session.pinned == true,
            isUnread: self.session.unread == true))
    }

    private var selectionFill: Color {
        if self.isSelected { return OpenClawSidebarPalette.selection }
        return Color.clear
    }

    private var titleColor: Color {
        if self.isSelected { return OpenClawSidebarPalette.accent }
        return OpenClawSidebarPalette.textStrong
    }

    private var iconColor: Color {
        if self.isSelected { return OpenClawSidebarPalette.accent }
        return OpenClawSidebarPalette.muted
    }

    private var label: some View {
        HStack(spacing: 9) {
            self.leadingIcon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: CommandCenterTab.sessionTitle(self.session))
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(self.titleColor)
                    .lineLimit(1)
                if let subtitle = ChatSessionSidebarModel.subtitle(
                    for: self.session,
                    workSubtitle: ChatSessionSidebarModel.workSubtitle(for: self.session))
                {
                    Text(verbatim: subtitle)
                        .font(OpenClawType.caption2Medium)
                        .foregroundStyle(OpenClawSidebarPalette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if self.session.pinned == true {
                Image(systemName: "pin.fill")
                    .font(OpenClawType.caption2Medium)
                    .foregroundStyle(OpenClawSidebarPalette.accent)
                    .accessibilityHidden(true)
            }
            Text(verbatim: CommandCenterTab.sessionDetail(self.session))
                .font(OpenClawType.caption2Medium)
                .foregroundStyle(OpenClawSidebarPalette.muted)
                .lineLimit(1)
            if self.session.unread == true {
                Circle()
                    .fill(OpenClawSidebarPalette.accent)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if self.node.badges.runningCount > 0 {
            ProgressView()
                .controlSize(.mini)
                .tint(OpenClawSidebarPalette.accent)
        } else {
            Image(systemName: "bubble.left")
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(self.iconColor)
                .accessibilityHidden(true)
        }
    }

    static func accessibilityValue(isPinned: Bool, isUnread: Bool) -> String {
        var states: [String] = []
        if isPinned {
            states.append(String(localized: "Pinned"))
        }
        if isUnread {
            states.append(String(localized: "Unread"))
        }
        return states.joined(separator: ", ")
    }
}
