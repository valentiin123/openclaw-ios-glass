import SwiftUI

/// Native Workboard: board picker + cards grouped by status, move-to-status through a menu.
/// Content sits on opaque list surfaces; glass only comes from system bars and controls.
struct NativeWorkboardScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model = WorkboardViewModel()
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    var body: some View {
        NavigationStack {
            self.stateView
                .navigationTitle(self.navTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { self.toolbarContent }
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        .alert(
            String(localized: "Action failed"),
            isPresented: self.errorBinding,
            actions: { Button(String(localized: "OK"), role: .cancel) {} },
            message: { Text(verbatim: self.model.actionError ?? "") })
    }

    /// The board name replaces the generic title once a board is loaded.
    private var navTitle: String {
        if case let .loaded(content) = self.model.state, let name = content.selectedBoardName {
            return name
        }
        return self.title
    }

    // MARK: - State

    @ViewBuilder
    private var stateView: some View {
        if let reason = self.model.unavailable {
            WorkboardUnavailableView(
                reason: reason,
                retry: { await self.model.load(appModel: self.appModel, showSpinner: true) })
        } else {
            self.loadedStateView
        }
    }

    private var loadedStateView: some View {
        NativeStateView(
            state: self.model.state,
            isEmpty: { (content: WorkboardContent) -> Bool in content.boards.isEmpty },
            emptyTitle: "No Workboard boards yet",
            emptyIcon: "rectangle.3.group",
            retry: { await self.model.load(appModel: self.appModel, showSpinner: true) },
            content: { (content: WorkboardContent) -> WorkboardListContent in
                self.makeList(content)
            })
    }

    private func makeList(_ content: WorkboardContent) -> WorkboardListContent {
        WorkboardListContent(
            content: content,
            canMove: self.model.canMove,
            busyCardIds: self.model.busyCardIds,
            onMove: { (card: WorkboardCardItem, status: String) in
                Task { await self.model.move(card: card, to: status, appModel: self.appModel) }
            },
            onRefresh: { await self.model.load(appModel: self.appModel, showSpinner: false) })
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

    private var errorBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.model.actionError != nil },
            set: { newValue in
                if !newValue { self.model.actionError = nil }
            })
    }
}

// MARK: - Unavailable

/// Shown when the Workboard plugin is not active on the Gateway. No raw error text.
private struct WorkboardUnavailableView: View {
    let reason: WorkboardUnavailableReason
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "Workboard unavailable on this Gateway"), systemImage: "rectangle.3.group")
        } description: {
            Text(verbatim: self.detail)
        } actions: {
            Button(String(localized: "Check again")) { Task { await self.retry() } }
                .nativeGlassButton()
        }
    }

    private var detail: String {
        let base: String = String(localized: "The Workboard plugin is not enabled on the connected Gateway.")
        let hint: String = String(localized: "Enable the workboard plugin on the Gateway, then check again.")
        return base + " " + hint
    }
}

// MARK: - List

enum WorkboardFilter: Hashable {
    case all
    case active
    case done
}

