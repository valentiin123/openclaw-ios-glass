import OpenClawChatUI
import OpenClawKit
import SwiftUI
import UIKit

struct RootTabs: View {
    struct SessionObserverTaskIdentity: Equatable {
        let sidebarRefreshID: String
        let isSceneActive: Bool
        let isSidebarVisible: Bool

        var isObserverVisible: Bool {
            self.isSceneActive && self.isSidebarVisible
        }
    }

    private struct ChatOwnerTaskIdentity: Equatable {
        let route: String
        let sessionKey: String
        let routingContract: String?
        let isConnected: Bool
        let isRecording: Bool
        let isAttachmentOwnerPinned: Bool
        let newChatRequestID: Int
        let authority: GatewayConnectConfig.ControlUIInputs?
    }

    @Environment(NodeAppModel.self) private var appModel
    @Environment(VoiceWakeManager.self) private var voiceWake
    @Environment(GatewayConnectionController.self) private var gatewayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("screen.preventSleep") private var preventSleep: Bool = true
    @AppStorage("onboarding.requestID") private var onboardingRequestID: Int = 0
    @AppStorage("gateway.onboardingComplete") private var onboardingComplete: Bool = false
    @AppStorage("gateway.hasConnectedOnce") private var hasConnectedOnce: Bool = false
    @AppStorage("gateway.preferredStableID") private var preferredGatewayStableID: String = ""
    @AppStorage("gateway.manual.enabled") private var manualGatewayEnabled: Bool = false
    @AppStorage("gateway.manual.host") private var manualGatewayHost: String = ""
    @AppStorage("onboarding.quickSetupDismissed") private var quickSetupDismissed: Bool = false
    @State private var shell = AppShellNavigation(
        landing: AppShellLanding(legacy: RootTabs.initialSidebarDestination))
    @State private var sidebarModel = RootSidebarModel()
    @State private var voiceWakeToastText: String?
    @State private var toastDismissGate = DelayedActionGate()
    @State private var presentedSheet: PresentedSheet?
    @State private var showGatewayProblemDetails: Bool = false
    @State private var gatewayToastDragOffset: CGFloat = 0
    @State private var gatewayRetryFailure: String?
    // Swipe-up hides the current problem until it changes or resolves.
    @State private var isGatewayToastSwipeDismissed: Bool = false
    @State private var showOnboarding: Bool = false
    @State private var didEvaluateOnboarding: Bool = false
    @State private var didAutoOpenSettings: Bool = false
    @State private var didApplyInitialChatSession: Bool = false
    @State private var gatewaySetupRequest: GatewaySetupRequest?
    @State private var suppressedExecApprovalForNotificationSettings: NodeAppModel.ExecApprovalInboxKey?

    static var initialSidebarDestination: SidebarDestination {
        initialDestination(arguments: ProcessInfo.processInfo.arguments)
    }

