import Foundation
import OpenClawKit
import SwiftUI

/// Read-only snapshot of the Gateway host and health.
/// Methods: `system.info` (operator.read, params `{}`) and `health` (operator.read, params `probe?`).
struct NativeGatewayStatusSummary: Equatable {
    var machineName: String
    var hostname: String
    var osLabel: String
    var arch: String
    var nodeVersion: String
    var lanAddress: String?
    var port: Int?
    var uptimeMs: Int
    var cpuCount: Int
    var memoryTotalBytes: Int
    var memoryFreeBytes: Int
    var diskTotalBytes: Int?
    var diskAvailableBytes: Int?
    var healthOK: Bool?
    var heartbeatSeconds: Int?
    var channelCount: Int?
}

@MainActor
enum NativeGatewayStatusLoader {
    static func summary(_ appModel: NodeAppModel) async throws -> NativeGatewayStatusSummary {
        let info: [String: Any] = try await NativeSettingsGateway.call(
            appModel: appModel,
            method: "system.info")
        let health: [String: Any]? = try? await NativeSettingsGateway.call(
            appModel: appModel,
            method: "health",
            timeoutSeconds: 8)

        let machineName: String = info.string("machineName") ?? ""
        let hostname: String = info.string("hostname") ?? ""
        let osLabel: String = info.string("osLabel") ?? ""
        let arch: String = info.string("arch") ?? ""
        let nodeVersion: String = info.string("nodeVersion") ?? ""
        let uptime: Int = info.int("uptimeMs") ?? 0
        let cpus: Int = info.int("cpuCount") ?? 0
        let memTotal: Int = info.int("memoryTotalBytes") ?? 0
        let memFree: Int = info.int("memoryFreeBytes") ?? 0

        var healthOK: Bool?
        var heartbeat: Int?
        var channels: Int?
        if let health {
            healthOK = health.bool("ok")
            heartbeat = health.int("heartbeatSeconds")
            let order: [String] = health.strings("channelOrder")
            channels = order.count
        }

        return NativeGatewayStatusSummary(
            machineName: machineName,
            hostname: hostname,
            osLabel: osLabel,
            arch: arch,
            nodeVersion: nodeVersion,
            lanAddress: info.string("lanAddress"),
            port: info.int("port"),
            uptimeMs: uptime,
            cpuCount: cpus,
            memoryTotalBytes: memTotal,
            memoryFreeBytes: memFree,
            diskTotalBytes: info.int("diskTotalBytes"),
            diskAvailableBytes: info.int("diskAvailableBytes"),
            healthOK: healthOK,
            heartbeatSeconds: heartbeat,
            channelCount: channels)
    }
}

