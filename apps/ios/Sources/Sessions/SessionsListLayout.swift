import OpenClawChatUI
import SwiftUI

/// One titled block of the shell's session list (Pinned, a custom group, or recent sessions).
/// Nodes are already flattened and capped, so the view only iterates.
struct SessionsListSection: Identifiable, Equatable {
    let id: String
    let title: String
    let nodes: [ChatSessionSidebarModel.Node]
}

/// Pure projection of `ChatSessionSidebarModel.Section`s into the shell's list: pinned first,
/// then custom groups, then recent sessions. Same rules as the former sidebar
/// (`RootSidebar.sessionLayout`, `recentSessionCap`), kept free of view state.
struct SessionsListLayout: Equatable {
    /// Without a search query the recent block is capped, like the former sidebar.
    static let recentCap: Int = 20

    let sections: [SessionsListSection]

    var isEmpty: Bool {
        self.sections.isEmpty
    }

    static func make(
        from sections: [ChatSessionSidebarModel.Section],
        searchText: String) -> SessionsListLayout
    {
        let query: String = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching: Bool = !query.isEmpty
        var pinned: [SessionsListSection] = []
        var others: [SessionsListSection] = []
        for section in sections {
            var nodes: [ChatSessionSidebarModel.Node] = Self.flattened(section.nodes)
            if section.id == "recent", !isSearching {
                nodes = Array(nodes.prefix(Self.recentCap))
            }
            guard !nodes.isEmpty else { continue }
            let row: SessionsListSection = SessionsListSection(
                id: section.id,
                title: Self.title(for: section),
                nodes: nodes)
            if section.id == "pinned" {
                pinned.append(row)
            } else {
                others.append(row)
            }
        }
        return SessionsListLayout(sections: pinned + others)
    }

    static func flattened(_ nodes: [ChatSessionSidebarModel.Node]) -> [ChatSessionSidebarModel.Node] {
        nodes.flatMap { (node: ChatSessionSidebarModel.Node) -> [ChatSessionSidebarModel.Node] in
            [node] + Self.flattened(node.children)
        }
    }

    private static func title(for section: ChatSessionSidebarModel.Section) -> String {
        if section.id == "pinned" {
            return String(localized: "Pinned")
        }
        if section.id == "recent" {
            return String(localized: "Sessions")
        }
        return section.title ?? String(localized: "Sessions")
    }
}
