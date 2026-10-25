import OpenClawChatUI
import OpenClawKit
import SwiftUI

// Clean subagent chat: compact header (sprite, simple name, playful state, duration, discreet Stop),
// a list of running child subagents, then the existing `OpenClawChatView` (full-width assistant text,
// composer as a bottom safe-area inset above the keyboard). Presented inside a full-screen cover,
// so no tab bar is underneath. Glass on header controls and the running-children list; message
// content surfaces stay opaque.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Children

struct SubagentChatChild: Identifiable, Equatable {
    let key: String
    let name: String
    let sprite: AgentTileSpriteKind
    var id: String { self.key }
}

enum SubagentChatChildren {
    /// Direct children of `parentKey` whose run is still active.
    static func running(parentKey: String, sessions: [OpenClawChatSessionEntry]) -> [SubagentChatChild] {
        var result: [SubagentChatChild] = []
        for row in sessions {
            if row.key == parentKey { continue }
            if row.archived == true { continue }
            let parent: String? = row.parentSessionKey ?? row.spawnedBy
            if parent != parentKey { continue }
            let status: AgentsHubRunStatus = AgentsHubRunStatus(row)
            if !status.isActive { continue }
            let name: String = AgentTileNaming.name(for: row.key)
            let sprite: AgentTileSpriteKind = AgentTileNaming.sprite(for: row.key)
            let child: SubagentChatChild = SubagentChatChild(key: row.key, name: name, sprite: sprite)
            result.append(child)
        }
        return result
    }
}

// MARK: - Header

private struct SubagentChatClock: View {
    let item: AgentTileItem

    var body: some View {
        if let start = self.item.startDate {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                self.text(seconds: context.date.timeIntervalSince(start))
            }
        } else {
            self.text(seconds: self.item.elapsed)
        }
    }

    private func text(seconds: TimeInterval?) -> some View {
        let value: String = seconds.flatMap { AgentTileFormat.duration(seconds: $0, spelledOut: false) } ?? ""
        return Text(verbatim: value)
            .font(OpenClawType.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }
}

private struct SubagentChatHeaderBar: View {
    let item: AgentTileItem
    let isRoot: Bool
    let canStop: Bool
    let onBack: () -> Void
    let onStop: () -> Void

    private let spriteSize: CGFloat = 32

    private var backSymbol: String {
        self.isRoot ? "xmark" : "chevron.backward"
    }

    private var backLabel: LocalizedStringKey {
        self.isRoot ? "Close" : "Back"
    }

    private var showsStop: Bool {
        self.canStop && self.item.canBeStopped
    }

    var body: some View {
        HStack(spacing: 10) {
            self.backButton
            self.sprite
            self.titleBlock
            Spacer(minLength: 0)
            self.stopButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenClawBrand.void)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OpenClawBrand.hairlineBorder)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subagent-chat-header")
    }

    private var backButton: some View {
        Button(action: self.onBack) {
            Image(systemName: self.backSymbol)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .openClawGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(self.backLabel))
        .accessibilityIdentifier("subagent-chat-back")
    }

    private var sprite: some View {
        let asleep: Bool = self.item.state.isAsleep
        let opacity: Double = asleep ? 0.55 : 1
        let saturation: Double = asleep ? 0 : 1
        return AgentTileSpriteView(kind: self.item.sprite)
            .frame(width: self.spriteSize, height: self.spriteSize)
            .saturation(saturation)
            .opacity(opacity)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: self.item.name)
                .font(OpenClawType.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            self.stateLine
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.item.accessibilityText))
    }

    private var stateLine: some View {
        HStack(spacing: 6) {
            Text(verbatim: self.item.state.label)
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(self.item.state.tint)
                .lineLimit(1)
            SubagentChatClock(item: self.item)
        }
        .openClawAnimation(value: self.item.state)
    }

    @ViewBuilder
    private var stopButton: some View {
        if self.showsStop {
            Button(action: self.onStop) {
                Image(systemName: "stop.fill")
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(OpenClawBrand.danger)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .openClawGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop"))
            .accessibilityIdentifier("subagent-chat-stop")
        }
    }
}

// MARK: - Children list

private struct SubagentChatChildrenList: View {
    let children: [SubagentChatChild]
    let onOpen: (String) -> Void

    private let visibleLimit: Int = 4

    private var visible: [SubagentChatChild] {
        Array(self.children.prefix(self.visibleLimit))
    }

    private var hiddenCount: Int {
        max(0, self.children.count - self.visibleLimit)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(self.visible) { child in
                self.row(child)
                if child.id != self.visible.last?.id {
                    Divider().overlay(OpenClawBrand.hairlineBorder)
                }
            }
            self.moreRow
        }
        .clipShape(RoundedRectangle(cornerRadius: OpenClawProMetric.cardRadius, style: .continuous))
        .openClawGlass(
            in: RoundedRectangle(cornerRadius: OpenClawProMetric.cardRadius, style: .continuous),
            interactive: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subagent-chat-children")
    }

