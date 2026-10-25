import SwiftUI
import UIKit

/// Summary card at the top of the Settings hub: Gateway name, live status and two glass shortcuts.
/// The card itself is an opaque reading surface; glass is limited to the controls on it
/// (icon badge, status pill, shortcut chips), so there is never glass on glass.
struct SettingsConnectionHeader: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let status: InstancesConnectionStatus
    let pendingApprovals: Int
    let openGateway: () -> Void
    let openApprovals: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            self.summary
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

    private var approvalsTitle: OpenClawTextValue {
        if self.pendingApprovals > 0 {
            return .verbatim(String(localized: "Approvals") + " · " + self.pendingApprovals.formatted())
        }
        return "Approvals"
    }

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
