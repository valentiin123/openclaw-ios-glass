import SwiftUI

/// Native Instances page: pending pairing requests, paired devices and live presence.
/// Content rows sit on opaque list surfaces; glass is limited to buttons and the toolbar.
struct NativeInstancesScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model = InstancesViewModel()
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    var body: some View {
        NavigationStack {
            self.stateView
                .navigationTitle(self.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let headerSidebarAction {
                        OpenClawSidebarToolbarItem(action: headerSidebarAction, placement: .topBarLeading)
                    }
                }
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        .confirmationDialog(
            self.model.confirmation?.title ?? "",
            isPresented: self.confirmingBinding,
            titleVisibility: .visible)
        {
            self.confirmationButtons
        } message: {
            Text(verbatim: self.model.confirmation?.message ?? "")
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

    private var stateView: some View {
        NativeStateView(
            state: self.model.state,
            isEmpty: { (snapshot: InstancesSnapshot) -> Bool in snapshot.isEmpty },
            emptyTitle: "No devices",
            emptyIcon: "dot.radiowaves.left.and.right",
            retry: { await self.model.load(appModel: self.appModel, showSpinner: true) })
        { (snapshot: InstancesSnapshot) in
            self.list(snapshot)
        }
    }

    private func list(_ snapshot: InstancesSnapshot) -> some View {
        List {
            if let error = self.model.actionError {
                Section {
                    NativeInlineNotice(message: error)
                }
            }
            self.pendingSection(snapshot)
            self.pairedSection(snapshot)
            self.presenceSection(snapshot)
        }
        .refreshable { await self.model.load(appModel: self.appModel, showSpinner: false) }
    }

    @ViewBuilder
    private func pendingSection(_ snapshot: InstancesSnapshot) -> some View {
        if !snapshot.pending.isEmpty {
            Section {
                ForEach(snapshot.pending) { request in
                    InstancePendingRow(model: self.model, request: request, appModel: self.appModel)
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
                }
            }
        }
    }

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
        }
    }
}

// MARK: - Rows

private struct InstancePendingRow: View {
    let model: InstancesViewModel
    let request: InstancePendingRequest
    let appModel: NodeAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.header
            self.details
            self.buttons
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "person.badge.clock")
                .accessibilityHidden(true)
            Text(verbatim: self.request.name)
                .font(OpenClawType.headline)
            Spacer(minLength: 8)
            if self.request.isRepair {
                OpenClawStatusPill(
                    label: OpenClawTextValue.verbatim(String(localized: "Re-pairing")),
                    tone: .warn,
                    systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
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
        return HStack(spacing: 12) {
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

private struct InstancePairedRow: View {
    let model: InstancesViewModel
    let device: InstancePairedDevice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: self.device.name)
                    .font(OpenClawType.headline)
                ForEach(self.detailLines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(OpenClawType.subhead)
                        .foregroundStyle(.secondary)
                }
                self.status
            }
            Spacer(minLength: 8)
            self.menu
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: self.device.name)
                .font(OpenClawType.headline)
            if let summary = NativeFormat.joined(self.detailLines) {
                Text(verbatim: summary)
                    .font(OpenClawType.subhead)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
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
