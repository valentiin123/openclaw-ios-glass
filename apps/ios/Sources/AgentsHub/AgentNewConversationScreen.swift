import OpenClawChatUI
import SwiftUI

// Empty "new conversation" screen opened by the + button of the Agents tab.
// No session exists while the draft is open: nothing is created on the Gateway until the first message is
// sent. Then a ROOT session is created (`sessions.create`, agentId = selected agent, no parentSessionKey),
// the message is sent into it, and the screen swaps to the regular chat screen of that session.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Request

/// What the Agents tab presents: an empty draft for one agent. The session key is only generated here,
/// it is sent to `sessions.create` with the first message and never before.
struct AgentNewConversationRequest: Identifiable, Hashable, Sendable {
    let agentID: String
    let sessionKey: String
    var id: String { self.sessionKey }

    init(agentID: String) {
        let suffix: String = UUID().uuidString.lowercased()
        self.agentID = agentID
        self.sessionKey = "agent:\(agentID):ios-\(suffix)"
    }
}

// MARK: - Cover

/// Full-screen host of the draft. Same structure as `SubagentChatCover` (own NavigationStack, so children
/// of the new conversation can be pushed and edge swipe-back keeps working). No zoom: plain cover.
struct AgentNewConversationCover: View {
    let request: AgentNewConversationRequest

    @State private var stack: SubagentChatStackModel = SubagentChatStackModel()

    private var pathBinding: Binding<[SubagentChatRoute]> {
        Binding<[SubagentChatRoute]>(
            get: { self.stack.path },
            set: { newValue in self.stack.path = newValue })
    }

    var body: some View {
        NavigationStack(path: self.pathBinding) {
            AgentNewConversationScreen(
                agentID: self.request.agentID,
                sessionKey: self.request.sessionKey,
                stack: self.stack)
                .navigationDestination(for: SubagentChatRoute.self) { route in
                    self.child(key: route.key)
                }
        }
        .accessibilityIdentifier("AppShell.NewConversationCover")
    }

    private func child(key: String) -> some View {
        SubagentChatScreen(sessionKey: key, isRoot: false, stack: self.stack)
            .id(key)
    }
}

// MARK: - Screen

struct AgentNewConversationScreen: View {
    let agentID: String
    /// Pre-generated key of the future session (only used by `sessions.create`, never before the first send).
    let sessionKey: String
    let stack: SubagentChatStackModel

    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var isSending: Bool = false
    @State private var errorText: String?
    /// Set once `sessions.create` succeeded, so a failed send can be retried without creating a second session.
    @State private var createdKey: String?
    /// Set once the first message went out: the screen shows the real chat of this session.
    @State private var openedKey: String?
    @FocusState private var isFocused: Bool

    private let spriteSize: CGFloat = 72

    // MARK: Derived

    private var trimmedText: String {
        self.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        if self.isSending { return false }
        if self.trimmedText.isEmpty { return false }
        return self.appModel.isOperatorGatewayConnected
    }

    private var sendTint: Color? {
        if self.canSend { return OpenClawBrand.accentFill }
        return nil
    }

    // MARK: Body

    var body: some View {
        Group {
            if let key = self.openedKey {
                SubagentChatScreen(sessionKey: key, isRoot: true, stack: self.stack)
                    .id(key)
            } else {
                self.draft
            }
        }
    }

    private var draft: some View {
        VStack(spacing: 0) {
            self.header
            self.emptyState
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OpenClawBrand.void.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            self.composer
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("AppShell.NewConversation")
        .task { self.isFocused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            self.closeButton
            VStack(alignment: .leading, spacing: 2) {
                Text("New conversation")
                    .font(OpenClawType.headline)
                    .foregroundStyle(OpenClawBrand.textPrimary)
                    .lineLimit(1)
                Text(verbatim: self.agentID)
                    .font(OpenClawType.caption)
                    .foregroundStyle(OpenClawBrand.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
        .padding(.vertical, 8)
    }

    private var closeButton: some View {
        Button(action: self.close) {
            Image(systemName: "xmark")
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .openClawGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close"))
        .accessibilityIdentifier("AppShell.NewConversation.Close")
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            AgentTileSpriteView(kind: AgentTileEmptyContent.sprite)
                .frame(width: self.spriteSize, height: self.spriteSize)
            Text("New conversation")
                .font(OpenClawType.headline)
                .foregroundStyle(OpenClawBrand.textPrimary)
                .multilineTextAlignment(.center)
            Text("Send a message to start. The conversation is only created when you send it.")
                .font(OpenClawType.subhead)
                .foregroundStyle(OpenClawBrand.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            self.errorRow
            HStack(alignment: .bottom, spacing: 8) {
                self.field
                self.sendButton
            }
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var errorRow: some View {
        if let message = self.errorText {
            Text(verbatim: message)
                .font(OpenClawType.caption)
                .foregroundStyle(OpenClawBrand.danger)
                .lineLimit(3)
        }
    }

    private var field: some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return TextField("Message", text: self.$text, axis: .vertical)
            .font(OpenClawType.body)
            .lineLimit(1...5)
            .focused(self.$isFocused)
            .disabled(self.isSending)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .openClawGlass(in: shape)
            .accessibilityIdentifier("AppShell.NewConversation.Field")
    }

    private var sendButton: some View {
        Button(action: self.send) {
            self.sendIcon
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .openClawGlass(in: Circle(), tint: self.sendTint, interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(!self.canSend)
        .accessibilityLabel(Text("Send"))
        .accessibilityIdentifier("AppShell.NewConversation.Send")
    }

    @ViewBuilder
    private var sendIcon: some View {
        if self.isSending {
            ProgressView()
        } else {
            Image(systemName: "arrow.up")
        }
    }

    // MARK: Actions

    private func close() {
        if let handler = self.stack.onCloseRoot {
            handler()
            return
        }
        self.dismiss()
    }

    private func send() {
        guard self.canSend else { return }
        let message: String = self.trimmedText
        self.isSending = true
        self.errorText = nil
        Task { await self.createAndSend(message) }
    }

    /// First message: create a root session (no parent) for the selected agent, then send into it.
    /// Reuses the same Gateway wiring as the rest of AgentsHub (`createSession`, `sendMessage`).
    private func createAndSend(_ message: String) async {
        let gateway: AgentsHubGateway = AgentsHubScreen.makeGateway(session: self.appModel.operatorSession)
        do {
            var targetKey: String = self.createdKey ?? ""
            if targetKey.isEmpty {
                let request: OpenClawChatGatewayRequest = OpenClawChatGatewayRequests.createSession(
                    key: self.sessionKey,
                    agentID: self.agentID,
                    label: nil,
                    parentSessionKey: nil,
                    worktree: nil)
                let data: Data = try await gateway.request(request)
                let created: OpenClawChatCreateSessionResponse = try JSONDecoder().decode(
                    OpenClawChatCreateSessionResponse.self,
                    from: data)
                let trimmedKey: String = created.key.trimmingCharacters(in: .whitespacesAndNewlines)
                targetKey = trimmedKey
                if trimmedKey.isEmpty {
                    targetKey = self.sessionKey
                }
                self.createdKey = targetKey
            }
            try await gateway.sendMessage(targetKey, self.agentID, message)
            self.text = ""
            self.isSending = false
            self.openedKey = targetKey
        } catch {
            self.errorText = error.localizedDescription
            self.isSending = false
        }
    }
}