    static func initialDestination(arguments: [String]) -> SidebarDestination {
        if let requested = self.requestedInitialSidebarDestination(arguments: arguments) {
            return requested
        }
        guard let value = arguments.drop(while: { $0 != "--openclaw-initial-tab" }).dropFirst().first
        else { return .chat }
        return switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "control", "overview": .overview
        case "chat", "talk", "voice": .chat
        case "agent", "agents": .agents
        case "settings": .settings
        default: .chat
        }
    }

    static func requestedInitialSidebarDestination(arguments: [String]) -> SidebarDestination? {
        guard let value = arguments.drop(while: { $0 != "--openclaw-initial-destination" }).dropFirst().first
        else { return nil }
        let requested = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SidebarDestination.allCases.first { $0.rawValue.lowercased() == requested }
    }

    private static var initialChatSessionKey: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let value = arguments.drop(while: { $0 != "--openclaw-chat-session" }).dropFirst().first
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum PresentedSheet: Identifiable {
        case quickSetup
        case notificationSettings(path: String)
        case sessionDashboard(sessionKey: String, agentId: String?)

        var id: String {
            switch self {
            case .quickSetup: "quick-setup"
            case .notificationSettings: "notification-settings"
            case let .sessionDashboard(sessionKey, agentId):
                "session-dashboard:\(agentId ?? ""):\(sessionKey)"
            }
        }
    }

    var body: some View {
        self.rootPresentation(
            self.rootLifecycle(
                self.rootOverlays(
                    self.shellContent
                        .tint(OpenClawBrand.accent))))
            .overlay(alignment: .topLeading) {
                self.uiTestReadinessMarker
            }
            .task(id: self.chatOwnerTaskIdentity) {
                await self.appModel.restoreChatSessionRoutingIdentityIfNeeded()
                guard !Task.isCancelled else { return }
                self.appModel.chatPresentation.sync(appModel: self.appModel)
                if let viewModel = self.appModel.chatPresentation.viewModel,
                   self.appModel.consumeNewChatRequest(self.appModel.newChatRequestID)
                {
                    _ = await viewModel.startNewSession()
                }
            }
    }

    private var chatOwnerTaskIdentity: ChatOwnerTaskIdentity {
        ChatOwnerTaskIdentity(
            route: self.appModel.chatViewModelIdentityID,
            sessionKey: self.appModel.chatSessionKey,
            routingContract: self.appModel.chatSessionRoutingContract,
            isConnected: self.appModel.isOperatorGatewayConnected,
            isRecording: self.appModel.voiceNoteRecorder.ownsPendingChatAttachment,
            isAttachmentOwnerPinned: self.appModel.chatPresentation.viewModel?.isAttachmentOwnerPinned == true,
            newChatRequestID: self.appModel.newChatRequestID,
            authority: self.appModel.activeGatewayConnectConfig?.controlUIInputs)
    }

    @ViewBuilder
    private var uiTestReadinessMarker: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--openclaw-ui-test-readiness") {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("RootTabs.Ready")
                .accessibilityLabel(Text(verbatim: "OpenClaw test readiness"))
                .accessibilityValue(
                    "\(self.scenePhase == .active ? "ready" : "inactive"):\(self.readinessDestination)")
        }
        #endif
    }

    /// Shell destination reported to UI tests. A Gateway landing keeps the legacy "gateway"
    /// value so existing readiness expectations stay valid; other values are `AppShellTab` raw values.
    private var readinessDestination: String {
        if self.shell.selection == .settings, self.shell.settingsPresentation == .gateway {
            return "gateway"
        }
        return self.shell.selection.rawValue
    }

    private var shellContext: AppShellContext {
        AppShellContext(
            sidebarModel: self.sidebarModel,
            acceptsGatewaySetupRequests: !self.showOnboarding,
            gatewaySetupRequest: self.gatewaySetupRequest,
            onGatewaySetupRequestHandled: self.handleGatewaySetupRequest,
            onSettingsRouteChange: self.handleSettingsRouteChange,
            onApprovalNotificationsRoute: self.openNotificationSettings)
    }

    /// Native shell: system Liquid Glass `TabView` (Shell/App/INTEGRATION.md). RootTabs keeps
    /// lifecycle, sheets, toasts and deep links; the shell only renders and routes.
    private var shellContent: some View {
        AppShellRootView(navigation: self.shell, context: self.shellContext)
            // Single refresh owner: identity/session changes, scene activation,
            // and the periodic attention refresh all land here.
            .task(id: self.sidebarRefreshID) {
                guard self.scenePhase == .active else { return }
                repeat {
                    await self.sidebarModel.refresh(appModel: self.appModel)
                    await self.appModel.refreshPendingApprovalInbox()
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: .seconds(600))
                } while !Task.isCancelled
            }
            .task(id: "\(self.sidebarRefreshID):events") {
                guard self.scenePhase == .active else { return }
                await self.sidebarModel.observeSessionEvents(appModel: self.appModel)
            }
            .task(id: self.sessionObserverTaskIdentity) {
                await self.sidebarModel.setSessionObserverVisibility(
                    appModel: self.appModel,
                    visible: self.sessionObserverTaskIdentity.isObserverVisible)
            }
    }

    private var sessionObserverTaskIdentity: SessionObserverTaskIdentity {
        SessionObserverTaskIdentity(
            sidebarRefreshID: self.sidebarRefreshID,
            isSceneActive: self.scenePhase == .active,
            isSidebarVisible: self.shell.selection == .overview)
    }

    private var sidebarRefreshID: String {
        [
            self.appModel.chatViewModelIdentityID,
            self.appModel.chatSessionKey,
            String(self.appModel.operatorAuthorityGeneration),
            self.scenePhase == .active ? "active" : "inactive",
        ].joined(separator: ":")
    }

    private var activeExecApprovalPromptSuppression: NodeAppModel.ExecApprovalInboxKey? {
        if case .notificationSettings = self.presentedSheet {
            return self.suppressedExecApprovalForNotificationSettings
        }
        guard self.shell.activeSettingsRoute == .approvals else { return nil }
        return NodeAppModel.execApprovalInboxKey(self.appModel.pendingExecApprovalPrompt)
    }

    private func rootOverlays(_ content: some View) -> some View {
        content
            .overlay(alignment: .top) {
                // Stable container so the toast's move/opacity transition animates
                // when the gateway problem appears or clears outside withAnimation.
                ZStack(alignment: .top) {
                    if let liveVoiceStartError = self.appModel.liveVoiceStartError {
                        // A banner survives onboarding dismissal without racing another modal.
                        OpenClawNoticeBanner(
                            icon: "mic.slash",
                            title: "Unable to Start Live Voice",
                            message: .verbatim(liveVoiceStartError),
                            ownerLabel: "Needs attention",
                            tint: OpenClawBrand.warn,
                            secondaryActionTitle: "Dismiss",
                            onSecondaryAction: { self.appModel.liveVoiceStartError = nil })
                            .padding(.horizontal, 12)
                            .safeAreaPadding(.top, 10)
                    } else if let gatewayRetryFailure {
                        OpenClawNoticeBanner(
                            icon: "wifi.exclamationmark",
                            title: "Gateway reconnect failed",
                            message: .verbatim(gatewayRetryFailure),
                            ownerLabel: "Needs attention",
                            tint: OpenClawBrand.warn,
                            secondaryActionTitle: "Dismiss",
                            onSecondaryAction: { self.gatewayRetryFailure = nil })
                            .padding(.horizontal, 12)
                            .safeAreaPadding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if let gatewayProblem = self.activeGatewayProblemToast {
                        self.gatewayProblemToast(gatewayProblem)
                    }
                }
                .animation(self.gatewayToastAnimation, value: self.gatewayRetryFailure)
                .animation(self.gatewayToastAnimation, value: self.activeGatewayProblemToast)
            }
            .overlay(alignment: .topLeading) {
                if let voiceWakeToastText, !voiceWakeToastText.isEmpty {
                    VoiceWakeToast(command: voiceWakeToastText)
                        .padding(.leading, 10)
                        .safeAreaPadding(
                            .top,
                            self.activeGatewayProblemToast == nil && self.gatewayRetryFailure == nil
                                && self.appModel.liveVoiceStartError == nil ? 58 : 132)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            .overlay {
                // Keep the observer mounted so the first 0 -> 1 capture transition
                // flashes without treating a later remount as a new capture.
                RootCameraFlashOverlay(nonce: self.appModel.cameraFlashNonce)
            }
    }

    private var activeGatewayProblemToast: GatewayConnectionProblem? {
        // Auth and pairing failures remain actionable even if another route is connected.
        guard let problem = appModel.gatewayProblemForToast,
              !self.isGatewayToastSwipeDismissed
        else { return nil }
        return problem
    }

    private var gatewayToastAnimation: Animation? {
        OpenClawMotion.animation(reduceMotion: self.reduceMotion)
    }

    private func gatewayProblemToast(_ problem: GatewayConnectionProblem) -> some View {
        GatewayProblemBanner(
            problem: problem,
            primaryActionTitle: gatewayProblemPrimaryActionTitle(problem),
            onPrimaryAction: {
                self.handleGatewayProblemPrimaryAction(problem)
            },
            onShowDetails: {
                self.showGatewayProblemDetails = true
            })
            .padding(.horizontal, 12)
            .safeAreaPadding(.top, 10)
            .offset(y: min(self.gatewayToastDragOffset, 0))
            .gesture(self.gatewayToastSwipeGesture)
            // A drag cancelled by toast removal never fires onEnded; clear the
            // offset so the next toast doesn't render shifted up.
            .onDisappear { self.gatewayToastDragOffset = 0 }
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var gatewayToastSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                self.gatewayToastDragOffset = value.translation.height
            }
            .onEnded { value in
                let swipedUp = value.translation.height < -32 || value.predictedEndTranslation.height < -80
                withAnimation(self.gatewayToastAnimation) {
                    if swipedUp {
                        self.isGatewayToastSwipeDismissed = true
                    }
                    self.gatewayToastDragOffset = 0
                }
            }
    }

    private func rootLifecycle(_ content: some View) -> some View {
        self.rootRequestLifecycle(
            self.rootGatewayLifecycle(
                self.rootAppearLifecycle(
                    self.rootVoiceWakeLifecycle(content))))
    }

    private func rootVoiceWakeLifecycle(_ content: some View) -> some View {
        content
            .onChange(of: self.voiceWake.lastTriggeredCommand) { _, newValue in
                guard let newValue else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
                    self.voiceWakeToastText = trimmed
                }

                self.toastDismissGate.schedule(after: .milliseconds(2300)) {
                    OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
                        self.voiceWakeToastText = nil
                    }
                }
            }
    }

    private func rootAppearLifecycle(_ content: some View) -> some View {
        content
            .onAppear {
                self.sidebarModel.setSnoozeWakeUpdatesActive(self.scenePhase == .active)
                self.updateIdleTimer()
                self.evaluateOnboardingPresentation(force: false)
                self.maybeAutoOpenSettings()
                self.maybeOpenSettingsForGatewaySetup()
                self.maybeShowQuickSetup()
                self.applyInitialChatSessionIfNeeded()
                self.handleLiveVoiceStartRequest()
                self.handleOpenChatRequest(self.appModel.openChatRequestID)
            }
            .onChange(of: self.preventSleep) { _, _ in self.updateIdleTimer() }
            .onChange(of: self.appModel.talkMode.isEnabled) { _, _ in self.updateIdleTimer() }
            .onChange(of: self.scenePhase) { _, newValue in
                self.sidebarModel.setSnoozeWakeUpdatesActive(newValue == .active)
                self.updateIdleTimer()
                guard newValue == .active else {
                    self.clearVoiceWakeToast()
                    return
                }
                self.handleLiveVoiceStartRequest()
                self.maybeRequestLocalNetworkAccess(reason: "scene_active")
                Task {
                    await self.appModel.refreshGatewayOverviewIfConnected()
                }
            }
            .onDisappear {
                self.sidebarModel.setSnoozeWakeUpdatesActive(false)
                UIApplication.shared.isIdleTimerDisabled = false
                self.clearVoiceWakeToast()
            }
    }

    private func clearVoiceWakeToast() {
        self.voiceWakeToastText = nil
        self.toastDismissGate.cancel()
    }

    private func rootGatewayProblemLifecycle(_ content: some View) -> some View {
        content
            .onChange(of: self.appModel.gatewayProblemForToast) { _, _ in
                self.isGatewayToastSwipeDismissed = false
            }
    }

    private func rootGatewayLifecycle(_ content: some View) -> some View {
        self.rootGatewayProblemLifecycle(content)
            .onChange(of: self.gatewayController.gateways.count) { _, _ in self.maybeShowQuickSetup() }
            .onChange(of: self.appModel.gatewayServerName) { _, newValue in
                if newValue != nil {
                    self.onboardingComplete = true
                    self.hasConnectedOnce = true
                    OnboardingStateStore.markCompleted(mode: nil)
                }
                self.maybeAutoOpenSettings()
                self.maybeShowQuickSetup()
            }
    }

    private func rootRequestLifecycle(_ content: some View) -> some View {
        content
            .onAppear {
                self.handleDashboardNavigationRequest(self.appModel.dashboardNavigationRequestID)
            }
            .onChange(of: self.onboardingRequestID) { _, _ in
                self.evaluateOnboardingPresentation(force: true)
            }
            .onChange(of: self.shell.settingsPath) { _, _ in
                self.handleSettingsRouteChange(self.shell.activeSettingsRoute)
            }
            .onChange(of: self.showOnboarding) { _, newValue in
                guard !newValue else { return }
                self.maybeRequestLocalNetworkAccess(reason: "onboarding_dismissed")
            }
            .onChange(of: self.appModel.pendingLiveVoiceStart) { _, _ in
                self.handleLiveVoiceStartRequest()
            }
            .onChange(of: self.appModel.openChatRequestID) { _, newValue in
                self.handleOpenChatRequest(newValue)
            }
            .onChange(of: self.appModel.dashboardNavigationRequestID) { _, requestID in
                self.handleDashboardNavigationRequest(requestID)
            }
            .onChange(of: self.appModel.gatewaySetupRequestID) { _, _ in
                self.maybeOpenSettingsForGatewaySetup()
            }
            .onChange(of: NodeAppModel.execApprovalInboxKey(self.appModel.pendingExecApprovalPrompt)) { _, newValue in
                if newValue != self.suppressedExecApprovalForNotificationSettings {
                    self.suppressedExecApprovalForNotificationSettings = nil
                }
            }
    }

    private func handleDashboardNavigationRequest(_ requestID: Int) {
        guard self.appModel.consumeDashboardNavigationRequest(requestID) else { return }
        self.selectSidebarDestination(.overview)
    }

    private func rootPresentation(_ content: some View) -> some View {
        content
            .sheet(isPresented: self.$showGatewayProblemDetails) {
                if let gatewayProblem = self.appModel.lastGatewayProblem {
                    GatewayProblemDetailsSheet(
                        problem: gatewayProblem,
                        primaryActionTitle: self.gatewayProblemPrimaryActionTitle(gatewayProblem),
                        onPrimaryAction: {
                            self.handleGatewayProblemPrimaryAction(gatewayProblem)
                        })
                }
            }
            .sheet(item: self.$presentedSheet) { sheet in
                switch sheet {
                case .quickSetup:
                    GatewayQuickSetupSheet(onUseManualSetup: {
                        self.presentedSheet = nil
                        self.selectSettingsRoute(.gateway)
                    })
                    .environment(self.appModel)
                    .environment(self.gatewayController)
                    .openClawSheetChrome()
                case let .notificationSettings(path):
                    DashboardPageScreen(
                        path: path,
                        title: String(localized: "Notifications"),
                        onClose: { self.presentedSheet = nil })
                case let .sessionDashboard(sessionKey, agentId):
                    NavigationStack {
                        SessionDashboardScreen(sessionKey: sessionKey, agentId: agentId)
                    }
                }
            }
            .fullScreenCover(isPresented: self.$showOnboarding) {
                OnboardingWizardView(
                    allowSkip: true,
                    onRequestLocalNetworkAccess: { reason in
                        self.requestLocalNetworkAccess(reason: reason)
                    },
                    onClose: {
                        self.showOnboarding = false
                    },
                    onComplete: {
                        self.showOnboarding = false
                        self.selectSidebarDestination(.chat)
                    })
                    .environment(self.appModel)
                    .environment(self.voiceWake)
                    .environment(self.gatewayController)
            }
            .gatewayTrustPromptAlert(isEnabled: !self.showOnboarding)
            .deepLinkAgentPromptAlert()
            .execApprovalPromptDialog(
                suppressedApproval: self.activeExecApprovalPromptSuppression)
            .notificationPermissionGuidanceDialog(openNotifications: self.openNotificationSettings)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            self.scenePhase == .active && (self.preventSleep || self.appModel.talkMode.isEnabled)
    }
}

