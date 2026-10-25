import Observation
import SwiftUI

// MARK: - Store

/// Saved Gateways (multi-Gateway registry) with their live-connection flags.
/// Reads the keychain-backed registry and changes it through `GatewayConnectionController`,
/// so every change also reconciles the operator fleet.
@MainActor
@Observable
final class InstancesGatewayStore {
    typealias Entry = GatewaySettingsStore.GatewayRegistryEntry

    var entries: [Entry] = []
    var activeStableID: String?
    var connectedStableIDs: [String] = []
    var busyIDs: Set<String> = []
    var errorMessage: String?

    func reload() {
        let registry: GatewaySettingsStore.GatewayRegistry = GatewaySettingsStore.loadGatewayRegistry()
        self.entries = registry.entries.sorted { (a: Entry, b: Entry) -> Bool in
            let aSeen: Int = a.lastConnectedAtMs ?? 0
            let bSeen: Int = b.lastConnectedAtMs ?? 0
            return aSeen > bSeen
        }
        self.activeStableID = registry.activeStableID
        self.connectedStableIDs = registry.connectedStableIDs
    }

    func isActive(_ entry: Entry) -> Bool {
        GatewayStableIdentifier.matches(entry.stableID, self.activeStableID)
    }

    func isLive(_ entry: Entry) -> Bool {
        self.connectedStableIDs.contains { (id: String) -> Bool in
            GatewayStableIdentifier.matches(id, entry.stableID)
        }
    }

    func isBusy(_ entry: Entry) -> Bool {
        self.busyIDs.contains(entry.stableID)
    }

    func setLive(_ entry: Entry, enabled: Bool, controller: GatewayConnectionController) {
        guard !self.isBusy(entry) else { return }
        self.errorMessage = nil
        let ok: Bool = controller.setGatewayConnectionEnabled(stableID: entry.stableID, enabled: enabled)
        if !ok {
            self.errorMessage = String(localized: "Could not update the Gateway connection.")
        }
        self.reload()
    }

    func forget(_ entry: Entry, controller: GatewayConnectionController) async {
        guard !self.isBusy(entry) else { return }
        self.busyIDs.insert(entry.stableID)
        self.errorMessage = nil
        let ok: Bool = await controller.forgetGateway(stableID: entry.stableID)
        self.busyIDs.remove(entry.stableID)
        if !ok {
            self.errorMessage = String(localized: "Could not forget this Gateway.")
        }
        self.reload()
    }
}

// MARK: - Row

/// One saved Gateway. Status is a symbol + label, never color alone.
struct InstanceGatewayRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: GatewaySettingsStore.GatewayRegistryEntry
    let isActive: Bool
    let isLive: Bool
    let isBusy: Bool
    let onToggleLive: (Bool) -> Void

    var body: some View {
        let stacked: Bool = self.typeSize.isAccessibilitySize
        return HStack(alignment: .center, spacing: OpenClawSpace.md) {
            InstanceGlyphTile(
                symbol: self.entry.useTLS ? "lock.shield" : "server.rack",
                tint: self.isLive ? OpenClawBrand.ok : OpenClawBrand.textSecondary)
            VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
                Text(verbatim: self.entry.name)
                    .font(OpenClawType.headline)
                if let address = self.address {
                    Text(verbatim: address)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let seen = NativeFormat.relative(ms: self.entry.lastConnectedAtMs) {
                    Text(String(localized: "Last seen \(seen)"))
                        .font(OpenClawType.caption)
                        .foregroundStyle(.secondary)
                }
                if stacked {
                    self.pill
                }
            }
            Spacer(minLength: OpenClawSpace.sm)
            if !stacked {
                self.pill
            }
            if self.isBusy {
                ProgressView()
                    .accessibilityLabel(Text("Working"))
            }
        }
        .frame(minHeight: OpenClawHitTarget.minimum)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(self.isLive ? "Disconnect" : "Connect")) {
            self.onToggleLive(!self.isLive)
        }
    }

    private var address: String? {
        guard let host = self.entry.host, !host.isEmpty else { return nil }
        if let port = self.entry.port {
            return "\(host):\(port)"
        }
        return host
    }

    private var pill: some View {
        let label: String
        let tone: OpenClawStatusTone
        let symbol: String
        if self.isActive {
            label = String(localized: "Active")
            tone = .accent
            symbol = "checkmark.circle.fill"
        } else if self.isLive {
            label = String(localized: "Connected")
            tone = .ok
            symbol = "network"
        } else {
            label = String(localized: "Offline")
            tone = .muted
            symbol = "network.slash"
        }
        return OpenClawStatusPill(label: .verbatim(label), tone: tone, systemImage: symbol)
    }
}
