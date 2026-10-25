import SwiftUI

/// Connection hint at the top of the Settings hub, shown only while the Gateway is not fully connected.
/// It is a plain list row (default insets, row background, 44 pt minimum height, body/footnote type)
/// so it lines up exactly with the `NativeSettingsRow` rows below it. The Gateway name itself lives in
/// the first `NativeSettingsRow` of the hub; this view never repeats it.
/// States are told apart by symbol and text, never by color alone:
/// waiting for approval, or offline (with a prominent "Add a Gateway" action).
struct SettingsConnectionHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: InstancesConnectionStatus
    let openGateway: () -> Void

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

    /// True when the hub should show this row at all.
    static func isVisible(for status: InstancesConnectionStatus) -> Bool {
        if status.tone == .warn { return true }
        return !status.isConnected
    }

    var body: some View {
        self.content
            .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum, alignment: .leading)
            .openClawAnimation(value: self.status)
    }

    @ViewBuilder
    private var content: some View {
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
            VStack(alignment: .leading, spacing: OpenClawSpace.md) {
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
            .padding(.vertical, OpenClawSpace.xs)
            .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        }
    }

    private func hintRow(systemImage: String, tint: Color, text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OpenClawSpace.md) {
            Image(systemName: systemImage)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            text
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
