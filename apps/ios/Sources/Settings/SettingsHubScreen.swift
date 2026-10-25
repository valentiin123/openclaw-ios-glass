import OpenClawKit
import SwiftUI
import UIKit

/// Native Settings hub. No web content: every row pushes a SwiftUI screen.
/// Five groups: Connection (live status header), Appearance, Notifications, Agents, About.
/// Pull to refresh re-reads the Gateway overview and the approval inbox.
/// `SettingsRoute` rows go through the typed `navigationPath`; native Dashboard replacements
/// (`NativeSettingsDestination`) use destination links so the typed path stays `[SettingsRoute]`.
struct SettingsHubScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var toast = GlassToastModel()
    @Binding var navigationPath: [SettingsRoute]
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var onRouteChange: ((SettingsRoute?) -> Void)?
    var onApprovalNotificationsRoute: ((String?) -> Void)?

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            self.root
                .background(SidebarNavigationMarginAnchor())
                .navigationDestination(for: SettingsRoute.self) { route in
                    self.nativeScreen(route: route)
                }
        }
    }

    private var root: some View {
        List {
            self.connectionSection
            self.appearanceSection
            self.notificationsSection
            self.agentVoiceSection
            self.advancedSection
        }
        .font(OpenClawType.body)
        .scrollContentBackground(.hidden)
        .background { OpenClawProBackground() }
        .refreshable {
            await self.appModel.refreshGatewayOverviewIfConnected()
            await self.appModel.refreshPendingApprovalInbox()
        }
        .environment(self.toast)
        .glassToastHost(self.toast)
        .accessibilityIdentifier("SettingsHub.Fallback")
        .openClawAnimation(value: self.appModel.pendingExecApprovalCount)
        .openClawHaptic(.selection, trigger: self.navigationPath.count)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let headerSidebarAction {
                OpenClawSidebarToolbarItem(action: headerSidebarAction, placement: .topBarLeading)
            }
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            SettingsConnectionHeader(
                status: InstancesConnectionStatus(appModel: self.appModel),
                pendingApprovals: self.appModel.pendingExecApprovalCount,
                openGateway: { self.navigationPath.append(.gateway) },
                openApprovals: { self.navigationPath.append(.approvals) })
                .openClawEntrance(index: 0)
                .ngCardRow()
            NavigationLink(value: SettingsRoute.gateway) {
                NativeSettingsRow(
                    title: String(localized: "Gateway"),
                    detail: self.gatewayDetail,
                    systemImage: "network",
                    tint: OpenClawBrand.accent,
                    pill: self.gatewayPill)
            }
            .glassCopyMenu(self.gatewayDetail)
            .glassCopySwipe(self.gatewayDetail)
            .openClawEntrance(index: 1)
            .accessibilityIdentifier("SettingsHub.Gateway")
            NavigationLink(value: SettingsRoute.approvals) {
                NativeSettingsRow(
                    title: String(localized: "Approvals"),
                    systemImage: "checkmark.shield",
                    tint: OpenClawBrand.accent,
                    pill: self.approvalsPill)
            }
            .openClawEntrance(index: 2)
            .accessibilityIdentifier("SettingsHub.Approvals")
        } header: {
            NativeSettingsHeader("Connection")
        }
    }

    private var agentVoiceSection: some View {
        Section {
            self.nativeLink(.talkVoice, index: 0)
            if self.appModel.isOperatorGatewayConnected {
                self.nativeLink(.channels, index: 1)
                self.nativeLink(.skills, index: 2)
            }
        } header: {
            NativeSettingsHeader("Agents")
        }
    }

    private var notificationsSection: some View {
        Section {
            self.nativeLink(.notifications, index: 0)
            self.nativeLink(.permissions, index: 1)
        } header: {
            NativeSettingsHeader("Notifications")
        }
    }

    private var appearanceSection: some View {
        Section {
            self.nativeLink(.appearance)
        } header: {
            NativeSettingsHeader("Appearance")
        }
    }

    private var advancedSection: some View {
        Section {
            self.routeLink(
                .diagnostics,
                title: String(localized: "Diagnostics"),
                systemImage: "stethoscope")
            self.routeLink(
                .licenses,
                title: String(localized: "Licenses"),
                systemImage: "doc.text")
                .accessibilityIdentifier("settings-licenses-row")
            self.routeLink(
                .about,
                title: String(localized: "About"),
                systemImage: "info.circle")
        } header: {
            NativeSettingsHeader("About")
        }
    }

    // MARK: - Rows

    private func nativeLink(_ destination: NativeSettingsDestination, index: Int = 0) -> some View {
        NavigationLink {
            NativeSettingsRouter(destination: destination, embedded: true)
        } label: {
            NativeSettingsRow(
                title: destination.title,
                systemImage: destination.systemImage,
                tint: OpenClawBrand.accent)
        }
        .openClawEntrance(index: index)
        .accessibilityIdentifier("SettingsHub.\(destination.rawValue)")
    }

    private func routeLink(_ route: SettingsRoute, title: String, systemImage: String) -> some View {
        NavigationLink(value: route) {
            NativeSettingsRow(
                title: title,
                systemImage: systemImage,
                tint: OpenClawBrand.accent)
        }
    }

    // MARK: - Gateway summary

    private var gatewayPill: NativeSettingsPill {
        // Shared with the Instances header so both screens say the same thing,
        // including "Waiting for approval" while a pairing request is pending.
        let status: InstancesConnectionStatus = InstancesConnectionStatus(appModel: self.appModel)
        return NativeSettingsPill(label: status.label, tone: status.tone)
    }

    private var gatewayDetail: String? {
        let name: String = self.appModel.gatewayServerName ?? ""
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    private var approvalsPill: NativeSettingsPill? {
        let count: Int = self.appModel.pendingExecApprovalCount
        if count <= 0 { return nil }
        return NativeSettingsPill(label: count.formatted(), tone: .warn)
    }

    // MARK: - Navigation

    private func nativeScreen(route: SettingsRoute) -> some View {
        SettingsProTab(
            directRoute: route,
            registersNavigationDestinations: false,
            onRouteChange: self.onRouteChange,
            onApprovalNotificationsRoute: self.onApprovalNotificationsRoute)
    }

    /// Kept for `DashboardPageScreen` and tests; the Settings hub itself no longer embeds the Dashboard.
    static func usesDashboard(
        isOperatorConnected: Bool,
        hasOperatorAdminScope: Bool,
        isDemoMode: Bool,
        isScreenshotMode: Bool) -> Bool
    {
        isOperatorConnected && hasOperatorAdminScope && !isDemoMode && !isScreenshotMode
    }

    static func route(for panel: DeviceSettingsPanel) -> SettingsRoute? {
        switch panel {
        case .connection, .gateways: .gateway
        case .watch: .appleWatch
        case .diagnostics: .diagnostics
        case .licenses: .licenses
        case .about: .about
        case .aiSetup, .quickChatShortcut, .microphoneTest, .browserImport, .debug: nil
        }
    }
}