extension RootTabs {
    private func selectSidebarDestination(_ destination: SidebarDestination) {
        self.suppressedExecApprovalForNotificationSettings = nil
        self.shell.land(legacy: destination)
    }

    private func handleOpenChatRequest(_ requestID: Int) {
        guard self.appModel.consumeOpenChatRequest(requestID) else { return }
        self.selectSidebarDestination(.chat)
    }

    private func handleLiveVoiceStartRequest() {
        guard self.didApplyInitialChatSession, self.didEvaluateOnboarding,
              self.scenePhase == .active, self.appModel.pendingLiveVoiceStart
        else { return }
        if !self.showOnboarding {
            self.presentedSheet = nil
            self.showGatewayProblemDetails = false
        }
        self.appModel.consumeLiveVoiceStartRequest(
            isSceneActive: true,
            isOnboardingPresented: self.showOnboarding,
            hasGatewayConfiguration: self.hasExistingGatewayConfig() || self.appModel.gatewayServerName != nil)
    }

    private func selectSettingsRoute(_ route: SettingsRoute) {
        self.suppressedExecApprovalForNotificationSettings = nil
        self.shell.openSettings(route: route)
    }

    private func openNotificationSettings(_ approvalID: String?) {
        if let approvalID {
            self.suppressExecApprovalPromptForNotificationSettings(approvalID)
        }
        let path = Self.notificationSettingsPath(
            servingEnabled: NotificationServingPreference.isEnabled(),
            disclosureAccepted: !PushBuildConfig.current.usesOpenClawHostedRelay
                || PushEnrollmentConsent.disclosureAccepted)
        self.presentedSheet = .notificationSettings(path: path)
    }

