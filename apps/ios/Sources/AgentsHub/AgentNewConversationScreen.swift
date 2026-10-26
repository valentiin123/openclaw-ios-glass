import OpenClawChatUI
import SwiftUI

// "New conversation" opened by the + button of the Agents tab.
// It shows the regular chat screen (same composer: + menu, model, thinking, permissions) on a fresh ROOT
// session. The session is created when the cover opens (`sessions.create`, agentId = selected agent, no
// parentSessionKey): model, thinking and permission settings need a real session to be saved on.
// If the cover is closed while the session is still empty, the session is deleted again.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Request

/// What the Agents tab presents: a fresh conversation for one agent. The session key is generated here
/// and only sent to `sessions.create` once the cover is shown.
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

/// Full-screen host. Same structure as `SubagentChatCover` (own NavigationStack, so children of the new
/// conversation can be pushed and edge swipe-back keeps working). No zoom: plain cover.
struct AgentNewConversationCover: View {
    let request: AgentNewConversationRequest

    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var stack: SubagentChatStackModel = SubagentChatStackModel()
    @State private var createdKey: String?
    @State private var errorText: String?

    private static let emptyCheckDelay: Duration = .seconds(2)

    private var pathBinding: Binding<[SubagentChatRoute]> {
        Binding<[SubagentChatRoute]>(
            get: { self.stack.path },
            set: { newValue in self.stack.path = newValue })
    }

    private var gateway: AgentsHubGateway {
        AgentsHubScreen.makeGateway(session: self.appModel.operatorSession)
    }

    var body: some View {
        NavigationStack(path: self.pathBinding) {
            self.root
                .navigationDestination(for: SubagentChatRoute.self) { route in
                    self.child(key: route.key)
                }
        }
        .accessibilityIdentifier("AppShell.NewConversationCover")
        .task { await self.createSession() }
        .onDisappear(perform: self.discardIfEmpty)
    }

    // MARK: Content

    @ViewBuilder
    private var root: some View {
        if let key = self.createdKey {
            SubagentChatScreen(sessionKey: key, isRoot: true, stack: self.stack)
                .id(key)
        } else if let message = self.errorText {
            self.errorView(message)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OpenClawBrand.void.ignoresSafeArea())
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(verbatim: message)
                .font(OpenClawType.subhead)
                .foregroundStyle(OpenClawBrand.danger)
                .multilineTextAlignment(.center)
            Button("Close", action: self.close)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OpenClawBrand.void.ignoresSafeArea())
    }

    private func child(key: String) -> some View {
        SubagentChatScreen(sessionKey: key, isRoot: false, stack: self.stack)
            .id(key)
    }

    // MARK: Actions

    private func close() {
        self.dismiss()
    }

    private func createSession() async {
        if self.createdKey != nil { return }
        do {
            let create: OpenClawChatGatewayRequest = OpenClawChatGatewayRequests.createSession(
                key: self.request.sessionKey,
                agentID: self.request.agentID,
                label: nil,
                parentSessionKey: nil,
                worktree: nil)
            let data: Data = try await self.gateway.request(create)
            let created: OpenClawChatCreateSessionResponse = try JSONDecoder().decode(
                OpenClawChatCreateSessionResponse.self,
                from: data)
            let trimmed: String = created.key.trimmingCharacters(in: .whitespacesAndNewlines)
            self.createdKey = trimmed.isEmpty ? self.request.sessionKey : trimmed
        } catch is CancellationError {
        } catch {
            self.errorText = error.localizedDescription
        }
    }

    /// Closing without sending anything must not leave an empty conversation behind. A short delay lets a
    /// message sent just before closing reach the transcript first; any doubt keeps the session.
    private func discardIfEmpty() {
        guard let key = self.createdKey else { return }
        let agentID: String = self.request.agentID
        let gateway: AgentsHubGateway = self.gateway
        Task { @MainActor in
            try? await Task.sleep(for: Self.emptyCheckDelay)
            do {
                let historyRequest: OpenClawChatGatewayRequest = OpenClawChatGatewayRequests.history(
                    sessionKey: key,
                    agentID: agentID,
                    limit: 1)
                let data: Data = try await gateway.request(historyRequest)
                let payload: OpenClawChatHistoryPayload = try JSONDecoder().decode(
                    OpenClawChatHistoryPayload.self,
                    from: data)
                let isEmpty: Bool = payload.messages?.isEmpty ?? true
                guard isEmpty, payload.inFlightRun == nil else { return }
                _ = try await gateway.request(OpenClawChatGatewayRequests.deleteSession(
                    sessionKey: key,
                    agentID: agentID))
            } catch {
                // Keep the session when anything is unclear.
            }
        }
    }
}