struct EmbeddedDashboardContent: View {
    @State private var bridge: IOSDeviceSettingsBridge
    let embedCompatibility: DashboardEmbedCompatibility?
    let url: URL
    let config: GatewayConnectConfig?
    let openGateway: (() -> Void)?

    init(
        appModel: NodeAppModel,
        appearanceModel: AppAppearanceModel,
        gatewayController: GatewayConnectionController,
        url: URL,
        config: GatewayConnectConfig?,
        openPanel: @escaping (DeviceSettingsPanel) -> Void,
        embedCompatibility: DashboardEmbedCompatibility? = nil,
        openGateway: (() -> Void)? = nil)
    {
        self.url = url
        self.config = config
        self.openGateway = openGateway
        self.embedCompatibility = embedCompatibility
        self._bridge = State(initialValue: IOSDeviceSettingsBridge(
            appModel: appModel,
            appearanceModel: appearanceModel,
            gatewayController: gatewayController,
            openPanel: openPanel,
            onStatusRequest: { [weak embedCompatibility] in
                embedCompatibility?.didReceiveStatusRequest()
            }))
    }

    var body: some View {
        let storedOperatorToken = AuthenticatedControlUI.storedOperatorToken(config: self.config)
        VStack(spacing: 0) {
            self.gatewayUpgradeBanner
            AuthenticatedControlUIWebView(
                url: self.url,
                authScript: AuthenticatedControlUI.authUserScript(
                    config: self.config,
                    pageURL: self.url,
                    storedOperatorToken: storedOperatorToken,
                    usesNativeNavigationChrome: true),
                tls: self.config?.tls,
                basicProxyCredentialProvider: {
                    AuthenticatedControlUI.basicProxyCredential(config: self.config)
                },
                deviceSettingsBridge: self.bridge,
                usesNativeEmbed: true,
                embedCompatibility: self.embedCompatibility)
                .id(AuthenticatedControlUI.webContentIdentity(
                    config: self.config,
                    storedOperatorToken: storedOperatorToken))
                .accessibilityIdentifier("SettingsHub.Dashboard")
        }
    }

    @ViewBuilder private var gatewayUpgradeBanner: some View {
        if let openGateway, self.embedCompatibility?.needsGatewayUpgrade == true {
            VStack(alignment: .leading, spacing: 8) {
                Text("This Gateway's Dashboard is older than the app; update the Gateway to manage app settings here")
                    .font(OpenClawType.footnote)
                    .accessibilityIdentifier("SettingsHub.GatewayUpgradeWarning")
                OpenClawGlassButton(
                    title: "Open Gateway",
                    systemImage: "network",
                    kind: .prominent,
                    action: openGateway)
                    .accessibilityIdentifier("SettingsHub.UpgradeGateway")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(OpenClawBrand.warn.opacity(0.12))
            .accessibilityElement(children: .contain)
        }
    }
}
