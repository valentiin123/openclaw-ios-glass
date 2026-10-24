import Observation
import SwiftUI
import UIKit

/// One display row. Every list destination maps its Gateway JSON into this shape.
struct NativeRow: Identifiable, Equatable {
    let id: String
    let title: String
    var subtitle: String?
    var trailing: String?
    var systemImage: String
    var tint: Color = .secondary

    static func == (lhs: NativeRow, rhs: NativeRow) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.trailing == rhs.trailing
    }

    func matches(_ query: String) -> Bool {
        if self.title.localizedCaseInsensitiveContains(query) { return true }
        if let subtitle = self.subtitle, subtitle.localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    var copyText: String {
        var parts: [String] = [self.title]
        if let subtitle = self.subtitle { parts.append(subtitle) }
        return parts.joined(separator: "\n")
    }
}

@MainActor
@Observable
final class NativeListModel {
    var state: NativeLoadState<[NativeRow]> = .idle
    private(set) var footnote: String?

    typealias Loader = @MainActor (NodeAppModel) async throws -> (rows: [NativeRow], footnote: String?)
    private let loader: Loader

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(NativeGateway.offlineMessage)
            return
        }
        if showSpinner { self.state = .loading }
        do {
            let result = try await self.loader(appModel)
            self.footnote = result.footnote
            self.state = .loaded(result.rows)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }
}

/// Native replacement for a Dashboard list page: grouped list, search, refreshable, context menu.
struct NativeListScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model: NativeListModel
    @State private var search: String = ""
    let title: String
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    init(
        title: String,
        emptyTitle: LocalizedStringKey,
        emptyIcon: String,
        headerSidebarAction: OpenClawSidebarHeaderAction?,
        loader: @escaping NativeListModel.Loader)
    {
        self.title = title
        self.emptyTitle = emptyTitle
        self.emptyIcon = emptyIcon
        self.headerSidebarAction = headerSidebarAction
        self._model = State(initialValue: NativeListModel(loader: loader))
    }

    var body: some View {
        NavigationStack {
            NativeStateView(
                state: self.model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: self.emptyTitle,
                emptyIcon: self.emptyIcon,
                retry: { await self.model.load(appModel: self.appModel, showSpinner: true) })
            { rows in
                self.list(rows)
            }
            .nativeChrome(title: self.title, sidebar: self.headerSidebarAction)
            .searchable(text: self.$search, prompt: Text("Search"))
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
    }

    private func filtered(_ rows: [NativeRow]) -> [NativeRow] {
        let query: String = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return rows }
        return rows.filter { $0.matches(query) }
    }

    @ViewBuilder
    private func list(_ rows: [NativeRow]) -> some View {
        let visible: [NativeRow] = self.filtered(rows)
        List {
            Section {
                ForEach(visible) { row in
                    NativeRowView(row: row)
                        .contextMenu { self.menu(for: row) }
                }
            } footer: {
                if let footnote = self.model.footnote {
                    Text(verbatim: footnote)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await self.model.load(appModel: self.appModel, showSpinner: false) }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView.search(text: self.search)
            }
        }
    }

    @ViewBuilder
    private func menu(for row: NativeRow) -> some View {
        Button {
            UIPasteboard.general.string = row.copyText
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }
}

private struct NativeRowView: View {
    let row: NativeRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: self.row.systemImage)
                .foregroundStyle(self.row.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.row.title).font(OpenClawType.body)
                if let subtitle = self.row.subtitle {
                    Text(verbatim: subtitle)
                        .font(OpenClawType.subhead)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let trailing = self.row.trailing {
                Text(verbatim: trailing).font(OpenClawType.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
