import OpenClawChatUI
import OpenClawProtocol
import SwiftUI

/// Session mutations shared by the shell's session list. Same server calls as the former
/// sidebar (`RootSidebar`): pin, snooze, archive, fork. The roster is refreshed through the
/// shared `RootSidebarModel` so the Overview and the list never disagree.
@MainActor
struct SessionsListActions {
    let appModel: NodeAppModel
    let model: RootSidebarModel
    let openChat: () -> Void

    // MARK: Mutations

    func performMutation(
        resetActiveSessionKey: String?,
        _ operation: @escaping CommandSessionActionsModifier.Mutation)
    {
        let appModel: NodeAppModel = self.appModel
        let model: RootSidebarModel = self.model
        Task { @MainActor in
            do {
                try await operation(appModel.makeChatTransport())
                if resetActiveSessionKey == appModel.chatSessionKey {
                    appModel.focusChatSession(nil)
                }
                await model.refreshSessions(appModel: appModel)
            } catch {
                model.reportSessionError(error)
            }
        }
    }

    func fork(_ session: OpenClawChatSessionEntry) {
        let appModel: NodeAppModel = self.appModel
        let model: RootSidebarModel = self.model
        let openChat: () -> Void = self.openChat
        let parentKey: String = session.key
        let fromLastCompleted: Bool = session.hasActiveRun == true
        Task { @MainActor in
            do {
                let key: String = try await appModel.makeChatTransport().forkSession(
                    parentKey: parentKey,
                    fromLastCompleted: fromLastCompleted)
                // focusChatSession only: openChat(sessionKey:) also bumps openChatRequestID (legacy chat in RootTabs).
                appModel.focusChatSession(key)
                openChat()
                await model.refreshSessions(appModel: appModel)
            } catch {
                model.reportSessionError(error)
            }
        }
    }

    private func togglePin(key: String, currentlyPinned: Bool) {
        let newPinned: Bool = !currentlyPinned
        let mutation: CommandSessionActionsModifier.Mutation = { (transport: any OpenClawChatTransport) async throws -> Void in
            _ = try await transport.patchSession(
                key: key,
                expectedSessionID: nil,
                label: nil,
                category: nil,
                color: nil,
                pinned: newPinned,
                archived: nil,
                unread: nil)
        }
        self.performMutation(resetActiveSessionKey: nil, mutation)
    }

    private func snooze(key: String, sessionID: String?, patch: OpenClawChatSnoozePatch) {
        let mutation: CommandSessionActionsModifier.Mutation = { (transport: any OpenClawChatTransport) async throws -> Void in
            _ = try await transport.patchSession(
                key: key,
                expectedSessionID: sessionID,
                snoozedUntil: patch)
        }
        self.performMutation(resetActiveSessionKey: nil, mutation)
    }

    private func archive(key: String, sessionID: String?) {
        let mutation: CommandSessionActionsModifier.Mutation = { (transport: any OpenClawChatTransport) async throws -> Void in
            _ = try await transport.patchSession(
                key: key,
                expectedSessionID: sessionID,
                label: nil,
                category: nil,
                color: nil,
                pinned: nil,
                archived: true,
                unread: nil)
        }
        self.performMutation(resetActiveSessionKey: key, mutation)
    }

    // MARK: Swipe actions

    /// Pin, snooze and archive as rightward swipe actions (`SessionSwipeActions.swift`);
    /// same mutations as the long-press context menu.
    func swipeActions(
        for session: OpenClawChatSessionEntry,
        mainSessionKey: String) -> [SessionSwipeAction]
    {
        var actions: [SessionSwipeAction] = []
        let isPinned: Bool = session.pinned == true
        let pinTitle: String = isPinned ? String(localized: "Unpin") : String(localized: "Pin")
        let pinIcon: String = isPinned ? "pin.slash" : "pin"
        let pinKey: String = session.key
        let pinAction: () -> Void = { self.togglePin(key: pinKey, currentlyPinned: isPinned) }
        let pinSwipe: SessionSwipeAction = SessionSwipeAction(
            id: "pin",
            title: pinTitle,
            systemImage: pinIcon,
            tint: OpenClawSidebarPalette.accent,
            perform: pinAction)
        actions.append(pinSwipe)

        let now: Date = Date.now
        let canSnooze: Bool = session.isMain != true &&
            session.archived != true &&
            session.sessionId?.trimmedNonEmpty != nil &&
            !session.isSnoozed(at: now)
        if canSnooze, let preset = OpenClawChatSessionSnooze.presets(now: now).first {
            let snoozeKey: String = session.key
            let snoozeSessionID: String? = session.sessionId
            let snoozeWake: OpenClawChatSnoozePatch = .until(preset.wakeAt)
            let snoozeAction: () -> Void = {
                self.snooze(key: snoozeKey, sessionID: snoozeSessionID, patch: snoozeWake)
            }
            let snoozeSwipe: SessionSwipeAction = SessionSwipeAction(
                id: "snooze",
                title: String(localized: "Snooze"),
                systemImage: "clock",
                tint: Color.orange,
                perform: snoozeAction)
            actions.append(snoozeSwipe)
        }

        if ChatSessionSidebarModel.canArchiveSession(session, mainSessionKey: mainSessionKey) {
            let archiveKey: String = session.key
            let archiveSessionID: String? = session.sessionId
            let archiveAction: () -> Void = {
                self.archive(key: archiveKey, sessionID: archiveSessionID)
            }
            let archiveSwipe: SessionSwipeAction = SessionSwipeAction(
                id: "archive",
                title: String(localized: "Archive"),
                systemImage: "archivebox",
                tint: Color.gray,
                perform: archiveAction)
            actions.append(archiveSwipe)
        }
        return actions
    }
}
