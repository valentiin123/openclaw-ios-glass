import Observation
import OpenClawKit
import SwiftUI

// MARK: - Root tabs

/// Top-level destinations of the app shell.
///
/// The tab bar holds exactly three tabs, left to right: Agents, Home, Activity (`barTabs`).
/// - `overview` is the Home tab (title "Home"). It hosts only the Overview and is selected at launch.
/// - `activity` and `automations` are the two sections of the Activity tab, chosen with a
///   segmented control. Both stay valid destinations (deep links, `RootTabs` reads `selection`).
/// There is no Settings tab: the Settings hub opens full screen over the shell from the gear
/// button of Home (`AppShellNavigation.isSettingsPresented`). There is no Chat tab either: the
/// system chat (main session) is presented full screen (`AppShellNavigation.isChatPresented`)
/// and opened from the Home "More" menu ("Talk to OpenClaw").
enum AppShellTab: String, CaseIterable, Hashable, Identifiable {
    case overview
    case agents
    case activity
    case automations

    /// Tab selected when the app launches without a requested destination.
    static let launchTab: AppShellTab = .overview

    /// The three tabs of the bar, left to right.
    static let barTabs: [AppShellTab] = [.agents, .overview, .activity]

    var id: String {
        self.rawValue
    }

    /// Keys reuse existing localized titles ("Home", "Activity", "Automations", "Agents").
    var title: LocalizedStringKey {
        switch self {
        case .overview: "Home"
        case .agents: "Agents"
        case .activity: "Activity"
        case .automations: "Automations"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "house"
        case .agents: "person.2"
        case .activity: "waveform.path.ecg"
        case .automations: "timer"
        }
    }

    var accessibilityIdentifier: String {
        "AppShell.Tab.\(self.rawValue)"
    }

    /// Tab shown in the bar for this destination. Activity and Automations share the
    /// Activity tab, so the bar stays at three items.
    var barTab: AppShellTab {
        switch self {
        case .activity, .automations: .activity
        case .overview, .agents: self
        }
    }