struct WorkboardListContent: View {
    @State private var filter: WorkboardFilter = .all
    let content: WorkboardContent
    let canMove: Bool
    let busyCardIds: Set<String>
    let onMove: (WorkboardCardItem, String) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        List {
            if let cardsError = self.content.cardsError {
                Section {
                    NativeInlineNotice(message: cardsError)
                }
            }
            self.groupSections
            if self.content.hasMoreCards {
                Section {
                    NativeInlineNotice(
                        message: String(localized: "Only the first cards are shown. Open the Dashboard for the full board."),
                        systemImage: "ellipsis.circle")
                }
            }
        }
        .refreshable { await self.onRefresh() }
        .safeAreaInset(edge: .top, spacing: 0) {
            NativeSegmentedBar(segments: Self.segments, selection: self.$filter)
        }
        .openClawAnimation(value: self.filter)
    }

    private static let segments: [NativeSegment<WorkboardFilter>] = [
        NativeSegment(id: .all, title: String(localized: "All")),
        NativeSegment(id: .active, title: String(localized: "Active")),
        NativeSegment(id: .done, title: String(localized: "Done")),
    ]

    private var visibleGroups: [(status: String, cards: [WorkboardCardItem])] {
        switch self.filter {
        case .all: self.content.groups
        case .active: self.content.groups.filter { $0.status != "done" }
        case .done: self.content.groups.filter { $0.status == "done" }
        }
    }

    /// Next status in board order, if any. Drives the primary swipe action.
    private func nextStatus(after card: WorkboardCardItem) -> String? {
        guard let index = self.content.statusOrder.firstIndex(of: card.status) else { return nil }
        let next: Int = index + 1
        return next < self.content.statusOrder.count ? self.content.statusOrder[next] : nil
    }

    @ViewBuilder
    private func swipeButtons(_ card: WorkboardCardItem) -> some View {
        if self.canMove, !self.busyCardIds.contains(card.id) {
            if card.status != "done" {
                Button {
                    self.onMove(card, "done")
                } label: {
                    Label(String(localized: "Done"), systemImage: "checkmark.circle.fill")
                }
                .tint(OpenClawBrand.ok)
            }
            if let next = self.nextStatus(after: card), next != "done" {
                Button {
                    self.onMove(card, next)
                } label: {
                    Label(WorkboardStatusInfo.label(next), systemImage: WorkboardStatusInfo.systemImage(next))
                }
                .tint(OpenClawBrand.info)
            }
        }
    }

    @ViewBuilder
    private var groupSections: some View {
        if self.content.cards.isEmpty, self.content.cardsError == nil {
            Section {
                Text("No cards on this board.")
                    .font(OpenClawType.subhead)
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(self.visibleGroups, id: \.status) { group in
            self.groupSection(status: group.status, cards: group.cards)
        }
    }

    private func groupSection(status: String, cards: [WorkboardCardItem]) -> some View {
        Section {
            ForEach(cards) { card in
                self.row(card)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) { self.swipeButtons(card) }
            }
        } header: {
            WorkboardSectionHeader(status: status, count: cards.count)
        }
    }

    private func row(_ card: WorkboardCardItem) -> some View {
        let busy: Bool = self.busyCardIds.contains(card.id)
        return WorkboardCardRow(
            card: card,
            statuses: self.content.statusOrder,
            canMove: self.canMove,
            isBusy: busy,
            onMove: self.onMove)
    }
}

private struct WorkboardSectionHeader: View {
    let status: String
    let count: Int

    var body: some View {
        let label: String = WorkboardStatusInfo.label(self.status)
        let icon: String = WorkboardStatusInfo.systemImage(self.status)
        return HStack(spacing: 8) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(verbatim: label)
            Spacer(minLength: 8)
            Text(self.count, format: .number).monospacedDigit()
        }
        .font(OpenClawType.subheadSemiBold)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Row

private struct WorkboardCardRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let card: WorkboardCardItem
    let statuses: [String]
    let canMove: Bool
    let isBusy: Bool
    let onMove: (WorkboardCardItem, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            self.details
            Spacer(minLength: 4)
            self.trailing
        }
        .padding(.vertical, 4)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: self.card.title)
                .font(OpenClawType.body)
                .fixedSize(horizontal: false, vertical: true)
            if let notes = self.card.notes, !notes.isEmpty {
                Text(verbatim: notes)
                    .font(OpenClawType.subhead)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            self.metaLine
            self.labelsLine
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: self.accessibilitySummary))
    }

    private var metaLine: some View {
        let priorityText: String = WorkboardStatusInfo.priorityLabel(self.card.priority)
        let execution: String? = self.card.executionStatus?.capitalized
        let updated: String? = NativeFormat.relative(ms: self.card.updatedAtMs)
        let parts: [String?] = [priorityText, execution, updated]
        let line: String = NativeFormat.joined(parts) ?? priorityText
        return Text(verbatim: line)
            .font(OpenClawType.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    @ViewBuilder
    private var labelsLine: some View {
        if !self.card.labels.isEmpty {
            Text(verbatim: self.card.labels.joined(separator: ", "))
                .font(OpenClawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if self.isBusy {
            ProgressView()
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(Text("Moving card"))
        } else if self.canMove {
            self.moveMenu
        }
    }

    private var moveMenu: some View {
        Menu {
            ForEach(self.statuses, id: \.self) { status in
                self.moveButton(status)
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .nativeMinimumTapTarget()
        }
        .accessibilityLabel(Text("Move card"))
    }

    private func moveButton(_ status: String) -> some View {
        let text: String = WorkboardStatusInfo.label(status)
        let icon: String = WorkboardStatusInfo.systemImage(status)
        let isCurrent: Bool = status == self.card.status
        return Button {
            self.onMove(self.card, status)
        } label: {
            Label(text, systemImage: icon)
        }
        .disabled(isCurrent)
    }

    private var accessibilitySummary: String {
        let status: String = WorkboardStatusInfo.label(self.card.status)
        let priority: String = WorkboardStatusInfo.priorityLabel(self.card.priority)
        return "\(status), \(priority)"
    }
}