    private func suppressExecApprovalPromptForNotificationSettings(_ approvalID: String) {
        guard let approvalID = ExecApprovalIdentifier.key(approvalID),
              let prompt = self.appModel.pendingExecApprovalPrompt,
              ExecApprovalIdentifier.key(prompt.id) == approvalID
        else { return }
        self.suppressedExecApprovalForNotificationSettings = NodeAppModel.execApprovalInboxKey(prompt)
    }

    /// The shell derives the visible route (`AppShellNavigation.activeSettingsRoute`);
    /// the host only drops stale exec-approval suppression when the visible route changes.
    private func handleSettingsRouteChange(_ route: SettingsRoute?) {
        self.suppressedExecApprovalForNotificationSettings = nil
    }

    private func gatewayProblemPrimaryActionTitle(_ problem: GatewayConnectionProblem) -> String? {
        GatewayProblemPrimaryAction.title(
            for: problem,
            retryTitle: "Retry",
            resetTitle: "Reset onboarding",
            nonRetryableTitle: "Open Settings")
    }

    private func handleGatewayProblemPrimaryAction(_ problem: GatewayConnectionProblem) {
        if problem.suggestsOnboardingReset {
            // Reset bumps onboarding.requestID, which re-presents the wizard.
            let instanceId = UserDefaults.standard.string(forKey: "node.instanceId") ?? ""
            Task {
                await GatewayOnboardingReset.reset(appModel: self.appModel, instanceId: instanceId)
            }
        } else if problem.canTrustRotatedCertificate {
            Task { await self.gatewayController.trustRotatedGatewayCertificate(from: problem) }
        } else if GatewayProblemPrimaryAction.handleProtocolMismatchIfNeeded(problem) {
            return
        } else if problem.retryable {
            self.gatewayRetryFailure = nil
            Task {
                if case let .failed(message) = await self.gatewayController.retryGatewayConnection() {
                    self.gatewayRetryFailure = message
                }
            }
        } else {
            self.selectSidebarDestination(.gateway)
        }
    }

