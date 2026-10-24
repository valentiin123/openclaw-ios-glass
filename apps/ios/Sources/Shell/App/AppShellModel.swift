import Observation
import OpenClawKit
import SwiftUI

// MARK: - Root tabs

/// Top-level destinations of the app shell.
///
/// Five of them live in the iPhone tab bar. `automations` is a real tab too, but it is
/// hidden from the compact tab bar (the bar stays at five items). It shows in the iPad
/// sidebar and is reached from the Overview menu on iPhone.
enum AppShellTab: String, CaseIterable, Hashable, Identifiable {
    case overview
    case chat
    case agents
    case activity
    case automations
    case settings

    var id: String {
        self.rawValue
    }

    /// Keys reuse the existing `SidebarDestination` titles so current translations apply.
    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .chat: "Chat"
        case .agents: "Agents"
        case .activity: "Activity"
        case .automations: "Automations"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "chart.bar"
        case .chat: "bubble.left"
        case .agents: "person.2"
        case .activity: "waveform.path.ecg"
        case .automations: "timer"
        case .settings: "gearshape"
        }
    }

    var accessibilityIdentifier: String {
        "AppShell.Tab.\(self.rawValue)"
    }

    var isInCompactTabBar: Bool {
        self != .automations
    }
}

// MARK: - Agents sections

/// Sections of the Agents tab. Roster and files come from `AgentProTab`;
/// subagents come from `AgentsHubScreen`.
enum AppShellAgentsSection: String, CaseIterable, Hashable, Identifiable {
    case roster
    case subagents
    case files

    var id: String {
        self.rawValue
    }

    var title: OpenClawTextValue {
        switch self {
        case .roster: "Agents"
        case .subagents: "Subagents"
        case .files: "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .roster: "person.2"
        case .subagents: "person.3"
        case .files: "folder"
        }
    }
}

// MARK: - Secondary destinations

/// Screens reached from the Overview menu. Each hosted screen owns its NavigationStack,
/// so they are presented in a sheet rather than pushed (no nested stacks).
enum AppShellMoreItem: String, CaseIterable, Hashable, Identifiable {
    case usage
    case skillWorkshop
    case instances
    case dreaming
    case workboard
    case docs

    var id: String {
        self.rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .usage: "Usage"
        case .skillWorkshop: "Skill Workshop"
        case .instances: "Instances"
        case .dreaming: "Dreaming"
        case .workboard: "Workboard"
        case .docs: "Docs"
        }
    }

    /// Plain string for `NativeDestinationRouter`, which takes `String`.
    var titleString: String {
        switch self {
        case .usage: String(localized: "Usage")
        case .skillWorkshop: String(localized: "Skill Workshop")
        case .instances: String(localized: "Instances")
        case .dreaming: String(localized: "Dreaming")
        case .workboard: String(localized: "Workboard")
        case .docs: String(localized: "Docs")
        }
    }

    var systemImage: String {
        switch self {
        case .usage: "chart.bar.xaxis"
        case .skillWorkshop: "hammer"
        case .instances: "dot.radiowaves.left.and.right"
        case .dreaming: "moon.stars"
        case .workboard: "folder"
        case .docs: "book"
        }
    }

    /// Dashboard path served by `NativeDestinationRouter`; nil for Docs.
    var dashboardPath: String? {
        switch self {
        case .usage: DashboardRouteMap.usagePagePath
        case .skillWorkshop: DashboardRouteMap.skillWorkshopPagePath
        case .instances: DashboardRouteMap.devicesSettingsPath
        case .dreaming: DashboardRouteMap.dreamingPagePath
        case .workboard: DashboardRouteMap.workboardPagePath
        case .docs: nil
        }
    }

    var accessibilityIdentifier: String {
        "AppShell.More.\(self.rawValue)"
    }
}

/// Landing representation for the Overview tab. `.sessions` is pushed on the Overview stack;
/// `.more` is converted by `AppShellNavigation` into a sheet (`presentedMore`).
enum AppShellHomeRoute: Hashable {
    case sessions
    case more(AppShellMoreItem)
}

/// The Settings tab shows the hub. A gateway deep link lands on the Gateway screen directly,
/// which is also where a pending gateway setup request is delivered.
enum AppShellSettingsPresentation: Equatable {
    case hub
    case gateway
}

// MARK: - Legacy mapping

/// Resolved landing spot for a legacy `RootTabs.SidebarDestination`
/// (launch arguments, deep links, `selectSidebarDestination` call sites).
struct AppShellLanding: Equatable {
    var tab: AppShellTab
    var homeRoute: AppShellHomeRoute?
    var agentsSection: AppShellAgentsSection?
    var settingsRoute: SettingsRoute?

    init(tab: AppShellTab) {
        self.tab = tab
        self.homeRoute = nil
        self.agentsSection = nil
        self.settingsRoute = nil
    }