    var isInCompactTabBar: Bool {
        self == self.barTab
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

// MARK: - Activity sections

/// Sections of the Activity tab (Activity, Automations). Each maps to an `AppShellTab`
/// destination, so legacy landings (`.activity`, `.cron`) keep working and the host can
/// still read `selection`.
enum AppShellActivitySection: String, CaseIterable, Hashable, Identifiable {
    case activity
    case automations

    var id: String {
        self.rawValue
    }

    init(tab: AppShellTab) {
        switch tab {
        case .automations: self = .automations
        case .overview, .agents, .activity: self = .activity
        }
    }

    var tab: AppShellTab {
        switch self {
        case .activity: .activity
        case .automations: .automations
        }
    }

    var title: OpenClawTextValue {
        switch self {
        case .activity: "Activity"
        case .automations: "Automations"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: "waveform.path.ecg"
        case .automations: "timer"
        }
    }
}

// MARK: - Secondary destinations

/// Screens reached from the Home menu. Each hosted screen owns its NavigationStack,
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

/// Landing representation for the Home tab. `.sessions` is pushed on the Home stack;
/// `.more` is converted by `AppShellNavigation` into a sheet (`presentedMore`).
enum AppShellHomeRoute: Hashable {
    case sessions
    case more(AppShellMoreItem)
}

/// What the Settings full-screen cover shows. The hub is the normal presentation. A Gateway
/// landing shows the direct Gateway screen (the only place a pending gateway setup request is
/// consumed) with a back button that returns to the hub.
enum AppShellSettingsPresentation: Equatable {
    case hub
    case gateway
}

/// Content of the single full-screen cover of the shell. Chat and Settings share one cover so
/// that moving from one to the other swaps content instead of dismissing and presenting again.
enum AppShellCover: Equatable {
    case chat
    case settings
}

// MARK: - Legacy mapping

/// Resolved landing spot for a legacy `RootTabs.SidebarDestination`
/// (launch arguments, deep links, `selectSidebarDestination` call sites).
struct AppShellLanding: Equatable {
    var tab: AppShellTab
    var homeRoute: AppShellHomeRoute?
    var agentsSection: AppShellAgentsSection?
    var settingsRoute: SettingsRoute?
    /// True when the landing opens the system chat (full screen) over the shell.
    var presentsChat: Bool
    /// True when the landing opens the Settings hub (full screen) over the shell.
    var presentsSettings: Bool

    init(tab: AppShellTab) {
        self.tab = tab
        self.presentsChat = false
        self.presentsSettings = false
        self.homeRoute = nil
        self.agentsSection = nil
        self.settingsRoute = nil
    }

    init(legacy destination: RootTabs.SidebarDestination) {
        self.init(tab: AppShellTab.launchTab)
        switch destination {
        case .chat:
            // No Chat tab: the chat is presented over Home.
            self.tab = .overview
            self.presentsChat = true
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
            self.landOnSettings(route: nil)
        case .settings:
            self.landOnSettings(route: nil)
        case .gateway:
            self.landOnSettings(route: .gateway)
        }
    }

    private mutating func land(more item: AppShellMoreItem) {
        self.tab = .overview
        self.homeRoute = .more(item)
    }

    /// Settings open from Home: the tab underneath is Home and the hub is shown full screen.
    private mutating func landOnSettings(route: SettingsRoute?) {
        self.tab = .overview
        self.presentsSettings = true
        self.settingsRoute = route
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
    /// System chat (main session) presented full screen over the shell.
    var isChatPresented: Bool = false
    /// Settings hub presented full screen over the shell (opened from the Home gear button).
    var isSettingsPresented: Bool = false
    /// Content of the shared full-screen cover. Kept after dismissal so the dismissal animation
    /// still shows the screen that is leaving.
    var coverKind: AppShellCover = .chat
    private(set) var resetTokens: [AppShellTab: Int] = [:]
    @ObservationIgnored private var lastActivitySection: AppShellActivitySection = .activity

    init(landing: AppShellLanding = AppShellLanding(tab: AppShellTab.launchTab)) {
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

    /// Called by the tab bar binding with one of the three bar tabs. Re-selecting the current
    /// tab returns it to its root; entering Activity restores the last section used there.
    func userSelected(_ tab: AppShellTab) {
        if tab == self.selection.barTab {
            self.reselect(self.selection)
        } else if tab == .activity {
            self.move(to: self.lastActivitySection.tab)
        } else {
            self.move(to: tab)
        }
    }

    /// Segmented control of the Activity tab (Activity, Automations).
    func selectActivitySection(_ section: AppShellActivitySection) {
        guard section.tab != self.selection else { return }
        self.presentedMore = nil
        self.move(to: section.tab)
    }

    func openSessions() {
        self.presentedMore = nil
        self.move(to: .overview)
        self.homePath = [.sessions]
    }

    func open(more item: AppShellMoreItem) {
        self.move(to: .overview)
        self.homePath = []
        self.presentedMore = item
    }

    /// Automations is a section of the Activity tab.
    func openAutomations() {
        self.move(to: .automations)
    }

    /// Presents the system chat full screen over the current tab (no tab switch).
    func openChat() {
        self.presentedMore = nil
        self.resetSettings()
        self.coverKind = .chat
        self.isChatPresented = true
    }

    func closeChat() {
        self.isChatPresented = false
    }

    /// Opens the Settings hub full screen, on a given route, or on the hub root when `route`
    /// is nil. The selected tab does not change, so closing Settings returns to the same place.
    func openSettings(route: SettingsRoute?) {
        self.presentedMore = nil
        self.isChatPresented = false
        self.presentSettings(route: route)
    }

    func closeSettings() {
        self.resetSettings()
    }

    /// Leaves the direct Gateway screen and shows the hub root.
    func showSettingsHub() {
        self.settingsPresentation = .hub
        self.settingsPath.removeAll()
    }

    /// Dismisses whichever screen the full-screen cover is showing.
    func dismissCover() {
        self.isChatPresented = false
        self.resetSettings()
    }

    /// Route currently visible in Settings, or nil when Settings is closed / on the hub root.
    /// Replaces `RootTabs.activeSettingsRoute` (exec-approval prompt suppression).
    var activeSettingsRoute: SettingsRoute? {
        guard self.isSettingsPresented else { return nil }
        if let last = self.settingsPath.last { return last }
        return self.settingsPresentation == .gateway ? .gateway : nil
    }

    func resetToken(for tab: AppShellTab) -> Int {
        self.resetTokens[tab] ?? 0
    }

    /// Section the Activity page shows. While Activity is the selected bar tab it follows the
    /// selection; otherwise it is the section the tab will restore when entered (`userSelected`),
    /// so the page is already correct while it slides in and its content never swaps mid-swipe.
    var displayedActivitySection: AppShellActivitySection {
        if self.selection.barTab == .activity {
            return AppShellActivitySection(tab: self.selection)
        }
        return self.lastActivitySection
    }

    // MARK: Internals

    /// Single place that changes `selection`, so the Activity tab can remember its section.
    private func move(to tab: AppShellTab) {
        if self.selection.barTab == .activity, tab.barTab != .activity {
            self.lastActivitySection = AppShellActivitySection(tab: self.selection)
        }
        self.selection = tab
    }

    private func apply(_ landing: AppShellLanding) {
        if landing.presentsChat {
            self.coverKind = .chat
        }
        self.isChatPresented = landing.presentsChat
        self.move(to: landing.tab)
        if let section = landing.agentsSection {
            self.agentsSection = section
        }
        switch landing.tab {
        case .overview:
            self.applyHome(landing)
        case .agents, .activity, .automations:
            break
        }
        self.applySettings(landing)
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
        guard landing.presentsSettings else {
            self.resetSettings()
            return
        }
        self.isChatPresented = false
        self.presentSettings(route: landing.settingsRoute)
    }

    private func presentSettings(route: SettingsRoute?) {
        self.coverKind = .settings
        self.isSettingsPresented = true
        if route == .gateway {
            self.settingsPresentation = .gateway
            self.settingsPath = []
        } else if let route {
            self.settingsPresentation = .hub
            self.settingsPath = [route]
        } else {
            self.settingsPresentation = .hub
            self.settingsPath = []
        }
    }

    private func resetSettings() {
        self.isSettingsPresented = false
        self.settingsPath.removeAll()
        self.settingsPresentation = .hub
    }

    private func reselect(_ tab: AppShellTab) {
        switch tab {
        case .overview:
            self.homePath.removeAll()
        case .agents, .activity, .automations:
            let next: Int = self.resetToken(for: tab) + 1
            self.resetTokens[tab] = next
        }
    }
}