    private func evaluateOnboardingPresentation(force: Bool) {
        if force {
            self.showOnboarding = true
            return
        }

        guard !self.didEvaluateOnboarding else { return }
        self.didEvaluateOnboarding = true
        let route = Self.startupPresentationRoute(
            gatewayConnected: self.appModel.gatewayServerName != nil,
            hasConnectedOnce: self.hasConnectedOnce,
            onboardingComplete: self.onboardingComplete,
            hasExistingGatewayConfig: self.hasExistingGatewayConfig(),
            shouldPresentOnLaunch: OnboardingStateStore.shouldPresentOnLaunch(appModel: self.appModel))
        switch route {
        case .none:
            self.maybeRequestLocalNetworkAccess(reason: "root_appear")
        case .onboarding:
            self.showOnboarding = true
        case .settings:
            self.didAutoOpenSettings = true
            self.selectSidebarDestination(.gateway)
            self.maybeRequestLocalNetworkAccess(reason: "root_appear")
        }
    }

    private func hasExistingGatewayConfig() -> Bool {
        if self.appModel.activeGatewayConnectConfig != nil { return true }
        if GatewaySettingsStore.activeGatewayEntry() != nil { return true }

        let preferredStableID = self.preferredGatewayStableID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferredStableID.isEmpty { return true }

        let manualHost = self.manualGatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.manualGatewayEnabled && !manualHost.isEmpty
    }

