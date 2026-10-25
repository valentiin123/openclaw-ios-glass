import Foundation
import Observation
import SwiftUI

/// One installed skill, mapped tolerantly from a `skills.status` entry.
struct NativeSkillItem: Identifiable, Equatable {
    let id: String
    var name: String
    var detail: String?
    var emoji: String?
    var source: String?
    var isDisabled: Bool
    var isEligible: Bool
    var isBlocked: Bool
    var missingCount: Int
}

/// Parses `skills.status`. Verified shape (`SkillsStatusReport` in OpenClawKit):
/// `{ workspaceDir, managedSkillsDir, skills: [SkillStatus] }`.
enum NativeSkillsParser {
    static func items(from root: [String: Any]) -> [NativeSkillItem] {
        let entries: [[String: Any]] = root.array("skills")
        var result: [NativeSkillItem] = []
        for entry in entries {
            guard let key: String = entry.string("skillKey") else { continue }
            let name: String = entry.string("name") ?? key
            let detail: String? = entry.string("description")
            let emoji: String? = entry.string("emoji")
            let source: String? = entry.string("source")
            let isDisabled: Bool = entry.bool("disabled") ?? false
            let isEligible: Bool = entry.bool("eligible") ?? true
            let allowlistBlocked: Bool = entry.bool("blockedByAllowlist") ?? false
            let platformBlocked: Bool = entry.bool("platformIncompatible") ?? false
            let isBlocked: Bool = allowlistBlocked || platformBlocked
            let missing: Int = Self.missingCount(entry.dict("missing"))
            let item: NativeSkillItem = NativeSkillItem(
                id: key,
                name: name,
                detail: detail,
                emoji: emoji,
                source: source,
                isDisabled: isDisabled,
                isEligible: isEligible,
                isBlocked: isBlocked,
                missingCount: missing)
            result.append(item)
        }
        result.sort { (lhs: NativeSkillItem, rhs: NativeSkillItem) -> Bool in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return result
    }

    static func missingCount(_ missing: [String: Any]?) -> Int {
        guard let missing else { return 0 }
        let keys: [String] = ["bins", "anyBins", "env", "config", "os"]
        var total: Int = 0
        for key in keys {
            let values: [Any] = (missing[key] as? [Any]) ?? []
            total += values.count
        }
        return total
    }
}

@MainActor
@Observable
final class NativeSkillsModel {
    var state: NativeLoadState<[NativeSkillItem]> = .idle
    private(set) var pendingKeys: Set<String> = []
    var actionError: String?

    func refresh(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(String(localized: "The operator connection is offline."))
            return
        }
        if showSpinner { self.state = .loading }
        do {
            let root: [String: Any] = try await NativeSettingsGateway.call(
                appModel: appModel,
                method: "skills.status")
            let items: [NativeSkillItem] = NativeSkillsParser.items(from: root)
            self.state = .loaded(items)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    /// `skills.update` is verified in the Gateway registry (operator.admin) with `skillKey` + `enabled`.
    func setEnabled(_ enabled: Bool, for item: NativeSkillItem, appModel: NodeAppModel) async {
        guard appModel.hasOperatorAdminScope else {
            self.actionError = String(localized: "Changing skills requires operator.admin access.")
            return
        }
        guard !self.pendingKeys.contains(item.id) else { return }
        self.pendingKeys.insert(item.id)
        self.actionError = nil
        defer { self.pendingKeys.remove(item.id) }
        do {
            let params: [String: Any] = ["skillKey": item.id, "enabled": enabled]
            _ = try await NativeSettingsGateway.call(
                appModel: appModel,
                method: "skills.update",
                params: params)
            self.applyLocal(enabled: enabled, key: item.id)
        } catch is CancellationError {
            return
        } catch {
            self.actionError = error.localizedDescription
        }
    }

    private func applyLocal(enabled: Bool, key: String) {
        guard case let .loaded(items) = self.state else { return }
        var updated: [NativeSkillItem] = items
        guard let index: Int = updated.firstIndex(where: { (candidate: NativeSkillItem) -> Bool in
            candidate.id == key
        }) else { return }
        updated[index].isDisabled = !enabled
        self.state = .loaded(updated)
    }
}

enum NativeSkillsPresentation {
    static func pill(_ item: NativeSkillItem) -> NativeSettingsPill? {
        if item.isDisabled {
            return NativeSettingsPill(label: String(localized: "Off"), tone: .muted)
        }
        if item.isBlocked {
            return NativeSettingsPill(label: String(localized: "Blocked"), tone: .warn)
        }
        if !item.isEligible || item.missingCount > 0 {
            return NativeSettingsPill(label: String(localized: "Needs setup"), tone: .warn)
        }
        // "Ready" is the quiet default: no pill, so only exceptions draw the eye.
        return nil
    }

