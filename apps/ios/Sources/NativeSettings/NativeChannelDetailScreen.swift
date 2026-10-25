import Foundation
import Observation
import SwiftUI

/// One account of a channel, mapped from `channels.status` -> `channelAccounts[channel][]`.
/// Verified fields (`ChannelAccountSnapshotSchema`): accountId, name?, enabled?, configured?, running?,
/// connected?, lastError?.
struct NativeChannelAccount: Identifiable, Equatable {
    let id: String
    var name: String
    var isRunning: Bool
    var isConnected: Bool
    var isConfigured: Bool
    var isEnabled: Bool
    var lastError: String?
}

/// Account operations. Verified in `core-descriptors.ts` (scope operator.admin) and
/// `ChannelsStartParamsSchema` / `ChannelsStopParamsSchema` / `ChannelsLogoutParamsSchema`:
/// params `channel` (required) + `accountId?`.
enum NativeChannelAction: Equatable {
    case start
    case stop
    case logout

    var method: String {
        switch self {
        case .start: "channels.start"
        case .stop: "channels.stop"
        case .logout: "channels.logout"
        }
    }
}

/// Target of an action: one account, or the whole channel when the Gateway reports no account.
struct NativeChannelTarget: Identifiable, Equatable {
    let id: String
    var accountId: String?
    var name: String
}

@MainActor
@Observable
final class NativeChannelActionModel {
    private(set) var isBusy: Bool = false
    private(set) var successCount: Int = 0
    var errorMessage: String?

