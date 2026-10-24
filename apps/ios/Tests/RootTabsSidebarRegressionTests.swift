import Foundation
import Testing
@testable import OpenClaw

/// Regression guards for the native `AppShell` (iOS 26 `TabView`, four bar tabs, no sidebar).
/// The former sidebar / drawer guards were removed together with the code they inspected.
struct RootTabsSidebarRegressionTests {
    // MARK: - Source guards

    @Test func `shell root is a four tab TabView without a sidebar`() throws {
        let source = try String(contentsOf: Self.shellSourceURL("AppShellRootView.swift"), encoding: .utf8)
        let body = try Self.extract(source, from: "TabView(selection:", to: ".accessibilityIdentifier(\"AppShell.Root\")")

        #expect(body.components(separatedBy: "Tab(\n").count == 5)
        for tab in ["chat", "agents", "activity", "settings"] {
            #expect(body.contains("value: AppShellTab.\(tab))"))
        }
        #expect(!body.contains("value: AppShellTab.overview)"))
        #expect(!body.contains("value: AppShellTab.automations)"))
        #expect(body.contains(".tabViewStyle(.sidebarAdaptable)"))
        #expect(body.contains(".tabBarMinimizeBehavior(.onScrollDown)"))
        #expect(!source.contains("RootSidebarShell("))
        #expect(!source.contains("RootSidebar("))
    }

    @Test func `shell tab bar binding maps every destination to a bar tab`() throws {
        let source = try String(contentsOf: Self.shellSourceURL("AppShellRootView.swift"), encoding: .utf8)
        let binding = try Self.extract(
            source,
            from: "private var selectionBinding",
            to: "var body: some View")

        #expect(binding.contains("self.navigation.selection.barTab"))
        #expect(binding.contains("self.navigation.userSelected(newValue)"))
    }

    @Test func `shell tabs host their screens and expose stable identifiers`() throws {
        let tabs = try String(contentsOf: Self.shellSourceURL("AppShellTabs.swift"), encoding: .utf8)
        let root = try String(contentsOf: Self.shellSourceURL("AppShellRootView.swift"), encoding: .utf8)

        for identifier in [
            "AppShell.Chat",
            "AppShell.Agents",
            "AppShell.Agents.Sections",
            "AppShell.Activity",
            "AppShell.Activity.Sections",
            "AppShell.Settings.Back",
        ] {
            #expect(tabs.contains("\"\(identifier)\""))
        }
        #expect(root.contains("AppShellChatView(navigation: self.navigation)"))
        #expect(root.contains("AppShellAgentsView(navigation: self.navigation)"))
        #expect(root.contains("AppShellActivityView(navigation: self.navigation, context: self.context)"))
        #expect(root.contains("AppShellSettingsView(navigation: self.navigation, context: self.context)"))
        // Hosted screens no longer receive a sidebar reveal action.
        #expect(!tabs.contains("headerSidebarAction: self."))
    }

    @Test func `host mounts the shell and no longer owns sidebar split or drawer state`() throws {
        let source = try String(contentsOf: Self.sourceURL("RootTabs.swift"), encoding: .utf8)

        #expect(source.contains("AppShellRootView(navigation: self.shell, context: self.shellContext)"))
        #expect(source.contains("@State private var shell = AppShellNavigation("))
        #expect(!source.contains("sidebarSplitContent"))
        #expect(!source.contains("sidebarDetailShell"))
        #expect(!source.contains("sidebarNavigationPath"))
        #expect(!source.contains("RootSidebarShell("))
    }

    @Test func `settings tab resets to the hub and routes gateway through the shell`() throws {
        let source = try String(contentsOf: Self.shellSourceURL("AppShellModel.swift"), encoding: .utf8)
        let reselect = try Self.extract(
            source,
            from: "private func reselect(",
            to: "\n}")
        let settingsCase = try Self.extract(reselect, from: "case .settings:", to: "case .agents")

        #expect(settingsCase.contains("self.settingsPath.removeAll()"))
        #expect(settingsCase.contains("self.settingsPresentation = .hub"))
    }

    // MARK: - Behaviour

    @Test func `overview and automations share the activity bar tab`() {
        #expect(AppShellTab.agents.barTab == .agents)
        #expect(AppShellTab.settings.barTab == .settings)
        #expect(AppShellTab.activity.barTab == .activity)
        #expect(AppShellTab.overview.barTab == .activity)
        #expect(AppShellTab.automations.barTab == .activity)

        let barTabs = Set(AppShellTab.allCases.map(\.barTab))
        #expect(barTabs == [.chat, .agents, .activity, .settings])
    }

    @Test func `tab accessibility identifiers use the AppShell prefix`() {
        for tab in AppShellTab.allCases {
            #expect(tab.accessibilityIdentifier == "AppShell.Tab.\(tab.rawValue)")
        }
    }

    @Test @MainActor func `activity tab restores the last section after leaving`() {
        let navigation = AppShellNavigation(landing: AppShellLanding(tab: .chat))

        navigation.userSelected(.activity)
        #expect(navigation.selection == .activity)

        navigation.selectActivitySection(.automations)
        #expect(navigation.selection == .automations)

        navigation.userSelected(.settings)
        #expect(navigation.selection == .settings)

        navigation.userSelected(.activity)
        #expect(navigation.selection == .automations)
    }

    @Test @MainActor func `legacy destinations land on the matching tab`() {
        let navigation = AppShellNavigation(landing: AppShellLanding(tab: .chat))

        navigation.land(legacy: .agentsHub)
        #expect(navigation.selection == .agents)
        #expect(navigation.agentsSection == .subagents)

        navigation.land(legacy: .gateway)
        #expect(navigation.selection == .settings)
        #expect(navigation.settingsPresentation == .gateway)
        #expect(navigation.activeSettingsRoute == .gateway)

        navigation.land(legacy: .settings)
        #expect(navigation.selection == .settings)
        #expect(navigation.settingsPresentation == .hub)
        #expect(navigation.activeSettingsRoute == nil)
    }

    // MARK: - Helpers

    private static func iosRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func sourceURL(_ path: String) -> URL {
        self.iosRootURL().appendingPathComponent("Sources/\(path)")
    }

    private static func shellSourceURL(_ file: String) -> URL {
        self.sourceURL("Shell/App/\(file)")
    }

    private static func extract(_ source: String, from start: String, to end: String) throws -> String {
        let startRange = try #require(source.range(of: start))
        let tail = source[startRange.lowerBound...]
        let endRange = try #require(tail.range(of: end))
        return String(tail[..<endRange.lowerBound])
    }
}
