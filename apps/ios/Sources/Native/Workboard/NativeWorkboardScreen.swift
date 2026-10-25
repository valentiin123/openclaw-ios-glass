import SwiftUI
import UIKit

/// Native Workboard: summary tiles, glass status filter, cards grouped by status.
/// Chrome and controls use Liquid Glass; card content sits on quiet opaque surfaces.
/// Moving a card is gated by the advertised `workboard.cards.move` method and the write scope.
struct NativeWorkboardScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model = WorkboardViewModel()
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    var body: some View {
        NavigationStack {
            self.stateView
                .background { OpenClawProBackground() }
                .navigationTitle(self.navTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { self.toolbarContent }
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        .nativeErrorAlert(self.$model.actionError)
        .sensoryFeedback(.impact(weight: .light), trigger: self.model.busyCardIds)
    }

    /// The board name replaces the generic title once a board is loaded.
    private var navTitle: String {
        if case let .loaded(content) = self.model.state, let name = content.selectedBoardName {
            return name
        }
        return self.title
    }

    private func reload(spinner: Bool) async {
        await self.model.load(appModel: self.appModel, showSpinner: spinner)
    }

    // MARK: - State

    @ViewBuilder
    private var stateView: some View {
        if let reason = self.model.unavailable {
            NGUnavailableState(
                systemImage: "rectangle.3.group",
                title: String(localized: "Workboard unavailable on this Gateway"),
                message: self.unavailableMessage(reason),
                retry: { await self.reload(spinner: true) })
        } else {
            switch self.model.state {
            case .idle, .loading:
                NGSkeletonList()
            case let .failed(message):
                NGErrorState(message: message, retry: { await self.reload(spinner: true) })
            case let .loaded(content):
                if content.boards.isEmpty {
                    self.emptyBoards
                } else {
                    self.list(content)
                }
            }
        }
    }

    private func unavailableMessage(_ reason: WorkboardUnavailableReason) -> String {
        let base: String = String(localized: "The Workboard plugin is not enabled on the connected Gateway.")
        let hint: String = String(localized: "Enable the workboard plugin on the Gateway, then check again.")
        return base + " " + hint
    }

    private var emptyBoards: some View {
        OpenClawEmptyState(
            systemImage: "rectangle.3.group",
            title: "No Workboard boards yet",
            message: "Boards created on the Gateway show up here.")
        {
            Button {
                Task { await self.reload(spinner: true) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .nativeGlassButtonStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ content: WorkboardContent) -> some View {
        WorkboardListContent(
            content: content,
            canMove: self.model.canMove,
            busyCardIds: self.model.busyCardIds,
            onMove: { (card: WorkboardCardItem, status: String) in
                Task { await self.model.move(card: card, to: status, appModel: self.appModel) }
            },
            onRefresh: { await self.reload(spinner: false) })
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let headerSidebarAction {
            OpenClawSidebarToolbarItem(action: headerSidebarAction, placement: .topBarLeading)
        }
        ToolbarItem(placement: .topBarTrailing) {
            self.boardMenu
        }
    }

    @ViewBuilder
    private var boardMenu: some View {
        if case let .loaded(content) = self.model.state, content.boards.count > 1 {
            Menu {
                ForEach(content.boards) { board in
                    self.boardMenuButton(board: board, selectedId: content.selectedBoardId)
                }
            } label: {
                Label(String(localized: "Boards"), systemImage: "rectangle.3.group")
                    .nativeMinimumTapTarget()
            }
            .accessibilityLabel(Text("Choose board"))
        }
    }

    private func boardMenuButton(board: WorkboardBoard, selectedId: String?) -> some View {
        let isSelected: Bool = board.id == selectedId
        let icon: String = isSelected ? "checkmark" : "rectangle"
        return Button {
            Task { await self.model.select(boardId: board.id, appModel: self.appModel) }
        } label: {
            Label(board.name, systemImage: icon)
        }
    }
}

// MARK: - Status tint

enum WorkboardStatusTint {
    static func color(_ status: String) -> Color {
        switch status {
        case "done": OpenClawBrand.ok
        case "running": OpenClawBrand.info
        case "blocked": OpenClawBrand.danger
        case "review": OpenClawBrand.warn
        default: Color.secondary
        }
    }

    static func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": OpenClawBrand.danger
        case "high": OpenClawBrand.warn
        default: Color.secondary
        }
    }
}

// MARK: - List

struct WorkboardListContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: String = NGFilterID.all
    let content: WorkboardContent
    let canMove: Bool
    let busyCardIds: Set<String>
    let onMove: (WorkboardCardItem, String) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        List {
            if let cardsError = self.content.cardsError {
                NativeInlineNotice(message: cardsError)
                    .padding(14)
                    .ngCardSurface()
                    .ngCardRow()
            }
            if !self.content.cards.isEmpty {
                NGSummaryHeader(items: self.metrics)
                    .ngCardRow()
            }
            self.groupSections
            if self.content.hasMoreCards {
                NativeInlineNotice(
                    message: String(localized: "Only the first cards are shown. Open the Dashboard for the full board."),
                    systemImage: "ellipsis.circle")
                    .padding(14)
                    .ngCardRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .ngTopScrollEdge()
        .refreshable { await self.onRefresh() }
        .safeAreaInset(edge: .top, spacing: 0) {
            NGFilterBar(items: self.filterItems, selection: self.$filter)
        }
        .openClawAnimation(value: self.filter)
        .openClawAnimation(value: self.content.cards)
        .onChange(of: self.content.statusOrder) { _, _ in
            self.filter = NGFilterID.all
        }
    }

    // MARK: Derived

    private var metrics: [NGMetricItem] {
        let total: Int = self.content.cards.count
        let done: Int = self.content.cards.filter { $0.status == "done" }.count
        let blocked: Int = self.content.cards.filter { $0.status == "blocked" }.count
        let running: Int = self.content.cards.filter { $0.status == "running" }.count
        return [
            NGMetricItem(
                id: "total", value: total, label: String(localized: "Cards"),
                systemImage: "rectangle.stack"),
            NGMetricItem(
                id: "running", value: running, label: String(localized: "Running"),
                systemImage: "play.circle", tint: OpenClawBrand.info),
            NGMetricItem(
                id: "blocked", value: blocked, label: String(localized: "Blocked"),
                systemImage: "exclamationmark.octagon", tint: OpenClawBrand.danger),
            NGMetricItem(
                id: "done", value: done, label: String(localized: "Done"),
                systemImage: "checkmark.circle.fill", tint: OpenClawBrand.ok),
        ]
    }

    private var filterItems: [NGFilterBar.Item] {
        var items: [NGFilterBar.Item] = [
            NGFilterBar.Item(
                id: NGFilterID.all,
                title: String(localized: "All"),
                count: self.content.cards.count),
        ]
        for group in self.content.groups {
            items.append(NGFilterBar.Item(
                id: group.status,
                title: WorkboardStatusInfo.label(group.status),
                count: group.cards.count,
                systemImage: WorkboardStatusInfo.systemImage(group.status)))
        }
        return items
    }

    private var visibleGroups: [(status: String, cards: [WorkboardCardItem])] {
        if self.filter == NGFilterID.all { return self.content.groups }
        return self.content.groups.filter { $0.status == self.filter }
    }

    /// Next status in board order, if any. Drives the secondary swipe action.
    private func nextStatus(after card: WorkboardCardItem) -> String? {
        guard let index = self.content.statusOrder.firstIndex(of: card.status) else { return nil }
        let next: Int = index + 1
        return next < self.content.statusOrder.count ? self.content.statusOrder[next] : nil
    }

    // MARK: Sections

    @ViewBuilder
    private var groupSections: some View {
        if self.content.cards.isEmpty, self.content.cardsError == nil {
            OpenClawEmptyState(
                systemImage: "tray",
                title: "No cards on this board.",
                message: "Cards you add to this board appear here, grouped by status.")
                .ngCardRow()
        }
        ForEach(self.visibleGroups, id: \.status) { group in
            Section {
                ForEach(Array(group.cards.enumerated()), id: \.element.id) { (index: Int, card: WorkboardCardItem) in
                    self.row(card, index: index)
                }
            } header: {
                WorkboardSectionHeader(
                    status: group.status,
                    count: group.cards.count,
                    acceptsDrop: self.canMove,
                    onDropCardIds: { (ids: [String]) -> Bool in
                        self.drop(ids: ids, to: group.status)
                    })
            }
        }
    }

    /// Moves the first dropped card that exists on this board and is not already in `status`.
    private func drop(ids: [String], to status: String) -> Bool {
        guard self.canMove else { return false }
        for id in ids {
            guard let card = self.content.cards.first(where: { $0.id == id }) else { continue }
            guard card.status != status, !self.busyCardIds.contains(card.id) else { continue }
            self.onMove(card, status)
            return true
        }
        return false
    }

    private func row(_ card: WorkboardCardItem, index: Int) -> some View {
        let busy: Bool = self.busyCardIds.contains(card.id)
        return WorkboardCardView(
            card: card,
            statuses: self.content.statusOrder,
            canMove: self.canMove,
            isBusy: busy,
            onMove: self.onMove)
            .openClawEntrance(index: index)
            .ngCardRow()
            .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
            .workboardDraggable(card.id, enabled: self.canMove && !busy)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) { self.trailingSwipe(card) }
            .swipeActions(edge: .leading, allowsFullSwipe: false) { self.leadingSwipe(card) }
            .contextMenu { self.menu(card) }
    }

    // MARK: Gestures

    @ViewBuilder
    private func trailingSwipe(_ card: WorkboardCardItem) -> some View {
        if self.canMove, !self.busyCardIds.contains(card.id), card.status != "done" {
            Button {
                self.onMove(card, "done")
            } label: {
                Label(String(localized: "Done"), systemImage: "checkmark.circle.fill")
            }
            .tint(OpenClawBrand.ok)
        }
    }

    @ViewBuilder
    private func leadingSwipe(_ card: WorkboardCardItem) -> some View {
        if self.canMove, !self.busyCardIds.contains(card.id), let next = self.nextStatus(after: card) {
            Button {
                self.onMove(card, next)
            } label: {
                Label(WorkboardStatusInfo.label(next), systemImage: WorkboardStatusInfo.systemImage(next))
            }
            .tint(OpenClawBrand.info)
        }
    }

    @ViewBuilder
    private func menu(_ card: WorkboardCardItem) -> some View {
        if self.canMove, !self.busyCardIds.contains(card.id) {
            Menu {
                ForEach(self.content.statusOrder, id: \.self) { status in
                    Button {
                        self.onMove(card, status)
                    } label: {
                        Label(
                            WorkboardStatusInfo.label(status),
                            systemImage: WorkboardStatusInfo.systemImage(status))
                    }
                    .disabled(status == card.status)
                }
            } label: {
                Label(String(localized: "Move to"), systemImage: "arrow.right.circle")
            }
        }
        Button {
            UIPasteboard.general.string = card.title
        } label: {
            Label(String(localized: "Copy title"), systemImage: "textformat")
        }
        Button {
            UIPasteboard.general.string = card.id
        } label: {
            Label(String(localized: "Copy ID"), systemImage: "doc.on.doc")
        }
        if let source = card.sourceUrl, !source.isEmpty {
            Button {
                UIPasteboard.general.string = source
            } label: {
                Label(String(localized: "Copy link"), systemImage: "link")
            }
        }
    }
}

private extension View {
    /// Long-press drag of a card id, only when moving is allowed.
    @ViewBuilder
    func workboardDraggable(_ id: String, enabled: Bool) -> some View {
        if enabled {
            self.draggable(id)
        } else {
            self
        }
    }
}

private struct WorkboardSectionHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted: Bool = false
    let status: String
    let count: Int
    let acceptsDrop: Bool
    let onDropCardIds: ([String]) -> Bool

    var body: some View {
        self.header
            .ngStickyHeader()
            .background {
                if self.isTargeted {
                    Capsule()
                        .fill(WorkboardStatusTint.color(self.status).opacity(0.18))
                        .padding(.horizontal, 6)
                        .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
                }
            }
            .openClawAnimation(value: self.isTargeted)
            .dropDestination(for: String.self) { (ids: [String], _: CGPoint) -> Bool in
                guard self.acceptsDrop else { return false }
                return self.onDropCardIds(ids)
            } isTargeted: { (targeted: Bool) -> Void in
                self.isTargeted = targeted && self.acceptsDrop
            }
            .sensoryFeedback(.selection, trigger: self.isTargeted)
    }

    private var header: some View {
        let label: String = WorkboardStatusInfo.label(self.status)
        let icon: String = WorkboardStatusInfo.systemImage(self.status)
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(WorkboardStatusTint.color(self.status))
                .accessibilityHidden(true)
            Text(verbatim: label)
            Spacer(minLength: 8)
            Text(self.count, format: .number).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(OpenClawType.subheadSemiBold)
        .textCase(nil)
        .padding(.horizontal, OpenClawProMetric.pagePadding)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Card

private struct WorkboardCardView: View {
    let card: WorkboardCardItem
    let statuses: [String]
    let canMove: Bool
    let isBusy: Bool
    let onMove: (WorkboardCardItem, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NGIconBadge(
                systemImage: WorkboardStatusInfo.systemImage(self.card.status),
                tint: WorkboardStatusTint.color(self.card.status))
            self.details
            if self.isBusy {
                ProgressView()
                    .accessibilityLabel(Text("Moving card"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCardSurface()
        .opacity(self.isBusy ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: self.accessibilitySummary))
        .accessibilityActions {
            if self.canMove, !self.isBusy {
                ForEach(self.statuses, id: \.self) { status in
                    if status != self.card.status {
                        Button(WorkboardStatusInfo.label(status)) {
                            self.onMove(self.card, status)
                        }
                    }
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: self.card.title)
                .font(OpenClawType.body)
                .fixedSize(horizontal: false, vertical: true)
            if let notes = self.card.notes, !notes.isEmpty {
                Text(verbatim: notes)
                    .font(OpenClawType.subhead)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            self.pills
            self.labelsRow
            self.footer
        }
    }

    private var pills: some View {
        NGFlowLayout(spacing: 6) {
            NGPill(
                text: WorkboardStatusInfo.label(self.card.status),
                systemImage: WorkboardStatusInfo.systemImage(self.card.status),
                tint: WorkboardStatusTint.color(self.card.status))
            if self.card.priority != "normal" {
                NGPill(
                    text: WorkboardStatusInfo.priorityLabel(self.card.priority),
                    systemImage: WorkboardStatusInfo.prioritySystemImage(self.card.priority),
                    tint: WorkboardStatusTint.priorityColor(self.card.priority))
            }
            if let execution = self.card.executionStatus, !execution.isEmpty {
                NGPill(
                    text: NativeFormat.humanized(execution).capitalized,
                    systemImage: "bolt.horizontal",
                    tint: OpenClawBrand.info)
            }
        }
    }

    @ViewBuilder
    private var labelsRow: some View {
        if !self.card.labels.isEmpty {
            Text(verbatim: self.card.labels.map { "#" + $0 }.joined(separator: " "))
                .font(OpenClawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var footer: some View {
        let updated: String? = NativeFormat.relative(ms: self.card.updatedAtMs)
        if let line = NativeFormat.joined([self.card.agentId, updated]) {
            Text(verbatim: line)
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var accessibilitySummary: String {
        let status: String = WorkboardStatusInfo.label(self.card.status)
        let priority: String = WorkboardStatusInfo.priorityLabel(self.card.priority)
        return "\(status), \(priority)"
    }
}