    private func maybeAutoOpenSettings() {
        guard !self.didAutoOpenSettings else { return }
        guard !self.showOnboarding else { return }
        let route = Self.startupPresentationRoute(
            gatewayConnected: self.appModel.gatewayServerName != nil,
            hasConnectedOnce: self.hasConnectedOnce,
            onboardingComplete: self.onboardingComplete,
            hasExistingGatewayConfig: self.hasExistingGatewayConfig(),
            shouldPresentOnLaunch: false)
        guard route == .settings else { return }
        self.didAutoOpenSettings = true
        self.selectSidebarDestination(.gateway)
        self.maybeRequestLocalNetworkAccess(reason: "auto_open_settings")
    }

    private func maybeOpenSettingsForGatewaySetup() {
        let requestID = self.appModel.gatewaySetupRequestID
        guard requestID != 0, requestID != self.gatewaySetupRequest?.id else { return }
        // The presented onboarding flow owns setup-link staging until it dismisses.
        guard !self.showOnboarding else { return }
        guard let link = appModel.consumePendingGatewaySetupLink() else { return }
        self.showOnboarding = false
        self.presentedSheet = nil
        self.didAutoOpenSettings = true
        self.selectSidebarDestination(.gateway)
        // Root owns delivery so embedded Settings views cannot consume the one-shot link.
        self.gatewaySetupRequest = GatewaySetupRequest(id: requestID, link: link)
        self.requestLocalNetworkAccess(reason: "gateway_setup_deeplink")
    }