/// Native Gateway status page: host identity, resources and health. Read-only.
@MainActor
struct NativeGatewayStatusScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var loader: NativeSettingsLoader<NativeGatewayStatusSummary>
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    var onClose: (() -> Void)?

    init(
        headerSidebarAction: OpenClawSidebarHeaderAction? = nil,
        embedded: Bool = false,
        onClose: (() -> Void)? = nil)
    {
        self.headerSidebarAction = headerSidebarAction
        self.embedded = embedded
        self.onClose = onClose
        let load: NativeSettingsLoader<NativeGatewayStatusSummary>.Load = { app in
            try await NativeGatewayStatusLoader.summary(app)
        }
        self._loader = State(initialValue: NativeSettingsLoader<NativeGatewayStatusSummary>(load: load))
    }

    var body: some View {
        NativeSettingsPage(
            title: String(localized: "Gateway status"),
            headerSidebarAction: self.headerSidebarAction,
            embedded: self.embedded,
            onClose: self.onClose)
        {
            self.list
        }
        .task { await self.loader.refresh(appModel: self.appModel, showSpinner: true) }
    }

    private var list: some View {
        List {
            Section {
                NativeSettingsInlineState(
                    state: self.loader.state,
                    retry: { await self.loader.refresh(appModel: self.appModel, showSpinner: true) },
                    content: { (summary: NativeGatewayStatusSummary) in
                        self.rows(summary)
                    })
            } footer: {
                NativeSettingsFooter("Values are read from the Gateway host. Pull to refresh.")
            }
        }
        .refreshable { await self.loader.refresh(appModel: self.appModel, showSpinner: false) }
    }

    @ViewBuilder
    private func rows(_ summary: NativeGatewayStatusSummary) -> some View {
        let notSet: String = String(localized: "Not set")
        let hostValue: String = Self.nonEmpty(summary.machineName, fallback: summary.hostname, notSet: notSet)
        let osValue: String = Self.nonEmpty(summary.osLabel, fallback: summary.arch, notSet: notSet)
        let nodeValue: String = Self.nonEmpty(summary.nodeVersion, fallback: "", notSet: notSet)
        let uptimeValue: String = NativeFormat.duration(ms: summary.uptimeMs)
        let cpuValue: String = summary.cpuCount.formatted()
        let memoryValue: String = Self.memoryText(total: summary.memoryTotalBytes, free: summary.memoryFreeBytes)
        let diskValue: String = Self.diskText(total: summary.diskTotalBytes, free: summary.diskAvailableBytes, notSet: notSet)
        let addressValue: String = Self.addressText(host: summary.lanAddress, port: summary.port, notSet: notSet)
        let healthPill: NativeSettingsPill? = Self.healthPill(summary.healthOK)
        let heartbeatValue: String = Self.heartbeatText(summary.heartbeatSeconds, notSet: notSet)
        let channelValue: String = summary.channelCount.map { (count: Int) -> String in count.formatted() } ?? notSet

        NativeSettingsRow(
            title: String(localized: "Health"),
            systemImage: "heart.text.square",
            tint: OpenClawBrand.accent,
            pill: healthPill)
        self.valueRow(title: String(localized: "Host"), value: hostValue, systemImage: "server.rack")
        self.valueRow(title: String(localized: "System"), value: osValue, systemImage: "desktopcomputer")
        self.valueRow(title: String(localized: "Address"), value: addressValue, systemImage: "network")
        self.valueRow(title: String(localized: "Node.js"), value: nodeValue, systemImage: "chevron.left.forwardslash.chevron.right")
        self.valueRow(title: String(localized: "Uptime"), value: uptimeValue, systemImage: "clock")
        self.valueRow(title: String(localized: "CPU cores"), value: cpuValue, systemImage: "cpu")
        self.valueRow(title: String(localized: "Memory"), value: memoryValue, systemImage: "memorychip")
        self.valueRow(title: String(localized: "Disk"), value: diskValue, systemImage: "internaldrive")
        self.valueRow(title: String(localized: "Heartbeat"), value: heartbeatValue, systemImage: "waveform.path.ecg")
        self.valueRow(title: String(localized: "Channels"), value: channelValue, systemImage: "bubble.left.and.bubble.right")
    }

    private func valueRow(title: String, value: String, systemImage: String) -> some View {
        NativeSettingsRow(
            title: title,
            detail: value,
            systemImage: systemImage,
            tint: OpenClawBrand.accent)
            .nativeSettingsCopyMenu(value)
            .nativeSettingsCopySwipe(value)
            .openClawEntrance()
            .openClawAnimation(value: value)
    }

    // MARK: - Formatting

    private static func nonEmpty(_ value: String, fallback: String, notSet: String) -> String {
        let trimmed: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let other: String = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty { return other }
        return notSet
    }

    private static func bytesText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    private static func memoryText(total: Int, free: Int) -> String {
        if total <= 0 { return String(localized: "Not set") }
        let used: Int = max(total - free, 0)
        return Self.bytesText(used) + " / " + Self.bytesText(total)
    }

    private static func diskText(total: Int?, free: Int?, notSet: String) -> String {
        guard let total, let free, total > 0 else { return notSet }
        return Self.bytesText(free) + " / " + Self.bytesText(total)
    }

    private static func addressText(host: String?, port: Int?, notSet: String) -> String {
        guard let host, !host.isEmpty else { return notSet }
        guard let port else { return host }
        return host + ":" + String(port)
    }

    private static func heartbeatText(_ seconds: Int?, notSet: String) -> String {
        guard let seconds else { return notSet }
        return String(seconds) + " s"
    }

    private static func healthPill(_ ok: Bool?) -> NativeSettingsPill? {
        guard let ok else { return nil }
        if ok {
            return NativeSettingsPill(label: String(localized: "Healthy"), tone: .ok)
        }
        return NativeSettingsPill(label: String(localized: "Needs attention"), tone: .warn)
    }
}