    private func row(_ child: SubagentChatChild) -> some View {
        Button {
            self.onOpen(child.key)
        } label: {
            HStack(spacing: 10) {
                AgentTileSpriteView(kind: child.sprite)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: child.name)
                        .font(OpenClawType.subheadSemiBold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("Running")
                        .font(OpenClawType.caption)
                        .foregroundStyle(OpenClawBrand.info)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(OpenClawPressButtonStyle())
        .accessibilityHint(Text("Opens the subagent chat"))
        .accessibilityIdentifier("subagent-chat-child")
    }

    @ViewBuilder
    private var moreRow: some View {
        if self.hiddenCount > 0 {
            Divider().overlay(OpenClawBrand.hairlineBorder)
            Text("+\(self.hiddenCount)")
                .font(OpenClawType.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
    }
}

// MARK: - Screen

struct SubagentChatScreen: View {
    let sessionKey: String
    let isRoot: Bool
    let stack: SubagentChatStackModel

    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: OpenClawChatViewModel?
    @State private var confirmsStop: Bool = false
    @State private var openedChildCount: Int = 0

    // MARK: Derived

    private var session: OpenClawChatSessionEntry {
        if let entry = self.viewModel?.currentSessionEntry() { return entry }
        let agentID: String? = OpenClawChatSessionKey.agentID(from: self.sessionKey)
        return OpenClawChatSessionEntry(key: self.sessionKey, agentId: agentID)
    }

    private var headerItem: AgentTileItem {
        let entry: OpenClawChatSessionEntry = self.session
        return AgentTileFactory.item(for: entry, isMain: entry.isMain == true, now: Date())
    }

    private var children: [SubagentChatChild] {
        guard let viewModel else { return [] }
        return SubagentChatChildren.running(parentKey: self.sessionKey, sessions: viewModel.sessions)
    }

    private var openHook: OpenClawChatOpenSubagent {
        let target: SubagentChatStackModel = self.stack
        let hook: OpenClawChatOpenSubagent = { key in
            target.open(key)
        }
        return hook
    }

    private var composerEnabled: Bool {
        self.appModel.isOperatorGatewayConnected
    }

    // MARK: Body

    var body: some View {
        self.content
            .background(OpenClawBrand.void.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .appShellSwipeBack()
            .chatPullToDismiss(onDismiss: self.goBack)
            .sensoryFeedback(.selection, trigger: self.openedChildCount)
            .sensoryFeedback(.warning, trigger: self.confirmsStop) { _, isPresented in isPresented }
            .environment(\.openClawChatOpenSubagent, self.openHook)
            .environment(\.openClawChatSubagentHeaderHidden, true)
            .confirmationDialog(
                "Stop this subagent?",
                isPresented: self.$confirmsStop,
                titleVisibility: .visible,
                actions: { self.stopDialogActions })
            .task { await self.run() }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let viewModel {
                self.chat(viewModel)
                    .transition(.opacity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) { self.headerStack }
                    .transition(.opacity)
            }
        }
        .openClawAnimation(value: self.viewModel != nil)
    }

    private func chat(_ model: OpenClawChatViewModel) -> some View {
        OpenClawChatView(
            viewModel: model,
            resolveComposerModel: model.composerModelResolver(),
            drawsBackground: true,
            showsSessionSwitcher: false,
            displayOptions: .toolActivity,
            showsAssistantAvatars: false,
            composerChrome: .clean,
            isComposerEnabled: self.composerEnabled,
            isAttachmentInputEnabled: self.composerEnabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .top, spacing: 0) { self.headerStack }
    }

    private var headerStack: some View {
        VStack(spacing: 0) {
            SubagentChatHeaderBar(
                item: self.headerItem,
                isRoot: self.isRoot,
                canStop: self.appModel.isOperatorGatewayConnected,
                onBack: self.goBack,
                onStop: self.requestStop)
            self.childrenSection
        }
        .background(OpenClawBrand.void)
    }

    @ViewBuilder
    private var childrenSection: some View {
        let list: [SubagentChatChild] = self.children
        if !list.isEmpty {
            SubagentChatChildrenList(children: list, onOpen: self.openChild)
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
                .openClawAnimation(value: list)
        }
    }

    @ViewBuilder
    private var stopDialogActions: some View {
        Button("Stop", role: .destructive, action: self.confirmStop)
        Button("Cancel", role: .cancel, action: self.cancelStop)
    }

    // MARK: Actions

    private func goBack() {
        self.dismiss()
    }

    private func openChild(_ key: String) {
        self.openedChildCount += 1
        self.stack.open(key)
    }

    private func requestStop() {
        self.confirmsStop = true
    }

    private func cancelStop() {
        self.confirmsStop = false
    }

    private func confirmStop() {
        self.confirmsStop = false
        self.viewModel?.abort()
    }

    // MARK: Lifecycle

    /// Builds the view model once, then keeps the session row fresh while the screen is up.
    private func run() async {
        self.prepare()
        while !Task.isCancelled {
            self.viewModel?.refreshSessions()
            try? await Task.sleep(for: .seconds(4))
        }
    }

    /// Own view model for this subagent session: it never retargets the main chat
    /// (no `onSessionChanged`) and does not share the main chat's outbox.
    private func prepare() {
        if self.viewModel != nil { return }
        let store: OpenClawChatSQLiteTranscriptCache? = self.appModel.makeChatOfflineStore()
        let transport: any OpenClawChatTransport = self.appModel.makeChatTransport(outboxGatewayID: store?.gatewayID)
        let agentID: String? = OpenClawChatSessionKey.agentID(from: self.sessionKey)
        let model: OpenClawChatViewModel = OpenClawChatViewModel(
            sessionKey: self.sessionKey,
            transport: transport,
            activeAgentId: agentID,
            sessionRoutingContract: self.appModel.chatSessionRoutingContract,
            transcriptCache: store,
            diagnosticsLog: { message in GatewayDiagnostics.log(message) })
        self.viewModel = model
        model.load()
    }
}
