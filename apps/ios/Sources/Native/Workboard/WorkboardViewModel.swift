import Foundation
import Observation
import OpenClawKit
import SwiftUI

/// Loads Workboard boards and cards and moves cards between statuses.
///
/// Methods (plugin "workboard", handlers NOT present in the source tree):
/// - workboard.boards.list {}                         -> { boards: [...] }      (seen in scripts/perf/workboard-read-measure.ts)
/// - workboard.cards.list { boardId }                 -> { cards: [...] }       (same script)
/// - workboard.cards.update { id, patch: { status } } -> any                    (same script)
/// The required scope of these plugin methods is not declared in core-descriptors.ts.
/// `operator.write` is ASSUMED for updates; the action is also gated on the Gateway advertising the method.
@MainActor
@Observable
final class WorkboardViewModel {
    var state: NativeLoadState<WorkboardContent> = .idle
    var access: NativeOperatorAccess = .none
    var busyCardIds: Set<String> = []
    var actionError: String?
    var selectedBoardId: String?

    static let methods: [String] = [
        "workboard.boards.list",
        "workboard.cards.list",
        "workboard.cards.update",
    ]

    /// ASSUMED scope for card mutations (plugin descriptors unavailable).
    static let writeScope: String = "operator.write"

    var canMove: Bool {
        self.access.allows(method: "workboard.cards.update", scope: Self.writeScope)
    }

    func isBusy(_ cardId: String) -> Bool {
        self.busyCardIds.contains(cardId)
    }

    // MARK: - Loading

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(String(localized: "The operator connection is offline."))
            return
        }
        if showSpinner { self.state = .loading }

        let loaded: NativeOperatorAccess = await NativeOperatorAccess.load(
            appModel: appModel, methods: Self.methods)
        self.access = loaded

        do {
            let boardsObj: Any = try await NativeGateway.request(
                appModel: appModel, method: "workboard.boards.list")
            let boardsRoot: [String: Any] = (boardsObj as? [String: Any]) ?? [:]
            let boards: [WorkboardBoard] = boardsRoot.array("boards").compactMap(WorkboardBoard.parse)
            let selected: String? = self.resolveSelection(boards: boards)
            self.selectedBoardId = selected

            var content = WorkboardContent(
                boards: boards,
                selectedBoardId: selected,
                cards: [],
                statusOrder: WorkboardStatusInfo.defaultOrder,
                hasMoreCards: false,
                cardsError: nil)

            if let selected {
                await self.loadCards(appModel: appModel, boardId: selected, into: &content)
            }
            self.state = .loaded(content)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    func select(boardId: String, appModel: NodeAppModel) async {
        guard boardId != self.selectedBoardId else { return }
        self.selectedBoardId = boardId
        await self.load(appModel: appModel, showSpinner: true)
    }

    private func resolveSelection(boards: [WorkboardBoard]) -> String? {
        if let current = self.selectedBoardId, boards.contains(where: { $0.id == current }) {
            return current
        }
        let active: WorkboardBoard? = boards.first(where: { !$0.archived })
        return active?.id ?? boards.first?.id
    }

    private func loadCards(
        appModel: NodeAppModel,
        boardId: String,
        into content: inout WorkboardContent) async
    {
        do {
            let params: String = NativeJSON.string(["boardId": boardId])
            let obj: Any = try await NativeGateway.request(
                appModel: appModel, method: "workboard.cards.list", paramsJSON: params)
            let root: [String: Any] = (obj as? [String: Any]) ?? [:]
            content.cards = root.array("cards").compactMap(WorkboardCardItem.parse)
            content.hasMoreCards = root.dict("nextCursor") != nil
            // `statuses` is part of WorkboardListResult in the contract; fall back to the default order.
            if let statuses = root["statuses"] as? [String], !statuses.isEmpty {
                content.statusOrder = statuses
            }
        } catch is CancellationError {
            return
        } catch {
            content.cardsError = error.localizedDescription
        }
    }

    // MARK: - Actions

    func move(card: WorkboardCardItem, to status: String, appModel: NodeAppModel) async {
        guard self.canMove, status != card.status, !self.busyCardIds.contains(card.id) else { return }
        self.busyCardIds.insert(card.id)
        self.actionError = nil
        let patch: [String: Any] = ["status": status]
        let params: [String: Any] = ["id": card.id, "patch": patch]
        do {
            _ = try await NativeGateway.request(
                appModel: appModel,
                method: "workboard.cards.update",
                paramsJSON: NativeJSON.string(params))
        } catch is CancellationError {
            self.busyCardIds.remove(card.id)
            return
        } catch {
            self.actionError = error.localizedDescription
        }
        self.busyCardIds.remove(card.id)
        await self.load(appModel: appModel, showSpinner: false)
    }
}
