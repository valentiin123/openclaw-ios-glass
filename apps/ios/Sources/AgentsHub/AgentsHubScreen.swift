import Foundation
import OpenClawChatUI
import OpenClawKit
import SwiftUI

/// Hôte de la destination « Subagents » : branche AgentsHub sur la connexion Gateway opérateur courante.
struct AgentsHubScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    let headerSidebarAction: OpenClawSidebarHeaderAction?

    @State private var model: AgentsHubViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    AgentsHubListView(model: model)
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                if let headerSidebarAction {
                    OpenClawSidebarToolbarItem(action: headerSidebarAction, placement: .topBarLeading)
                }
            }
        }
        .task {
            if model == nil {
                model = AgentsHubViewModel(gateway: Self.makeGateway(session: appModel.operatorSession))
            }
            guard let model else { return }
            await Self.refreshCapabilities(model: model, session: appModel.operatorSession)
            await Self.observeSessionChanges(model: model, session: appModel.operatorSession)
        }
    }

    static func makeGateway(session: GatewayNodeSession) -> AgentsHubGateway {
        AgentsHubGateway(
            request: { request in try await session.request(request) },
            sendMessage: { sessionKey, agentID, message in
                let transport = IOSGatewayChatTransport(gateway: session, globalAgentId: agentID)
                _ = try await transport.sendMessage(
                    sessionKey: sessionKey,
                    agentID: agentID,
                    expectedSessionRoutingContract: nil,
                    message: message,
                    thinking: "off",
                    idempotencyKey: UUID().uuidString.lowercased(),
                    attachments: [])
            },
            fetchResultText: { sessionKey in
                let transport = IOSGatewayChatTransport(gateway: session)
                let payload = try await transport.requestHistory(sessionKey: sessionKey)
                let data = try JSONEncoder().encode(payload.messages ?? [])
                let messages = try JSONDecoder().decode([OpenClawChatMessage].self, from: data)
                guard let last = messages.last(where: { $0.role == "assistant" }) else { return nil }
                let text = last.content.compactMap(\.text).joined(separator: "\n")
                return text.isEmpty ? nil : text
            })
    }

    /// Équivalent iOS de `connection.allows(...)` (macOS seulement) : méthode annoncée + scope opérateur.
    static func refreshCapabilities(model: AgentsHubViewModel, session: GatewayNodeSession) async {
        guard let route = await session.currentRoute() else {
            model.canLaunch = false
            model.canStop = false
            model.canCreateAgent = false
            return
        }
        let scopes = await session.currentOperatorScopes(ifCurrentRoute: route) ?? []
        let hasWrite = scopes.contains("operator.write") || scopes.contains("operator.admin")
        let create = await session.supportsServerMethod("sessions.create", ifCurrentRoute: route) == true
        let abort = await session.supportsServerMethod("chat.abort", ifCurrentRoute: route) == true
        let hasAdmin = scopes.contains("operator.admin")
        let createAgent = await session.supportsServerMethod("agents.create", ifCurrentRoute: route) == true
        model.canLaunch = hasWrite && create
        model.canStop = hasWrite && abort
        model.canCreateAgent = hasAdmin && createAgent
    }

    /// Rafraîchit l'arbre lorsque la Gateway publie `sessions.changed` (la tâche est annulée avec la vue).
    static func observeSessionChanges(model: AgentsHubViewModel, session: GatewayNodeSession) async {
        let stream = await session.subscribeServerEvents()
        for await frame in stream {
            if Task.isCancelled { return }
            if case .sessionsChanged = OpenClawChatGatewayPayloadCodec.event(from: frame) {
                await model.refresh()
            }
        }
    }
}
