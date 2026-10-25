import OpenClawChatUI
import SwiftUI

// Parent / child run tree made of Liquid Glass tiles (`AgentGlassTile`).
// Live status comes from `AgentsHubViewModel` (refreshed on `sessions.changed` by the host).
// Gestures: swipe left = stop (asks for confirmation), swipe right = run details, long press =
// context menu (tile), pull down from the top zone = close. Every gesture has a visible button path.
// Reduce Motion: rows never move; gestures still commit.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Swipe

private enum AgentRowSwipeMetric {
    static let minimumDistance: CGFloat = 16
    static let resistance: CGFloat = 0.4
    static let commitDistance: CGFloat = 44
    static let maxTravel: CGFloat = 64
    static let dominance: CGFloat = 1.5
}

private struct AgentRowSwipeModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = 0

    let canStop: Bool
    let onStop: () -> Void
    let onDetails: () -> Void

    private var offsetX: CGFloat {
        self.reduceMotion ? 0 : self.travel
    }

    private var reachedThreshold: Bool {
        abs(self.travel) >= AgentRowSwipeMetric.commitDistance
    }

    func body(content: Content) -> some View {
        content
            .offset(x: self.offsetX)
            .simultaneousGesture(self.dragGesture)
            .sensoryFeedback(.impact(weight: .light), trigger: self.reachedThreshold)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: AgentRowSwipeMetric.minimumDistance)
            .onChanged { value in
                self.handleChange(value)
            }
            .onEnded { value in
                self.handleEnd(value)
            }
    }

    private func isHorizontal(_ value: DragGesture.Value) -> Bool {
        let side: CGFloat = abs(value.translation.width)
        let vertical: CGFloat = abs(value.translation.height)
        return side > AgentRowSwipeMetric.dominance * vertical
    }

    private func clamped(_ width: CGFloat) -> CGFloat {
        let scaled: CGFloat = width * AgentRowSwipeMetric.resistance
        let limit: CGFloat = AgentRowSwipeMetric.maxTravel
        let lowered: CGFloat = scaled < -limit ? -limit : scaled
        return lowered > limit ? limit : lowered
    }

    private func handleChange(_ value: DragGesture.Value) {
        guard self.isHorizontal(value) else {
            if self.travel != 0 { self.reset() }
            return
        }
        let next: CGFloat = self.clamped(value.translation.width)
        if next < 0, !self.canStop {
            self.travel = 0
            return
        }
        self.travel = next
    }

    private func handleEnd(_ value: DragGesture.Value) {
        defer { self.reset() }
        guard self.isHorizontal(value) else { return }
        let width: CGFloat = self.clamped(value.translation.width)
        if width <= -AgentRowSwipeMetric.commitDistance, self.canStop {
            self.onStop()
        } else if width >= AgentRowSwipeMetric.commitDistance {
            self.onDetails()
        }
    }

    private func reset() {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.travel = 0
        }
    }
}

private extension View {
    func agentRowSwipe(
        canStop: Bool,
        onStop: @escaping () -> Void,
        onDetails: @escaping () -> Void) -> some View
    {
        modifier(AgentRowSwipeModifier(canStop: canStop, onStop: onStop, onDetails: onDetails))
    }
}

// MARK: - Row

private struct AgentGlassTreeRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let row: FlatSubagentRow
    let item: AgentTileItem
    let canStop: Bool
    let namespace: Namespace.ID
    let onOpen: (AgentTileItem) -> Void
    let onStop: (AgentTileItem) -> Void
    let onDetails: (AgentTileItem) -> Void
    let onToggle: (String) -> Void

    private let indentStep: CGFloat = 20

    private var hasChildren: Bool {
        !self.row.node.children.isEmpty
    }

    private var indent: CGFloat {
        CGFloat(self.row.depth) * self.indentStep
    }

    private var canStopRow: Bool {
        self.canStop && self.item.canBeStopped
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            self.connector
            self.tile
            self.disclosure
        }
        .padding(.leading, self.indent)
        .transition(OpenClawMotion.edge(.top, reduceMotion: self.reduceMotion))
        .sensoryFeedback(.selection, trigger: self.row.isExpanded)
    }

    private var chevronDegrees: Double {
        self.row.isExpanded ? 90 : 0
    }

    private var tile: some View {
        AgentGlassTile(
            item: self.item,
            canStop: self.canStop,
            namespace: self.namespace,
            onOpen: self.onOpen,
            onStop: self.onStop)
            .agentRowSwipe(
                canStop: self.canStopRow,
                onStop: self.requestStop,
                onDetails: self.requestDetails)
            .accessibilityAction(named: Text("View details"), self.requestDetails)
    }

    @ViewBuilder
    private var connector: some View {
        if self.row.depth > 0 {
            Rectangle()
                .fill(OpenClawBrand.hairlineBorder)
                .frame(width: OpenClawProMetric.borderWidth)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        if self.hasChildren {
            Button(action: self.toggle) {
                Image(systemName: "chevron.right")
                    .font(OpenClawType.captionSemiBold)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(self.chevronDegrees))
                    .animation(OpenClawMotion.animation(reduceMotion: self.reduceMotion), value: self.row.isExpanded)
                    .frame(width: OpenClawHitTarget.minimum, height: OpenClawHitTarget.minimum)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(self.row.isExpanded ? "Collapse" : "Expand"))
        }
    }

    private func toggle() {
        self.onToggle(self.row.node.id)
    }

    private func requestStop() {
        self.onStop(self.item)
    }

    private func requestDetails() {
        self.onDetails(self.item)
    }
}