    init(legacy destination: RootTabs.SidebarDestination) {
        self.init(tab: .chat)
        switch destination {
        case .chat:
            self.tab = .chat
        case .overview:
            self.tab = .overview
        case .activity:
            self.tab = .activity
        case .cron:
            self.tab = .automations
        case .agents:
            self.tab = .agents
            self.agentsSection = .roster
        case .agentsHub:
            self.tab = .agents
            self.agentsSection = .subagents
        case .files:
            self.tab = .agents
            self.agentsSection = .files
        case .sessions:
            self.tab = .overview
            self.homeRoute = .sessions
        case .usage:
            self.land(more: .usage)
        case .workboard:
            self.land(more: .workboard)
        case .skillWorkshop:
            self.land(more: .skillWorkshop)
        case .instances:
            self.land(more: .instances)
        case .dreaming:
            self.land(more: .dreaming)
        case .docs:
            self.land(more: .docs)
        case .desktop, .terminal:
            // WebView-backed pages are not part of the native shell.
            self.tab = .settings
        case .settings:
            self.tab = .settings
        case .gateway:
            self.tab = .settings
            self.settingsRoute = .gateway
        }
    }

    private mutating func land(more item: AppShellMoreItem) {
        self.tab = .overview
        self.homeRoute = .more(item)
    }
}

// MARK: - Navigation state

/// Single owner of the shell's navigation state. The host keeps one instance in `@State`
/// and passes it to `AppShellRootView`. Every legacy `selectSidebarDestination(_:)` call
/// becomes `navigation.land(legacy:)`.
@MainActor
@Observable
final class AppShellNavigation {
    var selection: AppShellTab
    var homePath: [AppShellHomeRoute] = []
    var settingsPath: [SettingsRoute] = []
    var settingsPresentation: AppShellSettingsPresentation = .hub
    var agentsSection: AppShellAgentsSection = .roster
    var presentedMore: AppShellMoreItem?
    private(set) var resetTokens: [AppShellTab: Int] = [:]

    init(landing: AppShellLanding = AppShellLanding(tab: .chat)) {
        self.selection = landing.tab
        self.apply(landing)
    }

    // MARK: Entry points

    func land(legacy destination: RootTabs.SidebarDestination) {
        self.apply(AppShellLanding(legacy: destination))
    }

    func land(on landing: AppShellLanding) {
        self.apply(landing)
    }

    /// Called by the tab selection binding. Re-selecting the current tab returns it to its root.
    func userSelected(_ tab: AppShellTab) {
        if tab == self.selection {
            self.reselect(tab)
        } else {
            self.selection = tab
        }
    }

    func openSessions() {
        self.presentedMore = nil
        self.selection = .overview
        self.homePath = [.sessions]
    }

    func open(more item: AppShellMoreItem) {
        self.selection = .overview
        self.homePath = []
        self.presentedMore = item
    }

    func openAutomations() {
        self.selection = .automations
    }

    func openChat() {
        self.selection = .chat
    }

    /// Opens Settings on a given route, or on the hub root when `route` is nil.
    func openSettings(route: SettingsRoute?) {
        var landing = AppShellLanding(tab: .settings)
        landing.settingsRoute = route
        self.apply(landing)
    }

    /// Route currently visible in Settings, or nil outside Settings / on the hub root.
    /// Replaces `RootTabs.activeSettingsRoute` (exec-approval prompt suppression).
    var activeSettingsRoute: SettingsRoute? {
        guard self.selection == .settings else { return nil }
        if let last = self.settingsPath.last { return last }
        return self.settingsPresentation == .gateway ? .gateway : nil
    }

    func resetToken(for tab: AppShellTab) -> Int {
        self.resetTokens[tab] ?? 0
    }

    // MARK: Internals

    private func apply(_ landing: AppShellLanding) {
        self.selection = landing.tab
        if let section = landing.agentsSection {
            self.agentsSection = section
        }
        switch landing.tab {
        case .overview:
            self.applyHome(landing)
        case .settings:
            self.applySettings(landing)
        case .chat, .agents, .activity, .automations:
            break
        }
    }

    private func applyHome(_ landing: AppShellLanding) {
        self.presentedMore = nil
        guard let route = landing.homeRoute else {
            self.homePath = []
            return
        }
        if case let .more(item) = route {
            self.homePath = []
            self.presentedMore = item
        } else {
            self.homePath = [route]
        }
    }

    private func applySettings(_ landing: AppShellLanding) {
        guard let route = landing.settingsRoute else {
            self.settingsPresentation = .hub
            self.settingsPath = []
            return
        }
        if route == .gateway {
            self.settingsPresentation = .gateway
            self.settingsPath = []
        } else {
            self.settingsPresentation = .hub
            self.settingsPath = [route]
        }
    }

    private func reselect(_ tab: AppShellTab) {
        switch tab {
        case .overview:
            self.homePath.removeAll()
        case .settings:
            self.settingsPath.removeAll()
            self.settingsPresentation = .hub
        case .agents, .activity, .automations:
            let next: Int = self.resetToken(for: tab) + 1
            self.resetTokens[tab] = next
        case .chat:
            break
        }
    }
}
