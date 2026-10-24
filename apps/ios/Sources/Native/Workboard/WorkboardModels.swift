import Foundation

// Tolerant decoding of the Workboard plugin responses.
// VERIFIED: status/priority enums and the WorkboardCard shape (packages/workboard-contract/src/index.ts);
// `boards[]` with id/total/byStatus and `cards[]` with id/status (scripts/perf/workboard-read-measure.ts).
// NOT VERIFIED: the plugin handlers themselves (not present in the source tree), so every field is optional.

enum WorkboardStatusInfo {
    /// Order from WORKBOARD_STATUSES (contract).
    static let defaultOrder: [String] = [
        "triage", "backlog", "todo", "scheduled", "ready", "running", "review", "blocked", "done",
    ]

    static func label(_ status: String) -> String {
        switch status {
        case "triage": String(localized: "Triage")
        case "backlog": String(localized: "Backlog")
        case "todo": String(localized: "To do")
        case "scheduled": String(localized: "Scheduled")
        case "ready": String(localized: "Ready")
        case "running": String(localized: "Running")
        case "review": String(localized: "In review")
        case "blocked": String(localized: "Blocked")
        case "done": String(localized: "Done")
        default: status.capitalized
        }
    }

    /// Every status has its own symbol so state never relies on color alone.
    static func systemImage(_ status: String) -> String {
        switch status {
        case "triage": "tray.and.arrow.down"
        case "backlog": "tray.full"
        case "todo": "circle"
        case "scheduled": "calendar"
        case "ready": "checkmark.circle"
        case "running": "play.circle"
        case "review": "eye"
        case "blocked": "exclamationmark.octagon"
        case "done": "checkmark.circle.fill"
        default: "questionmark.circle"
        }
    }

    static func priorityLabel(_ priority: String) -> String {
        switch priority {
        case "low": String(localized: "Low priority")
        case "normal": String(localized: "Normal priority")
        case "high": String(localized: "High priority")
        case "urgent": String(localized: "Urgent")
        default: priority.capitalized
        }
    }

    static func prioritySystemImage(_ priority: String) -> String {
        switch priority {
        case "low": "arrow.down"
        case "high": "arrow.up"
        case "urgent": "exclamationmark.2"
        default: "equal"
        }
    }
}

struct WorkboardBoard: Identifiable, Equatable {
    let id: String
    let name: String
    let total: Int
    let archived: Bool

    static func parse(_ raw: [String: Any]) -> WorkboardBoard? {
        guard let id = raw.string("id"), !id.isEmpty else { return nil }
        let name: String = raw.string("name") ?? id
        let total: Int = raw.int("total") ?? 0
        let isArchived: Bool = raw.int("archivedAt") != nil
        return WorkboardBoard(id: id, name: name, total: total, archived: isArchived)
    }
}

struct WorkboardCardItem: Identifiable, Equatable {
    let id: String
    let title: String
    let notes: String?
    let status: String
    let priority: String
    let labels: [String]
    let agentId: String?
    let sourceUrl: String?
    let executionStatus: String?
    let updatedAtMs: Int?

    static func parse(_ raw: [String: Any]) -> WorkboardCardItem? {
        guard let id = raw.string("id"), !id.isEmpty else { return nil }
        let title: String = raw.string("title") ?? id
        let status: String = raw.string("status") ?? "backlog"
        let priority: String = raw.string("priority") ?? "normal"
        let labels: [String] = (raw["labels"] as? [String]) ?? []
        let execution: String? = raw.dict("execution")?.string("status")
        return WorkboardCardItem(
            id: id,
            title: title,
            notes: raw.string("notes"),
            status: status,
            priority: priority,
            labels: labels,
            agentId: raw.string("agentId"),
            sourceUrl: raw.string("sourceUrl"),
            executionStatus: execution,
            updatedAtMs: raw.int("updatedAt"))
    }
}

struct WorkboardContent {
    var boards: [WorkboardBoard]
    var selectedBoardId: String?
    var cards: [WorkboardCardItem]
    var statusOrder: [String]
    var hasMoreCards: Bool
    var cardsError: String?

    /// Cards grouped by status in board order; statuses without cards are omitted.
    var groups: [(status: String, cards: [WorkboardCardItem])] {
        var result: [(status: String, cards: [WorkboardCardItem])] = []
        var known = Set<String>()
        for status in self.statusOrder {
            known.insert(status)
            let matching: [WorkboardCardItem] = self.cards.filter { $0.status == status }
            if !matching.isEmpty { result.append((status: status, cards: matching)) }
        }
        // Unknown statuses (plugin may add custom ones) each get their own group, in first-seen order.
        var unknownOrder: [String] = []
        for card in self.cards where !known.contains(card.status) {
            if !unknownOrder.contains(card.status) { unknownOrder.append(card.status) }
        }
        for status in unknownOrder {
            let matching: [WorkboardCardItem] = self.cards.filter { $0.status == status }
            result.append((status: status, cards: matching))
        }
        return result
    }

    var selectedBoardName: String? {
        self.boards.first(where: { $0.id == self.selectedBoardId })?.name
    }
}
