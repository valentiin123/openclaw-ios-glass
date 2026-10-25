import Foundation
import Observation
import SwiftUI

/// One pending DM sender request, mapped from `channels.pairing.list`.
struct NativePairingRequest: Identifiable, Equatable {
    let id: String
    var channel: String
    var channelLabel: String
    var accountId: String
    var senderId: String
    var senderLabel: String
    var expiresAt: String?
    var notifySupported: Bool
}

/// Parses `channels.pairing.list`. Verified shape (`ChannelsPairingListResultSchema`,
/// packages/gateway-protocol/src/schema/channel-pairing.ts): `{ accounts, requests, commandOwnerConfigured, limits }`.
enum NativePairingParser {
    static func requests(from root: [String: Any]) -> [NativePairingRequest] {
        let entries: [[String: Any]] = root.array("requests")
        var result: [NativePairingRequest] = []
        for entry in entries {
            guard let requestId: String = entry.string("requestId") else { continue }
            guard let channel: String = entry.string("channel") else { continue }
            guard let accountId: String = entry.string("accountId") else { continue }
            let channelLabel: String = entry.string("channelLabel") ?? channel
            let senderId: String = entry.string("senderId") ?? ""
            let senderLabel: String = entry.string("senderLabel") ?? senderId
            let expiresAt: String? = entry.string("expiresAt")
            let notify: Bool = entry.bool("notifySupported") ?? false
            let item: NativePairingRequest = NativePairingRequest(
                id: requestId,
                channel: channel,
                channelLabel: channelLabel,
                accountId: accountId,
                senderId: senderId,
                senderLabel: senderLabel,
                expiresAt: expiresAt,
                notifySupported: notify)
            result.append(item)
        }
        return result
    }
}

@MainActor
@Observable
final class NativePairingModel {
    var state: NativeLoadState<[NativePairingRequest]> = .idle
    private(set) var pendingIds: Set<String> = []
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
                method: "channels.pairing.list")
            let items: [NativePairingRequest] = NativePairingParser.requests(from: root)
            self.state = .loaded(items)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    /// `channels.pairing.approve` params (verified): `channel`, `accountId`, `requestId`, `notify?`.
    func approve(_ request: NativePairingRequest, appModel: NodeAppModel) async {
        var params: [String: Any] = [:]
        params["channel"] = request.channel
        params["accountId"] = request.accountId
        params["requestId"] = request.id
        if request.notifySupported { params["notify"] = true }
        await self.perform(request, method: "channels.pairing.approve", params: params, appModel: appModel)
    }

    /// `channels.pairing.dismiss` params (verified): `channel`, `accountId`, `requestId`.
    func dismiss(_ request: NativePairingRequest, appModel: NodeAppModel) async {
        var params: [String: Any] = [:]
        params["channel"] = request.channel
        params["accountId"] = request.accountId
        params["requestId"] = request.id
        await self.perform(request, method: "channels.pairing.dismiss", params: params, appModel: appModel)
    }

    private func perform(
        _ request: NativePairingRequest,
        method: String,
        params: [String: Any],
        appModel: NodeAppModel) async
    {
        guard !self.pendingIds.contains(request.id) else { return }
        self.pendingIds.insert(request.id)
        self.actionError = nil
        defer { self.pendingIds.remove(request.id) }
        do {
            _ = try await NativeSettingsGateway.call(appModel: appModel, method: method, params: params)
            self.removeLocal(id: request.id)
        } catch is CancellationError {
            return
        } catch {
            self.actionError = error.localizedDescription
        }
    }

    private func removeLocal(id: String) {
        guard case let .loaded(items) = self.state else { return }
        let remaining: [NativePairingRequest] = items.filter { (item: NativePairingRequest) -> Bool in
            item.id != id
        }
        self.state = .loaded(remaining)
    }
}

/// Pending DM sender requests for pairing-policy channels: approve or dismiss.
/// Gateway methods: `channels.pairing.list`, `channels.pairing.approve`, `channels.pairing.dismiss`
/// (src/gateway/methods/core-descriptors.ts, src/gateway/server-methods/channel-pairing.ts).
@MainActor
struct NativeChannelPairingScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model: NativePairingModel = NativePairingModel()
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    var onClose: (() -> Void)?

    var body: some View {
        NativeSettingsPage(
            title: String(localized: "Pairing requests"),
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
            isEmpty: { (items: [NativePairingRequest]) -> Bool in items.isEmpty },
            emptyTitle: "No pending requests",
            emptyIcon: "person.crop.circle.badge.checkmark",
            retry: { await self.model.refresh(appModel: self.appModel, showSpinner: true) })
        { (items: [NativePairingRequest]) in
            self.list(items)
        }
    }

    private func list(_ items: [NativePairingRequest]) -> some View {
        List {
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
                ForEach(Array(items.enumerated()), id: \.element.id) { (offset: Int, item: NativePairingRequest) in
                    self.row(item)
                        .openClawEntrance(index: offset)
                }
            } footer: {
                NativeSettingsFooter("Swipe a request or press and hold it to approve or dismiss.")
            }
        }
        .refreshable { await self.model.refresh(appModel: self.appModel, showSpinner: false) }
    }

    private func row(_ item: NativePairingRequest) -> some View {
        let isPending: Bool = self.model.pendingIds.contains(item.id)
        let detail: String = item.channelLabel + " · " + item.accountId
        let pill: NativeSettingsPill? = isPending
            ? NativeSettingsPill(label: String(localized: "Working…"), tone: .muted)
            : nil
        return NativeSettingsRow(
            title: item.senderLabel,
            detail: detail,
            systemImage: "person.crop.circle.badge.questionmark",
            tint: OpenClawBrand.accent,
            pill: pill)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                self.approveButton(item).disabled(isPending)
                self.dismissButton(item).disabled(isPending)
            }
            .glassActionsMenu(copying: item.senderId) {
                self.approveButton(item).disabled(isPending)
                self.dismissButton(item).disabled(isPending)
            }
    }

    private func approveButton(_ item: NativePairingRequest) -> some View {
        Button {
            Task { await self.model.approve(item, appModel: self.appModel) }
        } label: {
            Label("Approve", systemImage: "checkmark.circle")
        }
        .tint(OpenClawBrand.ok)
    }

    private func dismissButton(_ item: NativePairingRequest) -> some View {
        Button(role: .destructive) {
            Task { await self.model.dismiss(item, appModel: self.appModel) }
        } label: {
            Label("Dismiss", systemImage: "xmark.circle")
        }
    }
}
