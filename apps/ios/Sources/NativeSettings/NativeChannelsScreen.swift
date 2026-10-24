import Foundation
import OpenClawKit
import SwiftUI

/// One channel row, flattened from `channels.status`.
struct NativeChannelItem: Identifiable, Equatable {
    let id: String
    var label: String
    var systemImage: String
    var accountCount: Int
    var connectedCount: Int
    var configuredCount: Int
    var issueMessage: String?
    var lastError: String?
}

/// Gateway call for Channels. Verified: `channels.status` (params: probe?, timeoutMs?, channel?;
/// result: channelOrder, channelLabels, channelSystemImages?, channelAccounts, statusIssues?).
@MainActor
enum NativeChannelsLoader {
    static func load(_ appModel: NodeAppModel) async throws -> [NativeChannelItem] {
        let root: [String: Any] = try await NativeSettingsGateway.call(
            appModel: appModel,
            method: "channels.status",
            timeoutSeconds: 15)
        let order: [String] = (root["channelOrder"] as? [String]) ?? []
        let labels: [String: String] = (root["channelLabels"] as? [String: String]) ?? [:]
        let images: [String: String] = (root["channelSystemImages"] as? [String: String]) ?? [:]
        let accountsByChannel: [String: Any] = root.dict("channelAccounts") ?? [:]
        let issues: [[String: Any]] = root.array("statusIssues")

        var items: [NativeChannelItem] = []
        for channelId in order {
            let item: NativeChannelItem = Self.item(
                channelId: channelId,
                label: labels[channelId],
                image: images[channelId],
                accountsValue: accountsByChannel[channelId],
                issues: issues)
            items.append(item)
        }
        return items
    }

    private static func item(
        channelId: String,
        label: String?,
        image: String?,
        accountsValue: Any?,
        issues: [[String: Any]]) -> NativeChannelItem
    {
        let accounts: [[String: Any]] = (accountsValue as? [[String: Any]]) ?? []
        var connected: Int = 0
        var configured: Int = 0
        var lastError: String?
        for account in accounts {
            let isConnected: Bool = (account.bool("connected") ?? false) || (account.bool("running") ?? false)
            if isConnected { connected += 1 }
            if account.bool("configured") ?? false { configured += 1 }
            if lastError == nil {
                let error: String? = account.string("lastError")
                if let error, !error.isEmpty { lastError = error }
            }
        }
        var issueMessage: String?
        for issue in issues where issue.string("channel") == channelId {
            let message: String? = issue.string("message")
            if let message, !message.isEmpty {
                issueMessage = message
                break
            }
        }
        let resolvedLabel: String = label ?? channelId
        let resolvedImage: String = image ?? "bubble.left.and.bubble.right"
        return NativeChannelItem(
            id: channelId,
            label: resolvedLabel,
            systemImage: resolvedImage,
            accountCount: accounts.count,
            connectedCount: connected,
            configuredCount: configured,
            issueMessage: issueMessage,
            lastError: lastError)
    }
}

enum NativeChannelsPresentation {
    static func pill(_ item: NativeChannelItem) -> NativeSettingsPill {
        if item.issueMessage != nil || item.lastError != nil {
            return NativeSettingsPill(label: String(localized: "Needs attention"), tone: .warn)
        }
        if item.connectedCount > 0 {
            return NativeSettingsPill(label: String(localized: "Connected"), tone: .ok)
        }
        if item.configuredCount > 0 {
            return NativeSettingsPill(label: String(localized: "Configured"), tone: .muted)
        }
        return NativeSettingsPill(label: String(localized: "Not configured"), tone: .muted)
    }

    static func detail(_ item: NativeChannelItem) -> String? {
        if let issue = item.issueMessage { return issue }
        if let error = item.lastError { return error }
        if item.accountCount == 0 { return nil }
        let count: Int = item.accountCount
        let connected: Int = item.connectedCount
        return String(localized: "\(count) account(s), \(connected) connected")
    }
}

/// Native replacement for the Dashboard `/settings/channels` page (read-only status).
@MainActor
struct NativeChannelsScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var loader: NativeSettingsLoader<[NativeChannelItem]>
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false

    init(headerSidebarAction: OpenClawSidebarHeaderAction? = nil, embedded: Bool = false) {
        self.headerSidebarAction = headerSidebarAction
        self.embedded = embedded
        let load: NativeSettingsLoader<[NativeChannelItem]>.Load = { app in
            try await NativeChannelsLoader.load(app)
        }
        self._loader = State(initialValue: NativeSettingsLoader<[NativeChannelItem]>(load: load))
    }

    var body: some View {
        NativeSettingsPage(
            title: NativeSettingsDestination.channels.title,
            headerSidebarAction: self.headerSidebarAction,
            embedded: self.embedded)
        {
            self.content
        }
        .task { await self.loader.refresh(appModel: self.appModel, showSpinner: true) }
    }

    private var content: some View {
        NativeStateView(
            state: self.loader.state,
            isEmpty: { (items: [NativeChannelItem]) in items.isEmpty },
            emptyTitle: "No channels",
            emptyIcon: "bubble.left.and.bubble.right",
            retry: { await self.loader.refresh(appModel: self.appModel, showSpinner: true) })
        { (items: [NativeChannelItem]) in
            self.list(items)
        }
    }

    private func list(_ items: [NativeChannelItem]) -> some View {
        List {
            Section {
                ForEach(items) { item in
                    self.row(item)
                }
            } footer: {
                Text("Channel setup and login are managed in the Dashboard.")
                    .font(OpenClawType.footnote)
            }
        }
        .refreshable { await self.loader.refresh(appModel: self.appModel, showSpinner: false) }
    }

    private func row(_ item: NativeChannelItem) -> some View {
        let pill: NativeSettingsPill = NativeChannelsPresentation.pill(item)
        let detail: String? = NativeChannelsPresentation.detail(item)
        return NativeSettingsRow(
            title: item.label,
            detail: detail,
            systemImage: item.systemImage,
            tint: pill.tone.color,
            pill: pill)
    }
}
