import Observation
import SwiftUI

// MARK: - Small value types

/// Sections of the Agents tab. The roster and the files list come from `AgentProTab`;
/// subagents come from `AgentsHubScreen`.
enum ShellAgentsSection: String, CaseIterable, Hashable, Identifiable {
    case roster
    case subagents
    case files

    var id: String {
        self.rawValue
    }
}

/// The Settings tab shows the hub. A gateway deep link lands on the Gateway screen directly,
/// which is also where a pending gateway setup request is delivered.
enum ShellSettingsPresentation: Equatable {
    case hub
    case gateway
}

// MARK: - Navigation state

/// Single owner of the shell's navigation state. `RootTabs` keeps one instance in `@State`
/// and passes it to `ShellRootView`. Every legacy `selectSidebarDestination(_:)` call site
/// becomes `land(on: ShellLandingTarget(legacy:))`.
@MainActor
@Observable
final class ShellNavigationState {
    var selection: ShellTab
    var homePath: [ShellHomeRoute] = []
    var settingsPath: [SettingsRoute] = []
    var settingsPresentation: ShellSettingsPresentation = .hub
    var agentsSection: ShellAgentsSection = .roster
    var secondary: ShellSecondaryDestination?
    private(set) var resetTokens: [ShellTab: Int] = [:]

    init(landing: ShellLandingTarget = ShellLandingTarget(tab: .chat)) {
        self.selection = landing.tab
        self.apply(landing)
    }

    // MARK: Entry points

    func land(on target: ShellLandingTarget) {
        self.apply(target)
    }

    func select(_ tab: ShellTab) {
        self.selection = tab
    }

    /// Called by the tab bar binding. Re-selecting the current tab returns it to its root.
    func userSelected(_ tab: ShellTab) {
        if tab == self.selection {
            self.reselect(tab)
        } else {
            self.selection = tab
        }
    }

    func showSessions() {
        self.secondary = nil
        self.selection = .overview
        self.homePath = [.sessions]
    }

    func present(_ destination: ShellSecondaryDestination) {
        self.secondary = destination
    }

    func dismissSecondary() {
        self.secondary = nil
    }

    /// Opens Settings on a given route, or on the hub root when `route` is nil.
    func openSettings(route: SettingsRoute?) {
        var target = ShellLandingTarget(tab: .settings)
        target.settingsRoute = route
        self.apply(target)
    }

    func resetToken(for tab: ShellTab) -> Int {
        self.resetTokens[tab] ?? 0
    }

    // MARK: Internals

    private func apply(_ target: ShellLandingTarget) {
        self.selection = target.tab
        self.secondary = target.secondary
        if let section = target.agentsSection {
            self.agentsSection = section
        }
        switch target.tab {
        case .overview:
            self.applyHome(target)
        case .settings:
            self.applySettings(target)
        case .chat, .agents, .activity, .automations:
            break
        }
    }

    private func applyHome(_ target: ShellLandingTarget) {
        if let route = target.homeRoute {
            self.homePath = [route]
        } else {
            self.homePath = []
        }
    }

    private func applySettings(_ target: ShellLandingTarget) {
        guard let route = target.settingsRoute else {
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

    private func reselect(_ tab: ShellTab) {
        switch tab {
        case .overview:
            self.homePath.removeAll()
        case .settings:
            self.settingsPath.removeAll()
            self.settingsPresentation = .hub
        case .agents, .activity, .automations:
            let next = self.resetToken(for: tab) + 1
            self.resetTokens[tab] = next
        case .chat:
            break
        }
    }
}
