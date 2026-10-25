import OpenClawChatUI
import OpenClawKit
import SwiftUI

// Agents tab content: a glass agent selector (top left) and, below it, a grid of tiles.
// One tile = one subagent of the selected agent (the agent's main session comes first).
// Glass only on the selector; tiles are opaque. Detail and stop reuse the existing AgentsHub types.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Host

/// Owns the view model and wires it to the operator Gateway session (same wiring as `AgentsHubScreen`).
struct AgentsBoardScreen: View {
    @Environment(NodeAppModel.self) private var appModel

    @State private var model: AgentsHubViewModel?

    var body: some View {
        Group {
            if let model {
                AgentsBoardView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil {
                model = AgentsHubViewModel(gateway: AgentsHubScreen.makeGateway(session: appModel.operatorSession))
            }
            guard let model else { return }
            await AgentsHubScreen.refreshCapabilities(model: model, session: appModel.operatorSession)
            await AgentsHubScreen.observeSessionChanges(model: model, session: appModel.operatorSession)
        }
    }
}

// MARK: - Board

struct AgentsBoardView: View {
    @Bindable var model: AgentsHubViewModel

    @State private var selectedAgentID: String?
    @State private var detailItem: AgentTileItem?
    @State private var confirmStop: AgentTileItem?
    @State private var chatPresenter: SubagentChatPresenter = SubagentChatPresenter()
    @State private var tileFrames: AgentTileFrameStore = AgentTileFrameStore()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 140), spacing: 12, alignment: .top),
    ]

    // MARK: Derived

    private var currentAgentID: String? {
        if let selectedAgentID { return selectedAgentID }
        if let fallback = model.defaultAgentID { return fallback }
        return model.agents.first?.id
    }

    private var currentAgent: OpenClawChatAgentChoice? {
        guard let id = self.currentAgentID else { return nil }
        for agent in model.agents where agent.id == id {
            return agent
        }
        return nil
    }

    private var agentBinding: Binding<String> {
        Binding<String>(
            get: { self.currentAgentID ?? "" },
            set: { newValue in self.selectedAgentID = newValue })
    }

    private var confirmStopBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.confirmStop != nil },
            set: { newValue in if !newValue { self.confirmStop = nil } })
    }

    private func items(now: Date) -> [AgentTileItem] {
        guard let id = self.currentAgentID else { return [] }
        return AgentTileFactory.items(sessions: model.boardSessions, agentID: id, now: now)
    }

    // MARK: Body

    var body: some View {
        self.content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                self.selectorBar
            }
            .background(OpenClawProBackground())
            .overlay { self.overlayState }
            .task { await self.loadAgentsIfNeeded() }
            .task(id: self.currentAgentID) { await self.loadBoardIfPossible() }
            .sheet(item: self.$detailItem) { item in
                SubagentResultSheet(model: self.model, node: AgentTileFactory.node(for: item))
            }
            .subagentChatZoomPresentation(presenter: self.chatPresenter)
            .confirmationDialog(
                "Stop this subagent and its descendants?",
                isPresented: self.confirmStopBinding,
                titleVisibility: .visible,
                actions: { self.stopDialogActions })
    }

    // MARK: Loading

    private func loadAgentsIfNeeded() async {
        if model.agents.isEmpty { await model.loadAgents() }
    }

    private func loadBoardIfPossible() async {
        guard let id = self.currentAgentID else { return }
        await model.loadBoard(agentID: id)
    }

    // MARK: Selector

    private var selectorBar: some View {
        HStack(spacing: 0) {
            self.selector
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
        .padding(.vertical, 8)
    }

    private var selector: some View {
        Menu {
            self.selectorItems
        } label: {
            self.selectorLabel
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(model.agents.isEmpty)
        .accessibilityLabel(Text("Agent"))
        .accessibilityValue(Text(verbatim: self.currentAgent?.displayName ?? ""))
        .accessibilityIdentifier("AppShell.Agents.Selector")
    }

    @ViewBuilder
    private var selectorItems: some View {
        Picker("Agent", selection: self.agentBinding) {
            ForEach(model.agents) { agent in
                Text(verbatim: agent.displayName).tag(agent.id)
            }
        }
    }

    private var selectorLabel: some View {
        let avatar: String = self.currentAgent?.avatarText ?? "?"
        let name: String = self.currentAgent?.displayName ?? String(localized: "Agents")
        return HStack(spacing: 8) {
            Text(verbatim: avatar)
                .font(OpenClawType.subheadSemiBold)
            Text(verbatim: name)
                .font(OpenClawType.subheadSemiBold)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(OpenClawType.caption2SemiBold)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .openClawGlassCapsule(interactive: true)
    }

    // MARK: Grid

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                self.errorRow
                self.timeline
            }
            .padding(.horizontal, OpenClawProMetric.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, OpenClawProMetric.bottomScrollInset)
        }
        .refreshable { await self.loadBoardIfPossible() }
    }

    /// Re-evaluates the list every 30 s so finished subagents leave the grid 30 minutes after they ended.
    private var timeline: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            self.grid(now: context.date)
        }
    }

    private func grid(now: Date) -> some View {
        let list: [AgentTileItem] = self.items(now: now)
        return LazyVGrid(columns: self.columns, alignment: .center, spacing: 12) {
            ForEach(list) { item in
                self.tile(item)
            }
        }
        .agentsHubAnimation(value: list)
    }

    private func tile(_ item: AgentTileItem) -> some View {
        AgentTileView(
            item: item,
            canStop: model.canStop,
            onOpen: { opened in self.openChat(opened) },
            onStop: { stopped in self.requestStop(stopped) },
            onDetails: { opened in self.openDetail(opened) },
            frameStore: self.tileFrames)
    }

    @ViewBuilder
    private var errorRow: some View {
        if let message = model.boardError ?? model.agentsError {
            AgentsHubErrorRow(message: message, retry: self.retry)
        }
    }

    @ViewBuilder
    private var overlayState: some View {
        if model.agents.isEmpty, model.isLoadingAgents {
            ProgressView().accessibilityLabel(Text("Loading agents"))
        } else if model.agents.isEmpty, model.agentsError == nil {
            ContentUnavailableView("No agents", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    // MARK: Actions

    private func retry() {
        Task {
            if model.agents.isEmpty { await model.loadAgents() }
            await self.loadBoardIfPossible()
        }
    }

    private func openChat(_ item: AgentTileItem) {
        let rect: CGRect? = self.tileFrames.frame(for: item.session.key)
        self.chatPresenter.open(item.session.key, from: rect)
    }

    private func openDetail(_ item: AgentTileItem) {
        self.detailItem = item
    }

    private func requestStop(_ item: AgentTileItem) {
        self.confirmStop = item
    }

    @ViewBuilder
    private var stopDialogActions: some View {
        Button("Stop", role: .destructive, action: self.confirmStopNow)
        Button("Cancel", role: .cancel, action: self.cancelStop)
    }

    private func cancelStop() {
        self.confirmStop = nil
    }

    private func confirmStopNow() {
        guard let item = self.confirmStop else { return }
        self.confirmStop = nil
        let node: SubagentNode = AgentTileFactory.node(for: item)
        let agentID: String? = self.currentAgentID
        Task {
            await model.stop(node)
            if let agentID { await model.loadBoard(agentID: agentID) }
        }
    }
}