    static func matches(_ item: NativeSkillItem, query: String) -> Bool {
        let trimmed: String = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let inName: Bool = item.name.localizedCaseInsensitiveContains(trimmed)
        let inDetail: Bool = (item.detail ?? "").localizedCaseInsensitiveContains(trimmed)
        return inName || inDetail
    }
}

/// Native replacement for the Dashboard `/skills` page: list + enable/disable.
/// Swipe toggles a skill, long press copies its key.
/// Not reproduced: ClawHub search/install, uploads, API key and env editing.
@MainActor
struct NativeSkillsScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model: NativeSkillsModel = NativeSkillsModel()
    @State private var searchText: String = ""
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    var onClose: (() -> Void)?

    var body: some View {
        NativeSettingsPage(
            title: NativeSettingsDestination.skills.title,
            headerSidebarAction: self.headerSidebarAction,
            embedded: self.embedded,
            onClose: self.onClose)
        {
            self.stateView
        }
        .task { await self.model.refresh(appModel: self.appModel, showSpinner: true) }
    }

    private var stateView: some View {
        NativeStateView(
            state: self.model.state,
            isEmpty: { (items: [NativeSkillItem]) -> Bool in items.isEmpty },
            emptyTitle: "No skills installed",
            emptyIcon: "sparkles",
            retry: { await self.model.refresh(appModel: self.appModel, showSpinner: true) },
            content: { (items: [NativeSkillItem]) -> AnyView in
                AnyView(self.list(items))
            })
    }

    private func list(_ items: [NativeSkillItem]) -> some View {
        let query: String = self.searchText
        let visible: [NativeSkillItem] = items.filter { (item: NativeSkillItem) -> Bool in
            NativeSkillsPresentation.matches(item, query: query)
        }
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
            self.findSkillsSection
            Section {
                ForEach(Array(visible.enumerated()), id: \.element.id) { (offset: Int, item: NativeSkillItem) in
                    self.row(item)
                        .openClawEntrance(index: offset)
                }
            } footer: {
                if !canEdit {
                    NativeSettingsFooter("Changing skills requires operator.admin access.")
                }
            }
        }
        .searchable(text: self.$searchText)
        .refreshable { await self.model.refresh(appModel: self.appModel, showSpinner: false) }
        .openClawAnimation(value: visible.map { (item: NativeSkillItem) -> Bool in item.isDisabled })
        .sensoryFeedback(.selection, trigger: items.map { (item: NativeSkillItem) -> Bool in item.isDisabled })
        .sensoryFeedback(trigger: self.model.actionError) { (_: String?, new: String?) -> SensoryFeedback? in
            new != nil ? .error : nil
        }
    }

    /// ClawHub search + install (`skills.search`, `skills.install`). A real list section, not an overlay.
    private var findSkillsSection: some View {
        Section {
            NavigationLink {
                NativeSkillsSearchScreen(embedded: true)
            } label: {
                NativeSettingsRow(
                    title: String(localized: "Find skills"),
                    detail: String(localized: "Search ClawHub and install on the Gateway"),
                    systemImage: "magnifyingglass",
                    tint: OpenClawBrand.accent)
            }
            .accessibilityIdentifier("NativeSettings.Skills.Find")
        }
    }

    private func binding(for item: NativeSkillItem) -> Binding<Bool> {
        Binding<Bool>(
            get: { !item.isDisabled },
            set: { (newValue: Bool) in
                Task { await self.model.setEnabled(newValue, for: item, appModel: self.appModel) }
            })
    }

    private func row(_ item: NativeSkillItem) -> some View {
        let canEdit: Bool = self.appModel.hasOperatorAdminScope
        let isPending: Bool = self.model.pendingKeys.contains(item.id)
        let pill: NativeSettingsPill? = NativeSkillsPresentation.pill(item)
        let rowDetail: String? = item.detail
        return Toggle(isOn: self.binding(for: item)) {
            NativeSettingsRow(
                title: item.name,
                detail: rowDetail,
                systemImage: "sparkles",
                emoji: item.emoji,
                tint: .secondary,
                pill: pill)
        }
        .disabled(!canEdit || isPending)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                self.swipeToggle(item)
            }
        }
        .glassActionsMenu(copying: item.id) {
            if canEdit {
                self.swipeToggle(item)
                    .disabled(isPending)
            }
        }
    }

    private func swipeToggle(_ item: NativeSkillItem) -> some View {
        let enable: Bool = item.isDisabled
        return Button {
            Task { await self.model.setEnabled(enable, for: item, appModel: self.appModel) }
        } label: {
            if enable {
                Label("Enable", systemImage: "checkmark.circle")
            } else {
                Label("Disable", systemImage: "slash.circle")
            }
        }
        .tint(enable ? OpenClawBrand.ok : Color.gray)
    }
}