    private func handleGatewaySetupRequest(_ requestID: Int) {
        guard self.gatewaySetupRequest?.id == requestID else { return }
        self.gatewaySetupRequest = nil
    }

    private func maybeRequestLocalNetworkAccess(reason: String) {
        guard self.didEvaluateOnboarding else { return }
        guard self.scenePhase == .active else { return }
        guard !self.showOnboarding else { return }
        self.requestLocalNetworkAccess(reason: reason)
    }

    private func requestLocalNetworkAccess(reason: String) {
        guard !self.appModel.isAppleReviewDemoModeEnabled else { return }
        self.gatewayController.requestLocalNetworkAccess(reason: reason)
    }

    private func applyInitialChatSessionIfNeeded() {
        guard !self.didApplyInitialChatSession else { return }
        self.didApplyInitialChatSession = true
        self.appModel.focusChatSession(Self.initialChatSessionKey)
    }

    private func maybeShowQuickSetup() {
        let shouldPresent = Self.shouldPresentQuickSetup(
            quickSetupDismissed: self.quickSetupDismissed,
            showOnboarding: self.showOnboarding,
            hasPresentedSheet: self.presentedSheet != nil,
            gatewayConnected: self.appModel.gatewayServerName != nil,
            hasExistingGatewayConfig: self.hasExistingGatewayConfig(),
            discoveredGatewayCount: self.gatewayController.gateways.count)
        guard shouldPresent else { return }
        self.presentedSheet = .quickSetup
    }
}

