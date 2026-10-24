import SwiftUI

// MARK: - Primary tabs

/// Primary destinations of the native shell. They sit in the floating glass tab bar.
/// Each one maps onto an existing `RootTabs.SidebarDestination`, so deep links,
/// launch arguments and `selectSidebarDestination` keep working unchanged.
enum ShellTab: String, CaseIterable, Hashable, Identifiable {
    case chat
    case workboard
    case activity
    case automations
    case usage

    var id: String {
        self.rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .chat: "Chat"
        case .workboard: "Workboard"
        case .activity: "Activity"
        case .automations: "Automations"
        case .usage: "Usage"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left"
        case .workboard: "folder"
        case .activity: "waveform.path.ecg"
        case .automations: "timer"
        case .usage: "chart.bar.xaxis"
        }
    }

    var accessibilityIdentifier: String {
        "Shell.Tab.\(self.rawValue)"
    }

    var destination: RootTabs.SidebarDestination {
        switch self {
        case .chat: .chat
        case .workboard: .workboard
        case .activity: .activity
        case .automations: .cron
        case .usage: .usage
        }
    }

    init?(destination: RootTabs.SidebarDestination) {
        let match: ShellTab? = ShellTab.allCases.first(where: { (tab: ShellTab) -> Bool in
            tab.destination == destination
        })
        guard let match else { return nil }
        self = match
    }
}

// MARK: - Secondary destinations

/// Reached from the sidebar or from the "More" menu of the tab bar.
/// All of them resolve to native screens through `NativeDestinationRouter` or the settings hub.
enum ShellSecondaryDestination: String, CaseIterable, Hashable, Identifiable {
    case instances
    case settings
    case skillWorkshop
    case dreaming

    var id: String {
        self.rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .instances: "Instances"
        case .settings: "Settings"
        case .skillWorkshop: "Skill Workshop"
        case .dreaming: "Dreaming"
        }
    }

    var systemImage: String {
        switch self {
        case .instances: "dot.radiowaves.left.and.right"
        case .settings: "gearshape"
        case .skillWorkshop: "hammer"
        case .dreaming: "moon.stars"
        }
    }

    var accessibilityIdentifier: String {
        "Shell.More.\(self.rawValue)"
    }

    var destination: RootTabs.SidebarDestination {
        switch self {
        case .instances: .instances
        case .settings: .settings
        case .skillWorkshop: .skillWorkshop
        case .dreaming: .dreaming
        }
    }

    init?(destination: RootTabs.SidebarDestination) {
        let match: ShellSecondaryDestination? = ShellSecondaryDestination.allCases.first(
            where: { (item: ShellSecondaryDestination) -> Bool in
                item.destination == destination
            })
        guard let match else { return nil }
        self = match
    }
}

// MARK: - Landing resolution

/// Where a legacy `SidebarDestination` lands in the shell.
enum ShellLanding: Equatable {
    case primary(ShellTab)
    case secondary(ShellSecondaryDestination)
    /// Screens that live outside the tab bar (Overview, Agents, Files, Sessions, Gateway...).
    case other

    init(destination: RootTabs.SidebarDestination) {
        if let tab = ShellTab(destination: destination) {
            self = .primary(tab)
        } else if let secondary = ShellSecondaryDestination(destination: destination) {
            self = .secondary(secondary)
        } else if destination == .gateway {
            self = .secondary(.settings)
        } else {
            self = .other
        }
    }

    var selectedTab: ShellTab? {
        if case let .primary(tab) = self { return tab }
        return nil
    }

    var isSecondary: Bool {
        if case .secondary = self { return true }
        return false
    }
}
