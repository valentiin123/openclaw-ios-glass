import Foundation
import Observation
import OpenClawKit
import SwiftUI

/// A destructive action waiting for the user's confirmation.
enum InstanceConfirmation: Equatable {
    case reject(requestId: String, name: String)
    case remove(deviceId: String, name: String)

    var title: String {
        switch self {
        case .reject: String(localized: "Reject this pairing request?")
        case .remove: String(localized: "Remove this device?")
        }
    }

    var message: String {
        switch self {
        case let .reject(_, name):
            String(localized: "\(name) will not be paired and must request access again.")
        case let .remove(_, name):
            String(localized: "\(name) will be disconnected and unpaired. It must be approved again to reconnect.")
        }
    }

    var confirmLabel: String {
        switch self {
        case .reject: String(localized: "Reject")
        case .remove: String(localized: "Remove")
        }
    }

    var action: InstanceAction {
        switch self {
        case let .reject(requestId, _): .reject(requestId: requestId)
        case let .remove(deviceId, _): .remove(deviceId: deviceId)
        }
    }
}

@MainActor
@Observable
final class InstancesViewModel {
    var state: NativeLoadState<InstancesSnapshot> = .idle
    var access: NativeOperatorAccess = .none
    var busyKeys: Set<String> = []
    var actionError: String?

    var confirmation: InstanceConfirmation?
    var isConfirming: Bool = false

    var renameTarget: InstancePairedDevice?
    var renameText: String = ""
    var isRenaming: Bool = false

    /// Methods whose advertisement and scope gate the actions. Verified in core-descriptors.ts.
    static let allMethods: [String] = [
        "device.pair.list",
        "device.pair.approve",
        "device.pair.reject",
        "device.pair.remove",
        "device.pair.rename",
        "presence.query",
    ]

    static let pairingScope: String = "operator.pairing"

    // MARK: - Capabilities

    func canPerform(_ method: String) -> Bool {
        self.access.allows(method: method, scope: Self.pairingScope)
    }

    var canResolveRequests: Bool {
        self.canPerform("device.pair.approve") && self.canPerform("device.pair.reject")
    }

    var canRemove: Bool { self.canPerform("device.pair.remove") }
    var canRename: Bool { self.canPerform("device.pair.rename") }

    func isBusy(_ key: String) -> Bool {
        self.busyKeys.contains(key)
    }

    // MARK: - Rename / confirm

    var renameIsValid: Bool {
        let trimmed: String = self.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 64
    }

    func beginRename(_ device: InstancePairedDevice) {
        self.renameTarget = device
        self.renameText = device.name
        self.isRenaming = true
    }

    func beginConfirmation(_ confirmation: InstanceConfirmation) {
        self.confirmation = confirmation
        self.isConfirming = true
    }

    // MARK: - Loading

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(String(localized: "The operator connection is offline."))
            return
        }
        if showSpinner { self.state = .loading }

        let loaded: NativeOperatorAccess = await NativeOperatorAccess.load(
            appModel: appModel, methods: Self.allMethods)
        self.access = loaded
        // When the Gateway advertises no scopes we still try the reads (the server enforces);
        // only the actions stay disabled.
        let scopesKnown: Bool = !loaded.scopes.isEmpty

        var snapshot = InstancesSnapshot(
            pending: [], paired: [], presence: [], presenceTruncated: false,
            pairingError: nil, presenceError: nil)

        if !scopesKnown || loaded.hasScope(Self.pairingScope) {
            do {
                let obj: Any = try await NativeGateway.request(appModel: appModel, method: "device.pair.list")
                let root: [String: Any] = (obj as? [String: Any]) ?? [:]
                snapshot.pending = root.array("pending").compactMap(InstancePendingRequest.parse)
                let paired: [InstancePairedDevice] = root.array("paired").compactMap(InstancePairedDevice.parse)
                snapshot.paired = paired.sorted(by: Self.pairedOrder)
            } catch is CancellationError {
                return
            } catch {
                snapshot.pairingError = error.localizedDescription
            }
        } else {
            snapshot.pairingError = String(
                localized: "This connection lacks the operator.pairing scope, so pairing requests cannot be listed.")
        }

        if !scopesKnown || loaded.canRead {
            do {
                let obj: Any = try await NativeGateway.request(
                    appModel: appModel,
                    method: "presence.query",
                    paramsJSON: #"{"action":"list","include":["devices"]}"#)
                let root: [String: Any] = (obj as? [String: Any]) ?? [:]
                snapshot.presence = InstancePresenceDevice.parseAll(root)
                snapshot.presenceTruncated = (root.bool("truncated") == true)
                let status: String = root.string("status") ?? "ok"
                if status != "ok" {
                    snapshot.presenceError = root.string("message") ?? status
                }
            } catch is CancellationError {
                return
            } catch {
                snapshot.presenceError = error.localizedDescription
            }
        } else {
            snapshot.presenceError = String(
                localized: "This connection lacks the operator.read scope, so connected devices cannot be listed.")
        }

        self.state = .loaded(snapshot)
    }

    private static func pairedOrder(_ a: InstancePairedDevice, _ b: InstancePairedDevice) -> Bool {
        let aConnected: Bool = a.connected == true
        let bConnected: Bool = b.connected == true
        if aConnected != bConnected { return aConnected }
        let aSeen: Int = a.lastSeenAtMs ?? 0
        let bSeen: Int = b.lastSeenAtMs ?? 0
        return aSeen > bSeen
    }

    // MARK: - Actions

    func perform(_ action: InstanceAction, appModel: NodeAppModel) async {
        let key: String = action.busyKey
        guard !self.busyKeys.contains(key) else { return }
        self.busyKeys.insert(key)
        self.actionError = nil
        do {
            _ = try await NativeGateway.request(
                appModel: appModel,
                method: action.method,
                paramsJSON: NativeJSON.string(action.params))
        } catch is CancellationError {
            self.busyKeys.remove(key)
            return
        } catch {
            self.actionError = error.localizedDescription
        }
        self.busyKeys.remove(key)
        await self.load(appModel: appModel, showSpinner: false)
    }

    func confirmPending(appModel: NodeAppModel) async {
        guard let confirmation = self.confirmation else { return }
        self.confirmation = nil
        await self.perform(confirmation.action, appModel: appModel)
    }

    func submitRename(appModel: NodeAppModel) async {
        guard let target = self.renameTarget, self.renameIsValid else { return }
        let label: String = self.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.renameTarget = nil
        await self.perform(.rename(deviceId: target.id, label: label), appModel: appModel)
    }
}