private struct RootCameraFlashOverlay: View {
    @Environment(\.scenePhase) private var scenePhase

    var nonce: Int

    @State private var opacity: CGFloat = 0
    @State private var dismissGate = DelayedActionGate()

    var body: some View {
        Color.white
            .opacity(self.opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: self.nonce) { _, _ in
                guard self.scenePhase == .active else {
                    self.clearFlash()
                    return
                }
                self.showFlash()
            }
            .onChange(of: self.scenePhase) { _, newValue in
                guard newValue != .active else { return }
                self.clearFlash()
            }
            .onDisappear { self.clearFlash() }
    }

    private func showFlash() {
        withAnimation(OpenClawMotion.reducedFade) {
            self.opacity = 0.85
        }
        self.dismissGate.schedule(after: .milliseconds(110)) {
            withAnimation(OpenClawMotion.reducedFade) {
                self.opacity = 0
            }
        }
    }

    private func clearFlash() {
        self.opacity = 0
        self.dismissGate.cancel()
    }
}

#if DEBUG
#Preview(
    "Shell iPhone portrait",
    traits: .fixedLayout(width: 393, height: 852),
    .portrait)
{
    RootTabsPreviewHost()
}

#Preview(
    "Shell iPhone connected",
    traits: .fixedLayout(width: 393, height: 852),
    .portrait)
{
    RootTabsPreviewHost(gatewayState: .connected)
}

#Preview(
    "Shell iPhone gateway error",
    traits: .fixedLayout(width: 393, height: 852),
    .portrait)
{
    RootTabsPreviewHost(gatewayState: .error)
}

#Preview(
    "Shell iPhone landscape",
    traits: .fixedLayout(width: 852, height: 393),
    .landscapeLeft)
{
    RootTabsPreviewHost()
        .environment(\.horizontalSizeClass, .regular)
        .environment(\.verticalSizeClass, .compact)
}

#Preview(
    "Shell iPad portrait drawer",
    traits: .fixedLayout(width: 1024, height: 1366),
    .portrait)
{
    RootTabsPreviewHost()
}

#Preview(
    "Shell iPad landscape split",
    traits: .fixedLayout(width: 1366, height: 1024),
    .landscapeLeft)
{
    RootTabsPreviewHost(gatewayState: .connected)
}

#Preview(
    "Shell iPad connecting",
    traits: .fixedLayout(width: 1366, height: 1024),
    .landscapeLeft)
{
    RootTabsPreviewHost(gatewayState: .connecting)
}

#Preview(
    "Shell iPad gateway error",
    traits: .fixedLayout(width: 1366, height: 1024),
    .landscapeLeft)
{
    RootTabsPreviewHost(gatewayState: .error)
}

private struct RootTabsPreviewHost: View {
    @State private var appearanceModel = AppAppearanceModel()
    @State private var appModel: NodeAppModel
    @State private var gatewayController: GatewayConnectionController

    init(gatewayState: RootTabsPreviewGatewayState = .offline) {
        let appModel = NodeAppModel()
        gatewayState.apply(to: appModel)
        _appModel = State(initialValue: appModel)
        _gatewayController = State(
            initialValue: GatewayConnectionController(appModel: appModel, startDiscovery: false))
    }

    var body: some View {
        RootTabs()
            .environment(self.appearanceModel)
            .environment(self.appModel)
            .environment(self.appModel.voiceWake)
            .environment(self.gatewayController)
    }
}

private enum RootTabsPreviewGatewayState {
    case offline
    case connecting
    case connected
    case error

    @MainActor
    func apply(to appModel: NodeAppModel) {
        switch self {
        case .offline:
            break
        case .connecting:
            appModel.gatewayStatusText = "Connecting..."
        case .connected:
            appModel.enterAppleReviewDemoMode()
        case .error:
            appModel.gatewayStatusText = "Gateway error: connection refused"
        }
    }
}

#endif