// MARK: - Screen

/// Full tree screen for one root session. Host it in a `NavigationStack` (or a sheet).
struct AgentGlassTreeScreen: View {
    @Bindable var model: AgentsHubViewModel
    let root: OpenClawChatSessionEntry

    @Environment(\.dismiss) private var dismiss
    @Namespace private var namespace

    @State private var detailNode: SubagentNode?
    @State private var confirmStop: AgentTileItem?
    @State private var showLaunch: Bool = false
    @State private var chatPresenter: SubagentChatPresenter = SubagentChatPresenter()

    // MARK: Derived

    private var confirmStopBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.confirmStop != nil },
            set: { newValue in if !newValue { self.confirmStop = nil } })
    }

    private var isLive: Bool {
        guard let tree = self.model.tree else { return false }
        return tree.status.isActive || tree.activeDescendantCount > 0
    }

    // MARK: Body

    var body: some View {
        self.content
            .background(OpenClawProBackground())
            .overlay { self.overlayState }
            .navigationTitle("Subagents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { self.toolbarContent }
            .refreshable { await self.model.loadTree(root: self.root) }
            .task(id: self.root.key) { await self.model.loadTree(root: self.root) }
            .chatPullToDismiss(onDismiss: self.close)
            .sheet(item: self.$detailNode) { node in
                SubagentResultSheet(model: self.model, node: node)
            }
            .sheet(isPresented: self.$showLaunch) {
                LaunchSubagentSheet(model: self.model, parent: self.root)
            }
            .subagentChatPresentation(presenter: self.chatPresenter)
            .confirmationDialog(
                "Stop this subagent and its descendants?",
                isPresented: self.confirmStopBinding,
                titleVisibility: .visible,
                actions: { self.stopDialogActions })
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                self.messages
                self.summary
                self.timeline
            }
            .padding(.horizontal, OpenClawProMetric.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, OpenClawProMetric.bottomScrollInset)
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let message = self.model.treeError {
            AgentsHubErrorRow(message: message, retry: self.reload)
        }
        if let message = self.model.actionError {
            AgentsHubErrorRow(message: message, retry: nil)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let tree = self.model.tree {
            AgentsHubSummaryBar(
                total: tree.descendantCount,
                active: tree.activeDescendantCount,
                failed: tree.failedDescendantCount,
                isLive: self.isLive)
        }
    }

    /// Re-evaluates tile wording every 30 s (done -> napping) without a new Gateway call.
    private var timeline: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            self.rows(now: context.date)
        }
    }

    private func rows(now: Date) -> some View {
        let list: [FlatSubagentRow] = self.model.visibleRows
        return LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(list) { row in
                self.rowView(row, now: now)
            }
        }
        .openClawAnimation(value: list)
        .accessibilityElement(children: .contain)
    }

    private func rowView(_ row: FlatSubagentRow, now: Date) -> some View {
        let item: AgentTileItem = AgentTileFactory.item(
            for: row.node.session,
            isMain: row.depth == 0,
            now: now)
        return AgentGlassTreeRow(
            row: row,
            item: item,
            canStop: self.model.canStop,
            namespace: self.namespace,
            onOpen: self.openChat,
            onStop: self.requestStop,
            onDetails: self.openDetails,
            onToggle: self.toggle)
    }

    @ViewBuilder
    private var overlayState: some View {
        if self.model.tree == nil, self.model.isLoadingTree {
            ProgressView().accessibilityLabel(Text("Loading subagents"))
        } else if let tree = self.model.tree, tree.children.isEmpty, !self.model.isLoadingTree {
            ContentUnavailableView("No subagents", systemImage: "person.2.slash")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: self.close) {
                Label("Close", systemImage: "xmark")
                    .frame(minWidth: OpenClawHitTarget.minimum, minHeight: OpenClawHitTarget.minimum)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: self.openLaunch) {
                Label("Launch subagent", systemImage: "plus")
                    .frame(minWidth: OpenClawHitTarget.minimum, minHeight: OpenClawHitTarget.minimum)
            }
            .disabled(!self.model.canLaunch)
        }
    }

    // MARK: Stop dialog

    @ViewBuilder
    private var stopDialogActions: some View {
        Button("Stop", role: .destructive, action: self.confirmStopNow)
        Button("Cancel", role: .cancel, action: self.cancelStop)
    }

    // MARK: Actions

    private func close() {
        self.dismiss()
    }

    private func reload() {
        let target: OpenClawChatSessionEntry = self.root
        Task { await self.model.loadTree(root: target) }
    }

    private func openLaunch() {
        self.showLaunch = true
    }

    private func openChat(_ item: AgentTileItem) {
        self.chatPresenter.open(item.session.key)
    }

    private func openDetails(_ item: AgentTileItem) {
        self.detailNode = AgentTileFactory.node(for: item)
    }

    private func requestStop(_ item: AgentTileItem) {
        self.confirmStop = item
    }

    private func toggle(_ id: String) {
        self.model.toggle(id)
    }

    private func cancelStop() {
        self.confirmStop = nil
    }

    private func confirmStopNow() {
        guard let item = self.confirmStop else { return }
        self.confirmStop = nil
        let node: SubagentNode = AgentTileFactory.node(for: item)
        Task { await self.model.stop(node) }
    }
}
