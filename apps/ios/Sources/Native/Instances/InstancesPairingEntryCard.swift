import OpenClawKit
import SwiftUI
import UIKit

/// Pairing entry for the Instances page: paste or type a setup code / link, or scan its QR code.
/// A valid link is staged on `NodeAppModel`; the root view owns delivery and opens Gateway settings,
/// exactly like a deep link, so the one-shot link is never consumed by an embedded screen.
struct InstancesPairingEntryCard: View {
    private enum Feedback: Equatable {
        case none
        case staged
        case invalid
        case scanner(String)
    }

    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var code: String = ""
    @State private var feedback: Feedback = .none
    @State private var showScanner: Bool = false
    @State private var pendingScan: QRScannerResult?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OpenClawGlassCard {
            VStack(alignment: .leading, spacing: OpenClawSpace.md) {
                self.titleRow
                self.stepsList
                self.field
                self.actions
                self.feedbackView
            }
        }
        .accessibilityIdentifier("Instances.PairingEntry")
        .sheet(isPresented: self.$showScanner, onDismiss: self.deliverPendingScan) {
            self.scannerSheet
        }
        .sensoryFeedback(.success, trigger: self.feedback == .staged)
    }

    // MARK: - Pieces

    private var titleRow: some View {
        HStack(alignment: .top, spacing: OpenClawSpace.md) {
            InstanceGlyphTile(symbol: "qrcode.viewfinder")
            VStack(alignment: .leading, spacing: OpenClawSpace.xxs) {
                Text("Add a Gateway")
                    .font(OpenClawType.headline)
                Text("Paste a setup code or link, or scan the QR code shown by your Gateway.")
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The pairing flow in three short steps, so the person always knows what comes next.
    private var stepsList: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.sm) {
            self.stepRow(number: 1, text: Text("On your Gateway host, run `openclaw qr`."))
            self.stepRow(number: 2, text: Text("Scan the QR code or paste the setup code below."))
            self.stepRow(number: 3, text: Text("Approve this device from the pairing requests list."))
        }
        .accessibilityElement(children: .combine)
    }

    private func stepRow(number: Int, text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OpenClawSpace.sm) {
            Text(verbatim: String(number))
                .font(OpenClawType.caption2SemiBold)
                .monospacedDigit()
                .foregroundStyle(OpenClawBrand.accent)
                .frame(width: 20, height: 20)
                .background(OpenClawBrand.accent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            text
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: OpenClawRadius.md, style: .continuous)
        return TextField("Setup code", text: self.$code, axis: .vertical)
            .font(OpenClawType.body)
            .lineLimit(1...3)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused(self.$fieldFocused)
            .onSubmit { self.submit() }
            .padding(.horizontal, OpenClawSpace.md)
            .frame(minHeight: OpenClawHitTarget.minimum)
            .background(Color(uiColor: .tertiarySystemFill), in: shape)
            .onChange(of: self.code) { _, _ in
                if self.feedback != .none {
                    self.setFeedback(.none)
                }
            }
    }

    private var actions: some View {
        OpenClawGlassControlGroup {
            HStack(spacing: OpenClawSpace.sm) {
                OpenClawGlassButton(title: "Connect", systemImage: "link", kind: .prominent) {
                    self.submit()
                }
                .disabled(!self.canSubmit)

                OpenClawGlassIconButton(
                    systemImage: "doc.on.clipboard",
                    accessibilityLabel: "Paste")
                {
                    self.paste()
                }
                .contextMenu {
                    Button {
                        self.paste()
                        self.submit()
                    } label: {
                        Label("Paste and connect", systemImage: "link")
                    }
                }

                OpenClawGlassIconButton(
                    systemImage: "qrcode.viewfinder",
                    accessibilityLabel: "Scan QR code")
                {
                    self.fieldFocused = false
                    self.showScanner = true
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        switch self.feedback {
        case .none:
            EmptyView()
        case .staged:
            self.notice(
                systemImage: "checkmark.circle.fill",
                tint: OpenClawBrand.ok,
                text: Text("Setup code loaded. Continue in the Gateway settings."))
        case .invalid:
            self.notice(
                systemImage: "exclamationmark.triangle.fill",
                tint: OpenClawBrand.warn,
                text: Text("Setup code not recognized or uses an insecure ws:// gateway URL."))
        case let .scanner(message):
            self.notice(
                systemImage: "exclamationmark.triangle.fill",
                tint: OpenClawBrand.warn,
                text: Text(verbatim: message))
        }
    }

    private func notice(systemImage: String, tint: Color, text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OpenClawSpace.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            text
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .transition(OpenClawMotion.edge(.top, reduceMotion: self.reduceMotion))
        .accessibilityElement(children: .combine)
    }

    private var scannerSheet: some View {
        NavigationStack {
            QRScannerView(
                onResult: { (result: QRScannerResult) -> Void in
                    self.pendingScan = result
                    self.showScanner = false
                },
                onError: { (message: String) -> Void in
                    self.showScanner = false
                    self.setFeedback(.scanner(message))
                },
                onDismiss: {})
                .ignoresSafeArea()
                .navigationTitle("Scan Setup Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            self.pendingScan = nil
                            self.showScanner = false
                        }
                    }
                }
        }
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        !self.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func setFeedback(_ value: Feedback) {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.feedback = value
        }
    }

    private func paste() {
        guard let value = UIPasteboard.general.string, !value.isEmpty else { return }
        self.code = value
    }

    private func submit() {
        let raw: String = self.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let link = GatewayConnectDeepLink.fromSetupInput(raw) else {
            self.setFeedback(.invalid)
            return
        }
        self.fieldFocused = false
        self.code = ""
        self.appModel.stageGatewaySetupLink(link)
        self.setFeedback(.staged)
    }

    /// The scanner result is handled after the sheet is gone and the camera had time to shut down.
    private func deliverPendingScan() {
        guard let result = self.pendingScan else { return }
        self.pendingScan = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: QRScannerResultHandoff.defaultSettlingNanoseconds)
            switch result {
            case let .gatewayLink(link):
                self.appModel.stageGatewaySetupLink(link)
                self.setFeedback(.staged)
            case let .setupCode(text):
                guard let link = GatewayConnectDeepLink.fromSetupInput(text) else {
                    self.setFeedback(.invalid)
                    return
                }
                self.appModel.stageGatewaySetupLink(link)
                self.setFeedback(.staged)
            }
        }
    }
}
