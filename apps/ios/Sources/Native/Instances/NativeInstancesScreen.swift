import SwiftUI
import UIKit

/// Views of the Instances page: paired devices (pending requests on top), live presence, saved Gateways.
enum InstancesScope: Hashable {
    case devices
    case connected
    case gateways
}

private typealias InstanceGatewayEntry = GatewaySettingsStore.GatewayRegistryEntry

/// Native Instances page: connection status, pairing entry (code / QR), pending pairing requests,
/// paired devices, live presence and saved Gateways.
/// Content rows sit on opaque list surfaces; Liquid Glass is limited to controls and the segmented bar.
/// The header, the pairing entry and the Gateways list stay reachable when the operator is offline
/// or the device list is empty, because that is exactly when someone needs to pair.
struct NativeInstancesScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(GatewayConnectionController.self) private var gatewayController
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model = InstancesViewModel()
    @State private var gateways = InstancesGatewayStore()
    @State private var scope: InstancesScope = .devices
    @State private var forgetTarget: InstanceGatewayEntry?
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    var body: some View {
        NavigationStack {
            self.content
                .navigationTitle(self.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let headerSidebarAction {
                        OpenClawSidebarToolbarItem(action: headerSidebarAction, placement: .topBarLeading)
                    }
                }
        }
        .task { await self.refreshAll(showSpinner: true) }
        .onChange(of: self.appModel.isOperatorGatewayConnected) { _, _ in
            Task { await self.refreshAll(showSpinner: false) }
        }
        .confirmationDialog(
            self.model.confirmation?.title ?? "",
            isPresented: self.confirmingBinding,
            titleVisibility: .visible)
        {
            self.confirmationButtons
        } message: {
            Text(verbatim: self.model.confirmation?.message ?? "")
        }
        .confirmationDialog(
            String(localized: "Forget this Gateway?"),
            isPresented: self.forgettingBinding,
            titleVisibility: .visible)
        {
            self.forgetButtons
        } message: {
            Text(verbatim: self.forgetTarget?.name ?? "")
        }
        .alert(
            String(localized: "Rename device"),
            isPresented: self.renamingBinding)
        {
            self.renameFields
        } message: {
            Text("Choose a label of up to 64 characters.")
        }
    }

    // MARK: - Refresh

    private func refreshAll(showSpinner: Bool) async {
        self.gateways.reload()
        await self.model.load(appModel: self.appModel, showSpinner: showSpinner)
    }

    // MARK: - Bindings

    private var confirmingBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.model.isConfirming },
            set: { self.model.isConfirming = $0 })
    }

    private var renamingBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.model.isRenaming },
            set: { self.model.isRenaming = $0 })
    }

    private var renameTextBinding: Binding<String> {
        Binding<String>(
            get: { self.model.renameText },
            set: { self.model.renameText = $0 })
    }

    private var forgettingBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.forgetTarget != nil },
            set: { (shown: Bool) -> Void in
                if !shown { self.forgetTarget = nil }
            })
    }

    // MARK: - Dialog content

    @ViewBuilder
    private var confirmationButtons: some View {
        if let confirmation = self.model.confirmation {
            Button(confirmation.confirmLabel, role: .destructive) {
                Task { await self.model.confirmPending(appModel: self.appModel) }
            }
        }
        Button(String(localized: "Cancel"), role: .cancel) {
            self.model.confirmation = nil
        }
    }

    @ViewBuilder
    private var forgetButtons: some View {
        if let target = self.forgetTarget {
            Button(String(localized: "Forget"), role: .destructive) {
                self.forgetTarget = nil
                Task { await self.gateways.forget(target, controller: self.gatewayController) }
            }
        }
        Button(String(localized: "Cancel"), role: .cancel) {
            self.forgetTarget = nil
        }
    }

    @ViewBuilder
    private var renameFields: some View {
        TextField(String(localized: "Device label"), text: self.renameTextBinding)
        Button(String(localized: "Save")) {
            Task { await self.model.submitRename(appModel: self.appModel) }
        }
        .disabled(!self.model.renameIsValid)
        Button(String(localized: "Cancel"), role: .cancel) {
            self.model.renameTarget = nil
        }
    }

    // MARK: - State

    @ViewBuilder
    private var content: some View {
        switch self.model.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading"))
        case let .failed(message):
            self.list(snapshot: nil, failure: message)
        case let .loaded(snapshot):
            self.list(snapshot: snapshot, failure: nil)
        }
    }

    private var scopeOptions: [OpenClawGlassSegmented<InstancesScope>.Option] {
        [
            OpenClawGlassSegmented<InstancesScope>.Option(.devices, title: "Devices"),
            OpenClawGlassSegmented<InstancesScope>.Option(.connected, title: "Connected now"),
            OpenClawGlassSegmented<InstancesScope>.Option(.gateways, title: "Gateways"),
        ]
    }

    private var scopeSegments: [NativeSegment<InstancesScope>] {
        [
            NativeSegment(id: .devices, title: String(localized: "Devices")),
            NativeSegment(id: .connected, title: String(localized: "Connected now")),
            NativeSegment(id: .gateways, title: String(localized: "Gateways")),
        ]
    }

    /// Glass segmented control (selection morphs on the shared spring); a menu picker at accessibility sizes.
    @ViewBuilder
    private var scopeBar: some View {
        if self.typeSize.isAccessibilitySize {
            NativeSegmentedBar(segments: self.scopeSegments, selection: self.$scope)
        } else {
            OpenClawGlassSegmented(selection: self.$scope, options: self.scopeOptions)
                .nativeBarInset()
        }
    }

    private func list(snapshot: InstancesSnapshot?, failure: String?) -> some View {
        List {
            self.overviewSection(snapshot)
            if let failure {
                self.failureSection(failure)
            }
            if let error = self.model.actionError {
                Section {
                    NativeInlineNotice(message: error)
                }
            }
            if let snapshot {
                // Pairing requests need attention first, whichever segment is selected.
                self.pendingSection(snapshot)
            }
            self.scopeSections(snapshot)
        }
        .refreshable { await self.refreshAll(showSpinner: false) }
        .safeAreaInset(edge: .top, spacing: 0) {
            self.scopeBar
        }
        .openClawAnimation(value: self.scope)
        .openClawHaptic(.selection, trigger: self.scope)
    }

    private func overviewSection(_ snapshot: InstancesSnapshot?) -> some View {
        Section {
            InstancesConnectionHeader(
                pendingCount: snapshot?.pending.count ?? 0,
                pairedCount: snapshot?.paired.count ?? 0,
                connectedCount: snapshot?.presence.count ?? 0)
                .openClawEntrance(index: 0)
                .instancesCardRow()
            InstancesPairingEntryCard()
                .openClawEntrance(index: 1)
                .instancesCardRow()
        }
    }

    private func failureSection(_ message: String) -> some View {
        Section {
            NativeInlineNotice(message: message)
            OpenClawGlassButton(title: "Retry", systemImage: "arrow.clockwise") {
                Task { await self.refreshAll(showSpinner: true) }
            }
        }
    }

    @ViewBuilder
    private func scopeSections(_ snapshot: InstancesSnapshot?) -> some View {
        switch self.scope {
        case .devices:
            if let snapshot {
                self.pairedSection(snapshot)
            }
        case .connected:
            if let snapshot {
                self.presenceSection(snapshot)
            }
        case .gateways:
            self.gatewaysSection
        }
    }

    // MARK: - Pending

    @ViewBuilder
    private func pendingSection(_ snapshot: InstancesSnapshot) -> some View {
        if !snapshot.pending.isEmpty {
            Section {
                ForEach(snapshot.pending) { request in
                    InstancePendingRow(model: self.model, request: request, appModel: self.appModel)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            self.approveSwipe(request)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            self.rejectSwipe(request)
                        }
                        .contextMenu {
                            self.approveSwipe(request)
                            self.rejectSwipe(request)
                        }
                }
            } header: {
                Text("Pairing requests")
            } footer: {
                if !self.model.canResolveRequests {
                    Text("Approving or rejecting needs the operator.pairing scope.")
                }
            }
        }
    }

    // MARK: - Paired

    @ViewBuilder
    private func pairedSection(_ snapshot: InstancesSnapshot) -> some View {
        if let error = snapshot.pairingError {
            Section(String(localized: "Paired devices")) {
                NativeInlineNotice(message: error)
            }
        } else if !snapshot.paired.isEmpty {
            Section(String(localized: "Paired devices")) {
                ForEach(snapshot.paired) { device in
                    InstancePairedRow(model: self.model, device: device)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            self.removeSwipe(device)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            self.renameSwipe(device)
                        }
                        .contextMenu {
                            self.renameSwipe(device)
                            self.removeSwipe(device)
                        }
                }
            }
        } else if snapshot.pending.isEmpty {
            Section {
                OpenClawEmptyState(
                    systemImage: "iphone.slash",
                    title: "No devices",
                    message: "Paired devices appear here once they connect to this Gateway.")
                    .instancesCardRow()
            }
        }
    }

    // MARK: - Presence

    @ViewBuilder
    private func presenceSection(_ snapshot: InstancesSnapshot) -> some View {
        if let error = snapshot.presenceError {
            Section(String(localized: "Connected now")) {
                NativeInlineNotice(message: error)
            }
        } else if !snapshot.presence.isEmpty {
            Section {
                ForEach(snapshot.presence) { device in
                    InstancePresenceRow(device: device)
                }
            } header: {
                Text("Connected now")
            } footer: {
                if snapshot.presenceTruncated {
                    Text("List truncated by the Gateway.")
                }
            }
        } else {
            Section {
                OpenClawEmptyState(
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    title: "No devices",
                    message: "Nothing is connected to this Gateway right now.")
                    .instancesCardRow()
            }
        }
    }

    // MARK: - Gateways

    private var gatewaysSection: some View {
        Section {
            if let error = self.gateways.errorMessage {
                NativeInlineNotice(message: error)
            }
            if self.gateways.entries.isEmpty {
                OpenClawEmptyState(
                    systemImage: "server.rack",
                    title: "No saved Gateways",
                    message: "Add a Gateway with a setup code or QR code above.")
                    .instancesCardRow()
            }
            ForEach(self.gateways.entries) { entry in
                self.gatewayRow(entry)
            }
        } header: {
            Text("Gateways")
        }
    }

    private func gatewayRow(_ entry: InstanceGatewayEntry) -> some View {
        let live: Bool = self.gateways.isLive(entry)
        let toggleTitle: LocalizedStringKey = live ? "Disconnect" : "Connect"
        let toggleImage: String = live ? "bolt.slash" : "bolt"
        let toggleTint: Color = live ? OpenClawBrand.info : OpenClawBrand.ok
        return InstanceGatewayRow(
            entry: entry,
            isActive: self.gateways.isActive(entry),
            isLive: live,
            isBusy: self.gateways.isBusy(entry),
            onToggleLive: { (enabled: Bool) -> Void in
                self.gateways.setLive(entry, enabled: enabled, controller: self.gatewayController)
            })
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    self.gateways.setLive(entry, enabled: !live, controller: self.gatewayController)
                } label: {
                    Label(toggleTitle, systemImage: toggleImage)
                }
                .tint(toggleTint)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    self.forgetTarget = entry
                } label: {
                    Label("Forget", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    self.gateways.setLive(entry, enabled: !live, controller: self.gatewayController)
                } label: {
                    Label(toggleTitle, systemImage: toggleImage)
                }
                if let host = entry.host, !host.isEmpty {
                    Button {
                        UIPasteboard.general.string = host
                    } label: {
                        Label(String(localized: "Copy address"), systemImage: "doc.on.doc")
                    }
                }
                Button(role: .destructive) {
                    self.forgetTarget = entry
                } label: {
                    Label("Forget", systemImage: "trash")
                }
            }
    }

    // MARK: - Swipe actions (same gating and confirmations as the buttons and menus)

    @ViewBuilder
    private func approveSwipe(_ request: InstancePendingRequest) -> some View {
        if self.model.canResolveRequests, !self.model.isBusy(request.id) {
            Button {
                Task {
                    await self.model.perform(.approve(requestId: request.id), appModel: self.appModel)
                }
            } label: {
                Label(String(localized: "Approve"), systemImage: "checkmark")
            }
            .tint(OpenClawBrand.ok)
        }
    }

    @ViewBuilder
    private func rejectSwipe(_ request: InstancePendingRequest) -> some View {
        if self.model.canResolveRequests, !self.model.isBusy(request.id) {
            Button(role: .destructive) {
                self.model.beginConfirmation(.reject(requestId: request.id, name: request.name))
            } label: {
                Label(String(localized: "Reject"), systemImage: "xmark")
            }
        }
    }

    @ViewBuilder
    private func removeSwipe(_ device: InstancePairedDevice) -> some View {
        if self.model.canRemove, !self.model.isBusy(device.id) {
            Button(role: .destructive) {
                self.model.beginConfirmation(.remove(deviceId: device.id, name: device.name))
            } label: {
                Label(String(localized: "Remove"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func renameSwipe(_ device: InstancePairedDevice) -> some View {
        if self.model.canRename, !self.model.isBusy(device.id) {
            Button {
                self.model.beginRename(device)
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }
            .tint(OpenClawBrand.info)
        }
    }
}

// MARK: - Row chrome

private extension View {
    /// Lets a card fill the list row without the grouped-list background or separators.
    func instancesCardRow() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Rows

private struct InstancePendingRow: View {
    let model: InstancesViewModel
    let request: InstancePendingRequest
    let appModel: NodeAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.md) {
            self.info
            self.buttons
        }
        .padding(.vertical, OpenClawSpace.xs)
    }

    private var info: some View {
        HStack(alignment: .top, spacing: OpenClawSpace.md) {
            InstanceGlyphTile(
                symbol: InstanceGlyph.symbol(platform: self.request.platform),
                tint: OpenClawBrand.warn)
            VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
                self.header
                self.details
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: OpenClawSpace.sm) {
            Text(verbatim: self.request.name)
                .font(OpenClawType.headline)
            Spacer(minLength: OpenClawSpace.sm)
            if self.request.isRepair {
                OpenClawStatusPill(
                    label: OpenClawTextValue.verbatim(String(localized: "Re-pairing")),
                    tone: .warn,
                    systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.xxs) {
            ForEach(self.detailLines, id: \.self) { line in
                Text(verbatim: line)
                    .font(OpenClawType.subhead)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailLines: [String] {
        var lines: [String] = []
        if let platform = self.request.platform { lines.append(platform) }
        if let role = self.request.role {
            lines.append(String(localized: "Role: \(role)"))
        }
        if !self.request.scopes.isEmpty {
            let joined: String = self.request.scopes.joined(separator: ", ")
            lines.append(String(localized: "Scopes: \(joined)"))
        }
        if let ip = self.request.remoteIp {
            lines.append(String(localized: "From \(ip)"))
        }
        if let when = NativeFormat.relative(ms: self.request.requestedAtMs) {
            lines.append(when)
        }
        return lines
    }

    private var buttons: some View {
        let busy: Bool = self.model.isBusy(self.request.id)
        let enabled: Bool = self.model.canResolveRequests && !busy
        return OpenClawGlassControlGroup {
            HStack(spacing: OpenClawSpace.md) {
                Button {
                    Task {
                        await self.model.perform(.approve(requestId: self.request.id), appModel: self.appModel)
                    }
                } label: {
                    Label(String(localized: "Approve"), systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .nativeMinimumTapTarget()
                }
                .nativeGlassButtonStyle(prominent: true)
                .disabled(!enabled)

                Button(role: .destructive) {
                    let confirmation = InstanceConfirmation.reject(
                        requestId: self.request.id, name: self.request.name)
                    self.model.beginConfirmation(confirmation)
                } label: {
                    Label(String(localized: "Reject"), systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                        .nativeMinimumTapTarget()
                }
                .nativeGlassButtonStyle()
                .disabled(!enabled)

                if busy {
                    ProgressView()
                        .accessibilityLabel(Text("Working"))
                }
            }
        }
    }
}

private struct InstancePairedRow: View {
    let model: InstancesViewModel
    let device: InstancePairedDevice

    var body: some View {
        HStack(alignment: .top, spacing: OpenClawSpace.md) {
            self.info
            Spacer(minLength: OpenClawSpace.sm)
            self.menu
        }
        .padding(.vertical, OpenClawSpace.xs)
        .accessibilityElement(children: .contain)
    }

    private var info: some View {
        HStack(alignment: .top, spacing: OpenClawSpace.md) {
            InstanceGlyphTile(
                symbol: InstanceGlyph.symbol(platform: self.device.platform, kind: self.device.deviceFamily),
                tint: self.device.connected == true ? OpenClawBrand.ok : OpenClawBrand.accent)
            VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
                Text(verbatim: self.device.name)
                    .font(OpenClawType.headline)
                ForEach(self.detailLines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(OpenClawType.subhead)
                        .foregroundStyle(.secondary)
                }
                self.status
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        if self.device.connected == true {
            OpenClawStatusPill(
                label: OpenClawTextValue.verbatim(String(localized: "Connected")),
                tone: .ok,
                systemImage: "checkmark.circle.fill")
        }
    }

    private var detailLines: [String] {
        var lines: [String] = []
        if let platform = self.device.platform { lines.append(platform) }
        if !self.device.roles.isEmpty {
            let joined: String = self.device.roles.joined(separator: ", ")
            lines.append(String(localized: "Roles: \(joined)"))
        }
        if let seen = NativeFormat.relative(ms: self.device.lastSeenAtMs) {
            lines.append(String(localized: "Last seen \(seen)"))
        }
        return lines
    }

    private var menu: some View {
        let busy: Bool = self.model.isBusy(self.device.id)
        return Menu {
            Button {
                self.model.beginRename(self.device)
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }
            .disabled(!self.model.canRename)

            Button(role: .destructive) {
                let confirmation = InstanceConfirmation.remove(
                    deviceId: self.device.id, name: self.device.name)
                self.model.beginConfirmation(confirmation)
            } label: {
                Label(String(localized: "Remove"), systemImage: "trash")
            }
            .disabled(!self.model.canRemove)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .nativeMinimumTapTarget()
        }
        .disabled(busy)
        .accessibilityLabel(Text("Actions for \(self.device.name)"))
    }
}

private struct InstancePresenceRow: View {
    let device: InstancePresenceDevice

    var body: some View {
        HStack(alignment: .top, spacing: OpenClawSpace.md) {
            InstanceGlyphTile(
                symbol: InstanceGlyph.symbol(platform: self.device.platform, kind: self.device.kind),
                tint: OpenClawBrand.ok)
            VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
                Text(verbatim: self.device.name)
                    .font(OpenClawType.headline)
                if let summary = NativeFormat.joined(self.detailLines) {
                    Text(verbatim: summary)
                        .font(OpenClawType.subhead)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, OpenClawSpace.xs)
        .accessibilityElement(children: .combine)
    }

    private var detailLines: [String] {
        var lines: [String] = []
        if let person = self.device.personName { lines.append(person) }
        if let kind = self.device.kind { lines.append(kind) }
        if let platform = self.device.platform { lines.append(platform) }
        if self.device.connectionCount > 1 {
            let count: Int = self.device.connectionCount
            lines.append(String(localized: "\(count) connections"))
        }
        if let active = NativeFormat.relative(ms: self.device.lastActivityAtMs) {
            lines.append(String(localized: "Active \(active)"))
        }
        return lines
    }
}
