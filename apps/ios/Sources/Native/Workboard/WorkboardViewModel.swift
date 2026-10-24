import Foundation
import Observation
import OpenClawKit
import SwiftUI

/// Loads Workboard boards and cards and moves cards between statuses.
///
/// All methods belong to the bundled plugin "workboard" (disabled by default on the Gateway).
/// VERIFIED in extensions/workboard/src/gateway.ts:
/// - workboard.boards.list {}                              -> { boards: WorkboardBoardSummary[] }   scope operator.read
/// - workboard.cards.list { boardId? }                     -> { cards, statuses, nextCursor?, boards, revision }   scope operator.read
/// - workboard.cards.move { id, status, position?, expectedUpdatedAt? } -> WorkboardCard            scope operator.write
/// Sessions boards (kind "sessions") use workboard.sessionsBoard.* and are not shown here.
/// When the plugin is off, the Gateway answers `unknown method: <name>` (src/gateway/server-methods.ts).
@MainActor
@Observable
final class WorkboardViewModel {
    var state: NativeLoadState<WorkboardContent> = .idle
    var access: NativeOperatorAccess = .none
    var unavailable: WorkboardUnavailableReason?
    var busyCardIds: Set<String> = []
    var actionError: String?
    var selectedBoardId: String?

    static let listBoardsMethod: String = "workboard.boards.list"
    static let listCardsMethod: String = "workboard.cards.list"
    static let moveCardMethod: String = "workboard.cards.move"

    static let methods: [String] = [
        WorkboardViewModel.listBoardsMethod,
        WorkboardViewModel.listCardsMethod,
        WorkboardViewModel.moveCardMethod,
    ]

    /// Scope declared by the plugin for card mutations (WRITE_SCOPE in gateway.ts).
    static let writeScope: String = "operator.write"

    var canMove: Bool {
        self.access.allows(method: Self.moveCardMethod, scope: Self.writeScope)
    }

    func isBusy(_ cardId: String) -> Bool {
        self.busyCardIds.contains(cardId)
    }

    // MARK: - Loading

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.unavailable = nil
            self.state = .failed(String(localized: "The operator connection is offline."))
            return
        }
        if showSpinner { self.state = .loading }

        let loaded: NativeOperatorAccess = await NativeOperatorAccess.load(
            appModel: appModel, methods: Self.methods)
        self.access = loaded

        // The Gateway advertises plugin methods in its hello snapshot. Only trust a negative answer
        // when a core method is advertised too, so a Gateway without any advertisement still gets a real try.
        let advertised: Bool? = await Self.advertisesBoardsList(appModel: appModel)
        if advertised == false {
            self.unavailable = .notAdvertised
            self.state = .idle
            return
        }

        do {
            let boardsObj: Any = try await NativeGateway.request(
                appModel: appModel, method: Self.listBoardsMethod)
            let boardsRoot: [String: Any] = (boardsObj as? [String: Any]) ?? [:]
            let parsed: [WorkboardBoard] = boardsRoot.array("boards").compactMap(WorkboardBoard.parse)
            let boards: [WorkboardBoard] = parsed.filter { !$0.isSessionsBoard }
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
                let cardsOutcome: WorkboardCardsOutcome = await self.loadCards(
                    appModel: appModel, boardId: selected, into: &content)
                if cardsOutcome == .methodMissing {
                    self.unavailable = .unknownMethod
                    self.state = .idle
                    return
                }
            }
            self.unavailable = nil
            self.state = .loaded(content)
        } catch is CancellationError {
            return
        } catch {
            if WorkboardErrors.isUnknownMethod(error) {
                self.unavailable = .unknownMethod
                self.state = .idle
                return
            }
            self.unavailable = nil
            self.state = .failed(error.localizedDescription)
        }
    }

    func select(boardId: String, appModel: NodeAppModel) async {
        guard boardId != self.selectedBoardId else { return }
        self.selectedBoardId = boardId
        await self.load(appModel: appModel, showSpinner: true)
    }

    private static func advertisesBoardsList(appModel: NodeAppModel) async -> Bool? {
        let session = appModel.operatorSession
        guard let route = await session.currentRoute() else { return nil }
        let listed: Bool? = await session.supportsServerMethod(
            Self.listBoardsMethod, ifCurrentRoute: route)
        if listed == true { return true }
        let core: Bool? = await session.supportsServerMethod("sessions.list", ifCurrentRoute: route)
        if listed == false, core == true { return false }
        return nil
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
        into content: inout WorkboardContent) async -> WorkboardCardsOutcome
    {
        do {
            let params: String = NativeJSON.string(["boardId": boardId])
            let obj: Any = try await NativeGateway.request(
                appModel: appModel, method: Self.listCardsMethod, paramsJSON: params)
            let root: [String: Any] = (obj as? [String: Any]) ?? [:]
            content.cards = root.array("cards").compactMap(WorkboardCardItem.parse)
            content.hasMoreCards = root.dict("nextCursor") != nil
            // `statuses` is part of the list result; fall back to the contract order.
            let statuses: [String] = root.strings("statuses")
            if !statuses.isEmpty {
                content.statusOrder = statuses
            }
            return .loaded
        } catch is CancellationError {
            return .cancelled
        } catch {
            if WorkboardErrors.isUnknownMethod(error) {
                return .methodMissing
            }
            content.cardsError = error.localizedDescription
            return .failed
        }
    }

    // MARK: - Actions

    func move(card: WorkboardCardItem, to status: String, appModel: NodeAppModel) async {
        guard self.canMove, status != card.status, !self.busyCardIds.contains(card.id) else { return }
        self.busyCardIds.insert(card.id)
        self.actionError = nil
        var params: [String: Any] = ["id": card.id, "status": status]
        // Optimistic concurrency: the plugin rejects the move when the card changed meanwhile.
        if let updatedAt = card.updatedAtMs {
            params["expectedUpdatedAt"] = updatedAt
        }
        do {
            _ = try await NativeGateway.request(
                appModel: appModel,
                method: Self.moveCardMethod,
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

enum WorkboardCardsOutcome: Equatable {
    case loaded
    case failed
    case cancelled
    case methodMissing
}
