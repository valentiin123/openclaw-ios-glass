import OpenClawKit
import SwiftUI

// MARK: - Root tabs

/// Top-level destinations of the shell.
///
/// Five of them live in the compact tab bar. `automations` is a real tab too, but it is
/// hidden from the iPhone tab bar (a tab bar holds five items before iOS adds "More").
/// It appears in the iPad sidebar and is reached from Overview on iPhone.
enum ShellTab: String, CaseIterable, Hashable, Identifiable {
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
        "Shell.Tab.\(self.rawValue)"
    }

    /// Shown in the compact (iPhone) tab bar.
    var isInCompactTabBar: Bool {
        self != .automations
    }

    var label: some View {
        Label {
            Text(self.title)
        } icon: {
            Image(systemName: self.systemImage)
        }
        .accessibilityIdentifier(self.accessibilityIdentifier)
    }
}

// MARK: - Secondary destinations

/// Screens reachable from Overview > "More" that are not worth a tab.
/// Each one is presented in a sheet because the hosted screens own their NavigationStack.
enum ShellSecondaryDestination: String, CaseIterable, Hashable, Identifiable {
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

    /// Plain string handed to `NativeDestinationRouter`, which expects `String`.
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

    /// Dashboard path for destinations backed by `NativeDestinationRouter`; nil for Docs.
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
}

/// Pushed on the Overview stack.
enum ShellHomeRoute: Hashable {
    case sessions
}

// MARK: - Legacy mapping

/// Resolved landing spot for a legacy `RootTabs.SidebarDestination`
/// (launch arguments, deep links, `selectSidebarDestination` call sites).
struct ShellLandingTarget: Equatable {
    var tab: ShellTab = .chat
    var homeRoute: ShellHomeRoute?
    var secondary: ShellSecondaryDestination?
    var settingsRoute: SettingsRoute?
    var agentsSection: ShellAgentsSection?

    init(tab: ShellTab) {
        self.tab = tab
    }

    init(legacy destination: RootTabs.SidebarDestination) {
        switch destination {
        case .chat:
            self.tab = .chat
        case .overview:
            self.tab = .overview
        case .activity:
            self.tab = .activity
        case .agents:
            self.tab = .agents
            self.agentsSection = .roster
        case .agentsHub:
            self.tab = .agents
            self.agentsSection = .subagents
        case .files:
            self.tab = .agents
            self.agentsSection = .files
        case .cron:
            self.tab = .automations
        case .sessions:
            self.tab = .overview
            self.homeRoute = .sessions
        case .usage:
            self.tab = .overview
            self.secondary = .usage
        case .workboard:
            self.tab = .overview
            self.secondary = .workboard
        case .skillWorkshop:
            self.tab = .overview
            self.secondary = .skillWorkshop
        case .instances:
            self.tab = .overview
            self.secondary = .instances
        case .dreaming:
            self.tab = .overview
            self.secondary = .dreaming
        case .docs:
            self.tab = .overview
            self.secondary = .docs
        case .desktop, .terminal:
            // WebView-backed pages are out of the native shell; Settings is the closest owner.
            self.tab = .settings
        case .settings:
            self.tab = .settings
        case .gateway:
            self.tab = .settings
            self.settingsRoute = .gateway
        }
    }
}
