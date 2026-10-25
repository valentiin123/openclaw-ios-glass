import Foundation
import Observation
import SwiftUI

/// One ClawHub search result, mapped from `skills.search`.
struct NativeSkillSearchResult: Identifiable, Equatable {
    let id: String
    var installRef: String
    var displayName: String
    var summary: String?
    var version: String?
    var isOfficial: Bool
    var isInstallOnly: Bool
    var isUnscanned: Bool
}

/// Parses `skills.search`. Verified shape (`SkillsSearchResultSchema`,
/// packages/gateway-protocol/src/schema/skills-search.ts): `{ results: [{ slug, registry, installRef,
/// displayName, summary?, version?, official?, installOnly?, trustState?, ... }] }`.
enum NativeSkillSearchParser {
    static func results(from root: [String: Any]) -> [NativeSkillSearchResult] {
        let entries: [[String: Any]] = root.array("results")
        var output: [NativeSkillSearchResult] = []
        for entry in entries {
            guard let installRef: String = entry.string("installRef") else { continue }
            let name: String = entry.string("displayName") ?? entry.string("slug") ?? installRef
            let summary: String? = entry.string("summary")
            let version: String? = entry.string("version")
            let official: Bool = entry.bool("official") ?? false
            let installOnly: Bool = entry.bool("installOnly") ?? false
            let unscanned: Bool = entry.string("trustState") != nil
            let item: NativeSkillSearchResult = NativeSkillSearchResult(
                id: installRef,
                installRef: installRef,
                displayName: name,
                summary: summary,
                version: version,
                isOfficial: official,
                isInstallOnly: installOnly,
                isUnscanned: unscanned)
            output.append(item)
        }
        return output
    }
}

@MainActor
@Observable
final class NativeSkillSearchModel {
    var state: NativeLoadState<[NativeSkillSearchResult]> = .idle
    private(set) var installingRefs: Set<String> = []
    private(set) var installedRefs: Set<String> = []
    var actionError: String?

    /// `skills.search` (operator.read): params `query?`, `limit?` (1...100).
    func search(query: String, appModel: NodeAppModel) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(String(localized: "The operator connection is offline."))
            return
        }
        let trimmed: String = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.state = .loading
        var params: [String: Any] = [:]
        params["limit"] = 30
        if !trimmed.isEmpty { params["query"] = trimmed }
        do {
            let root: [String: Any] = try await NativeSettingsGateway.call(
                appModel: appModel,
                method: "skills.search",
                params: params,
                timeoutSeconds: 20)
            let items: [NativeSkillSearchResult] = NativeSkillSearchParser.results(from: root)
            self.state = .loaded(items)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    /// `skills.install` (operator.admin), ClawHub variant: `source: "clawhub"`, `slug` = the `installRef`
    /// returned by `skills.search` (packages/gateway-protocol/src/schema/agents-models-skills.ts).
    func install(_ item: NativeSkillSearchResult, appModel: NodeAppModel) async {
        guard appModel.hasOperatorAdminScope else {
            self.actionError = String(localized: "Changing skills requires operator.admin access.")
            return
        }
        guard !self.installingRefs.contains(item.installRef) else { return }
        self.installingRefs.insert(item.installRef)
        self.actionError = nil
        defer { self.installingRefs.remove(item.installRef) }
        var params: [String: Any] = [:]
        params["source"] = "clawhub"
        params["slug"] = item.installRef
        do {
            _ = try await NativeSettingsGateway.call(
                appModel: appModel,
                method: "skills.install",
                params: params,
                timeoutSeconds: 90)
            self.installedRefs.insert(item.installRef)
        } catch is CancellationError {
            return
        } catch {
            self.actionError = error.localizedDescription
        }
    }
}

/// Search the ClawHub registry and install a skill on the Gateway.
/// Gateway methods: `skills.search`, `skills.install`
/// (src/gateway/methods/core-descriptors.ts, src/gateway/server-methods/skills.ts, skills-install.ts).
@MainActor
struct NativeSkillsSearchScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model: NativeSkillSearchModel = NativeSkillSearchModel()
    @State private var query: String = ""
    var embedded: Bool = true
    var onClose: (() -> Void)?

    var body: some View {
        NativeSettingsPage(
            title: String(localized: "Find skills"),
            embedded: self.embedded,
            onClose: self.onClose)
        {
            self.stateView
        }
        .searchable(text: self.$query, prompt: Text("Search ClawHub"))
        .onSubmit(of: .search) {
            Task { await self.model.search(query: self.query, appModel: self.appModel) }
        }
        .task { await self.model.search(query: "", appModel: self.appModel) }
    }

    private var stateView: some View {
        NativeStateView(
            state: self.model.state,
            isEmpty: { (items: [NativeSkillSearchResult]) -> Bool in items.isEmpty },
            emptyTitle: "No skills found",
            emptyIcon: "magnifyingglass",
            retry: { await self.model.search(query: self.query, appModel: self.appModel) })
        { (items: [NativeSkillSearchResult]) in
            self.list(items)
        }
    }

    private func list(_ items: [NativeSkillSearchResult]) -> some View {
        let canEdit: Bool = self.appModel.hasOperatorAdminScope
        return List {
            if let message = self.model.actionError {
                Section {
                    Label {
                        Text(verbatim: message)
                            .font(OpenClawType.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(OpenClawBrand.warn)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { (offset: Int, item: NativeSkillSearchResult) in
                    self.row(item, canEdit: canEdit)
                        .openClawEntrance(index: offset)
                }
            } footer: {
                if !canEdit {
                    NativeSettingsFooter("Changing skills requires operator.admin access.")
                }
            }
        }
        .openClawAnimation(value: self.model.installedRefs)
    }

    private func row(_ item: NativeSkillSearchResult, canEdit: Bool) -> some View {
        let isInstalling: Bool = self.model.installingRefs.contains(item.installRef)
        let isInstalled: Bool = self.model.installedRefs.contains(item.installRef)
        let pill: NativeSettingsPill? = self.pill(item, installing: isInstalling, installed: isInstalled)
        let detail: String? = self.detail(item)
        return NativeSettingsRow(
            title: item.displayName,
            detail: detail,
            systemImage: "sparkles",
            tint: OpenClawBrand.accent,
            pill: pill)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canEdit, !isInstalled {
                    self.installButton(item).disabled(isInstalling)
                }
            }
            .glassActionsMenu(copying: item.installRef) {
                if canEdit, !isInstalled {
                    self.installButton(item).disabled(isInstalling)
                }
            }
    }

    private func pill(_ item: NativeSkillSearchResult, installing: Bool, installed: Bool) -> NativeSettingsPill? {
        if installing {
            return NativeSettingsPill(label: String(localized: "Installing…"), tone: .muted)
        }
        if installed {
            return NativeSettingsPill(label: String(localized: "Installed"), tone: .ok)
        }
        if item.isUnscanned {
            return NativeSettingsPill(label: String(localized: "Not scanned"), tone: .warn)
        }
        if item.isOfficial {
            return NativeSettingsPill(label: String(localized: "Official"), tone: .accent)
        }
        return nil
    }

    private func detail(_ item: NativeSkillSearchResult) -> String? {
        let parts: [String?] = [item.summary, item.version]
        return NativeFormat.joined(parts)
    }

    private func installButton(_ item: NativeSkillSearchResult) -> some View {
        Button {
            Task { await self.model.install(item, appModel: self.appModel) }
        } label: {
            Label("Install", systemImage: "arrow.down.circle")
        }
        .tint(OpenClawBrand.accent)
    }
}
