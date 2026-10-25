import SwiftUI

// MARK: - Shared connection status

/// Presentation of the current Gateway connection, shared by the Instances header and the Settings summary.
/// Status is carried by a symbol, a label and a tone, never by color alone.
struct InstancesConnectionStatus: Equatable {
    var name: String
    var detail: String?
    var label: String
    var tone: OpenClawStatusTone
    var symbol: String
    var isConnected: Bool

    @MainActor
    init(appModel: NodeAppModel) {
        let rawName: String = (appModel.gatewayServerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = rawName.isEmpty ? String(localized: "Gateway") : rawName
        let connected: Bool = appModel.isOperatorGatewayConnected
        self.isConnected = connected
        let remote: String? = appModel.gatewayRemoteAddress
        let display: String? = connected ? nil : appModel.gatewayDisplayStatusText
        let parts: [String?] = [display, remote]
        self.detail = NativeFormat.joined(parts)
        if appModel.gatewayPairingPaused {
            self.label = String(localized: "Waiting for approval")
            self.tone = .warn
            self.symbol = "hourglass"
        } else if connected {
            self.label = String(localized: "Connected")
            self.tone = .ok
            self.symbol = "network"
        } else {
            self.label = String(localized: "Offline")
            self.tone = .muted
            self.symbol = "network.slash"
        }
    }
}

// MARK: - Header

/// Gateway connection summary shown at the top of the Instances page.
/// Opaque card: glass is reserved for the controls around it.
struct InstancesConnectionHeader: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let pendingCount: Int
    let pairedCount: Int
    let connectedCount: Int

    var body: some View {
        let status = InstancesConnectionStatus(appModel: self.appModel)
        return OpenClawGlassCard {
            VStack(alignment: .leading, spacing: OpenClawSpace.lg) {
                self.titleRow(status)
                self.statsRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Instances.ConnectionHeader")
    }

    private func titleRow(_ status: InstancesConnectionStatus) -> some View {
        let stacked: Bool = self.typeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: OpenClawSpace.sm) {
            HStack(alignment: .center, spacing: OpenClawSpace.md) {
                self.icon(status)
                VStack(alignment: .leading, spacing: OpenClawSpace.xxs) {
                    Text(verbatim: status.name)
                        .font(OpenClawType.headline)
                    if let detail = status.detail {
                        Text(verbatim: detail)
                            .font(OpenClawType.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: OpenClawSpace.sm)
                if !stacked {
                    self.pill(status)
                }
            }
            if stacked {
                self.pill(status)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func icon(_ status: InstancesConnectionStatus) -> some View {
        Image(systemName: status.symbol)
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(status.tone.color)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 36, height: 36)
            .background(status.tone.color.opacity(0.14), in: RoundedRectangle(cornerRadius: OpenClawRadius.md, style: .continuous))
            .openClawAnimation(value: status.symbol)
            .accessibilityHidden(true)
    }

    private func pill(_ status: InstancesConnectionStatus) -> some View {
        OpenClawStatusPill(label: .verbatim(status.label), tone: status.tone)
    }

    private var statsRow: some View {
        let vertical: AnyLayout = AnyLayout(VStackLayout(alignment: .leading, spacing: OpenClawSpace.md))
        let horizontal: AnyLayout = AnyLayout(HStackLayout(alignment: .top, spacing: OpenClawSpace.lg))
        let layout: AnyLayout = self.typeSize.isAccessibilitySize ? vertical : horizontal
        return layout {
            self.stat(count: self.pendingCount, label: "Pairing requests", highlight: self.pendingCount > 0)
            self.stat(count: self.pairedCount, label: "Devices", highlight: false)
            self.stat(count: self.connectedCount, label: "Connected", highlight: false)
        }
    }

    private func stat(count: Int, label: LocalizedStringKey, highlight: Bool) -> some View {
        let valueColor: Color = highlight ? OpenClawBrand.warn : Color.primary
        return VStack(alignment: .leading, spacing: OpenClawSpace.xxs) {
            Text(count.formatted())
                .font(OpenClawType.title3SemiBold)
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
            Text(label)
                .font(OpenClawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .openClawAnimation(value: count)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Glyphs

/// Maps a platform / kind string reported by the Gateway to an SF Symbol.
enum InstanceGlyph {
    static func symbol(platform: String?, kind: String? = nil) -> String {
        let parts: [String] = [platform, kind].compactMap { (value: String?) -> String? in value }
        let raw: String = parts.joined(separator: " ").lowercased()
        if raw.contains("ipad") { return "ipad" }
        if raw.contains("ios") || raw.contains("iphone") || raw.contains("android") { return "iphone" }
        if raw.contains("mac") || raw.contains("darwin") { return "laptopcomputer" }
        if raw.contains("windows") { return "desktopcomputer" }
        if raw.contains("linux") || raw.contains("server") || raw.contains("gateway") { return "server.rack" }
        if raw.contains("web") || raw.contains("browser") { return "globe" }
        return "display"
    }
}

/// Rounded tile holding a device glyph. Decorative: the row text carries the meaning.
struct InstanceGlyphTile: View {
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36
    let symbol: String
    var tint: Color = OpenClawBrand.accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OpenClawRadius.md, style: .continuous)
        return Image(systemName: self.symbol)
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(self.tint)
            .frame(width: self.side, height: self.side)
            .background(self.tint.opacity(0.14), in: shape)
            .accessibilityHidden(true)
    }
}