    /// Returns `true` when the Gateway accepted the call. Gateway errors (for example
    /// "channel x does not support logout") are shown as received.
    func perform(
        _ action: NativeChannelAction,
        channel: String,
        accountId: String?,
        appModel: NodeAppModel) async -> Bool
    {
        guard appModel.isOperatorGatewayConnected else {
            self.errorMessage = NativeGateway.offlineMessage
            return false
        }
        guard appModel.hasOperatorAdminScope else {
            self.errorMessage = String(localized: "Changing channels requires operator.admin access.")
            return false
        }
        guard !self.isBusy else { return false }
        self.isBusy = true
        self.errorMessage = nil
        defer { self.isBusy = false }
        var params: [String: Any] = ["channel": channel]
        if let accountId {
            params["accountId"] = accountId
        }
        do {
            let root: [String: Any] = try await NativeSettingsGateway.call(
                appModel: appModel,
                method: action.method,
                params: params,
                timeoutSeconds: 30)
            if let message = Self.unconfirmedMessage(action, root: root) {
                self.errorMessage = message
                return false
            }
            self.successCount += 1
            return true
        } catch is CancellationError {
            return false
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    /// `channels.start` answers `started`, `channels.stop` answers `stopped` (Gateway handler).
    private static func unconfirmedMessage(_ action: NativeChannelAction, root: [String: Any]) -> String? {
        switch action {
        case .start:
            if root.bool("started") == false {
                return String(localized: "The Gateway did not confirm the change.")
            }
            return nil
        case .stop:
            if root.bool("stopped") == false {
                return String(localized: "The Gateway did not confirm the change.")
            }
            return nil
        case .logout:
            return nil
        }
    }
}

extension NativeChannelsPresentation {
    static func accountPill(_ account: NativeChannelAccount) -> NativeSettingsPill {
        if account.lastError != nil {
            return NativeSettingsPill(label: String(localized: "Needs attention"), tone: .warn)
        }
        if !account.isEnabled {
            return NativeSettingsPill(label: String(localized: "Disabled"), tone: .muted)
        }
        if account.isConnected {
            return NativeSettingsPill(label: String(localized: "Connected"), tone: .ok)
        }
        if account.isRunning {
            return NativeSettingsPill(label: String(localized: "Running"), tone: .ok)
        }
        if account.isConfigured {
            return NativeSettingsPill(label: String(localized: "Stopped"), tone: .muted)
        }
        return NativeSettingsPill(label: String(localized: "Not configured"), tone: .muted)
    }
}

/// Accounts of one channel with Start / Stop / Log out. Logout asks for confirmation first.
/// Rows live in the list: no overlay.
@MainActor
struct NativeChannelDetailScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var loader: NativeSettingsLoader<[NativeChannelItem]>
    @State private var actions: NativeChannelActionModel = NativeChannelActionModel()
    @State private var pendingLogout: NativeChannelTarget?
    let channelId: String
    let title: String

    init(channelId: String, title: String) {
        self.channelId = channelId
        self.title = title
        let wanted: String = channelId
        let load: NativeSettingsLoader<[NativeChannelItem]>.Load = { (app: NodeAppModel) async throws -> [NativeChannelItem] in
            let all: [NativeChannelItem] = try await NativeChannelsLoader.load(app)
            return all.filter { (item: NativeChannelItem) -> Bool in item.id == wanted }
        }
        self._loader = State(initialValue: NativeSettingsLoader<[NativeChannelItem]>(load: load))
    }

    var body: some View {
        NativeSettingsPage(title: self.title, embedded: true) {
            self.content
        }
        .task { await self.loader.refresh(appModel: self.appModel, showSpinner: true) }
    }

    private var content: some View {
        NativeStateView(
            state: self.loader.state,
            isEmpty: { (items: [NativeChannelItem]) -> Bool in items.isEmpty },
            emptyTitle: "No channels",
            emptyIcon: "bubble.left.and.bubble.right",
            retry: { await self.loader.refresh(appModel: self.appModel, showSpinner: true) })
        { (items: [NativeChannelItem]) in
            self.list(items)
        }
    }

    private func list(_ items: [NativeChannelItem]) -> some View {
        let canEdit: Bool = self.appModel.hasOperatorAdminScope
        let busy: Bool = self.actions.isBusy
        return List {
            if let message = self.actions.errorMessage {
                self.errorSection(message)
            }
            if busy {
                self.workingSection
            }
            if let item = items.first {
                self.itemSections(item, canEdit: canEdit, busy: busy)
            }
        }
        .refreshable { await self.loader.refresh(appModel: self.appModel, showSpinner: false) }
        .openClawAnimation(value: items)
        .openClawAnimation(value: busy)
        .sensoryFeedback(.success, trigger: self.actions.successCount)
        .sensoryFeedback(trigger: self.actions.errorMessage) { (_: String?, new: String?) -> SensoryFeedback? in
            new != nil ? .error : nil
        }
        .confirmationDialog(
            "Log out?",
            isPresented: self.logoutBinding,
            presenting: self.pendingLogout)
        { (target: NativeChannelTarget) in
            Button(role: .destructive) {
                self.run(.logout, target: target)
            } label: {
                Text("Log out")
                    .font(OpenClawType.body)
            }
        } message: { (_: NativeChannelTarget) in
            Text("The account is disconnected from the Gateway. You may need to sign in again.")
                .font(OpenClawType.body)
        }
    }

    private var logoutBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.pendingLogout != nil },
            set: { (newValue: Bool) in
                if !newValue { self.pendingLogout = nil }
            })
    }

    private func errorSection(_ message: String) -> some View {
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

    private var workingSection: some View {
        Section {
            HStack(spacing: OpenClawSpace.md) {
                ProgressView()
                Text("Working…")
                    .font(OpenClawType.body)
            }
            .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func itemSections(_ item: NativeChannelItem, canEdit: Bool, busy: Bool) -> some View {
        if item.accounts.isEmpty {
            let target: NativeChannelTarget = NativeChannelTarget(id: "channel", accountId: nil, name: item.label)
            Section {
                self.actionRows(target, isActive: nil, canEdit: canEdit, busy: busy)
            } header: {
                NativeSettingsVerbatimHeader(text: item.label)
            } footer: {
                self.footer(canEdit: canEdit)
            }
        } else {
            let lastIndex: Int = item.accounts.count - 1
            ForEach(Array(item.accounts.enumerated()), id: \.element.id) { (offset: Int, account: NativeChannelAccount) in
                self.accountSection(
                    item,
                    account: account,
                    isFirst: offset == 0,
                    isLast: offset == lastIndex,
                    canEdit: canEdit,
                    busy: busy)
            }
        }
    }

    private func accountSection(
        _ item: NativeChannelItem,
        account: NativeChannelAccount,
        isFirst: Bool,
        isLast: Bool,
        canEdit: Bool,
        busy: Bool) -> some View
    {
        let pill: NativeSettingsPill = NativeChannelsPresentation.accountPill(account)
        let idDetail: String? = account.name == account.id ? nil : account.id
        let detail: String? = account.lastError ?? idDetail
        let target: NativeChannelTarget = NativeChannelTarget(id: account.id, accountId: account.id, name: account.name)
        let isActive: Bool = account.isRunning || account.isConnected
        return Section {
            NativeSettingsRow(
                title: account.name,
                detail: detail,
                systemImage: item.systemImage,
                tint: pill.tone.color,
                pill: pill)
                .nativeSettingsCopyMenu(account.id)
            self.actionRows(target, isActive: isActive, canEdit: canEdit, busy: busy)
        } header: {
            if isFirst {
                NativeSettingsHeader("Accounts")
            }
        } footer: {
            if isLast {
                self.footer(canEdit: canEdit)
            }
        }
    }

    @ViewBuilder
    private func footer(canEdit: Bool) -> some View {
        if canEdit {
            NativeSettingsFooter("Start, stop or log out each account. Setup and login are managed in the Dashboard.")
        } else {
            NativeSettingsFooter("Changing channels requires operator.admin access.")
        }
    }

    @ViewBuilder
    private func actionRows(
        _ target: NativeChannelTarget,
        isActive: Bool?,
        canEdit: Bool,
        busy: Bool) -> some View
    {
        let locked: Bool = !canEdit || busy
        let alreadyRunning: Bool = isActive ?? false
        let alreadyStopped: Bool = !(isActive ?? true)
        let startOff: Bool = locked || alreadyRunning
        let stopOff: Bool = locked || alreadyStopped
        self.actionButton(
            title: "Start",
            systemImage: "play.circle",
            role: nil,
            disabled: startOff,
            identifier: "NativeSettings.Channels.Start.\(target.id)")
        {
            self.run(.start, target: target)
        }
        self.actionButton(
            title: "Stop",
            systemImage: "stop.circle",
            role: nil,
            disabled: stopOff,
            identifier: "NativeSettings.Channels.Stop.\(target.id)")
        {
            self.run(.stop, target: target)
        }
        self.actionButton(
            title: "Log out",
            systemImage: "rectangle.portrait.and.arrow.right",
            role: .destructive,
            disabled: locked,
            identifier: "NativeSettings.Channels.Logout.\(target.id)")
        {
            self.pendingLogout = target
        }
    }

    private func actionButton(
        title: LocalizedStringKey,
        systemImage: String,
        role: ButtonRole?,
        disabled: Bool,
        identifier: String,
        action: @escaping () -> Void) -> some View
    {
        Button(role: role, action: action) {
            Label {
                Text(title)
                    .font(OpenClawType.body)
            } icon: {
                Image(systemName: systemImage)
            }
            .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }

    private func run(_ action: NativeChannelAction, target: NativeChannelTarget) {
        Task {
            _ = await self.actions.perform(
                action,
                channel: self.channelId,
                accountId: target.accountId,
                appModel: self.appModel)
            await self.loader.refresh(appModel: self.appModel, showSpinner: false)
        }
    }
}
