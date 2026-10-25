import SwiftUI
import UIKit

/// Summary card at the top of the Settings hub: Gateway name, live status and glass shortcuts.
/// The card itself is an opaque reading surface; glass is limited to the controls on it
/// (status pill, shortcut chips, the pairing call to action), so there is never glass on glass.
/// Three states are told apart by symbol, label and hint text, never by color alone:
/// connected, waiting for approval, and offline (with a prominent "Add a Gateway" action).
struct SettingsConnectionHeader: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: InstancesConnectionStatus
    let pendingApprovals: Int
    let openGateway: () -> Void
    let openApprovals: () -> Void

    private enum Phase {
        case connected
        case waiting
        case offline
    }

    private var phase: Phase {
        if self.status.tone == .warn { return .waiting }
        if self.status.isConnected { return .connected }
        return .offline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            self.summary
            self.hint
            self.shortcuts
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCardSurface(radius: 20)
        .openClawAnimation(value: self.status)
        .openClawAnimation(value: self.pendingApprovals)
        .contextMenu {
            Button {
                UIPasteboard.general.string = self.status.name
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Hint (state specific)

    @ViewBuilder
    private var hint: some View {
        switch self.phase {
        case .connected:
            EmptyView()
        case .waiting:
            self.hintRow(
                systemImage: "hourglass",
                tint: OpenClawBrand.warn,
                text: Text("Approve this device from your Gateway to finish pairing."))
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        case .offline:
            VStack(alignment: .leading, spacing: 10) {
                self.hintRow(
                    systemImage: "qrcode.viewfinder",
                    tint: OpenClawBrand.accent,
                    text: Text("Not connected. Add a Gateway with a setup code or QR code."))
                OpenClawGlassButton(
                    title: "Add a Gateway",
                    systemImage: "plus",
                    kind: .prominent,
                    action: self.openGateway)
                    .accessibilityIdentifier("SettingsHub.AddGateway")
            }
            .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        }
    }

    private func hintRow(systemImage: String, tint: Color, text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            text
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shortcuts

    private var shortcuts: some View {
        OpenClawGlassControlGroup {
            NGFlowLayout(spacing: 8) {
                OpenClawGlassChip(
                    title: "Gateway",
                    systemImage: "network",
                    isSelected: false,
                    tint: OpenClawBrand.accent,
                    action: self.openGateway)
                OpenClawGlassChip(
                    title: self.approvalsTitle,
                    systemImage: "checkmark.shield",
                    isSelected: self.pendingApprovals > 0,
                    tint: OpenClawBrand.warn,
                    action: self.openApprovals)
            }
        }
    }

    private var approvalsTitle: OpenClawTextValue {
        if self.pendingApprovals > 0 {
            return .verbatim(String(localized: "Approvals") + " · " + self.pendingApprovals.formatted())
        }
        return "Approvals"
    }

    // MARK: - Summary

    @ViewBuilder
    private var summary: some View {
        let identity = HStack(alignment: .center, spacing: 12) {
            NGIconBadge(systemImage: self.status.symbol, tint: self.status.tone.color, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.status.name)
                    .font(OpenClawType.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = self.status.detail {
                    Text(verbatim: detail)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        if self.typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                identity
                NGPill(text: self.status.label, tint: self.status.tone.color)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .center, spacing: 8) {
                identity
                Spacer(minLength: 8)
                NGPill(text: self.status.label, tint: self.status.tone.color)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
