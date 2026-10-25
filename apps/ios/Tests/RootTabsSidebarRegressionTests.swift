import Foundation
import Testing
@testable import OpenClaw

/// Regression guards for the native `AppShell` (iOS 26 `TabView`, three bar tabs, no sidebar).
/// Bar, left to right: Agents, Home (Overview only, selected at launch), Activity (Activity and
/// Automations behind a segmented control). Settings is not a tab: the full hub opens full screen
/// from the gear button of Home. The former sidebar / drawer guards were removed together with
/// the code they inspected.
struct RootTabsSidebarRegressionTests {
    // MARK: - Source guards

    @Test func `shell root is a three tab TabView ordered agents home activity`() throws {
        let source = try String(contentsOf: Self.shellSourceURL("AppShellRootView.swift"), encoding: .utf8)
        let body = try Self.extract(source, from: "TabView(selection:", to: ".accessibilityIdentifier(\"AppShell.Root\")")

        #expect(body.components(separatedBy: "Tab(\n").count == 4)
        for tab in ["agents", "overview", "activity"] {
            #expect(body.contains("value: AppShellTab.\(tab))"))
        }
        #expect(!body.contains("AppShellTab.settings"))
        #expect(!body.contains("AppShellTab.automations"))
        #expect(!body.contains("AppShellTab.chat"))

        let agents = try #require(body.range(of: "value: AppShellTab.agents)"))
        let overview = try #require(body.range(of: "value: AppShellTab.overview)"))
        let activity = try #require(body.range(of: "value: AppShellTab.activity)"))
        #expect(agents.lowerBound < overview.lowerBound)
        #expect(overview.lowerBound < activity.lowerBound)

        #expect(body.contains(".tabViewStyle(.sidebarAdaptable)"))
        #expect(!source.contains("RootSidebarShell("))
        #expect(!source.contains("RootSidebar("))
    }

    @Test func `shell tab bar binding maps every destination to a bar tab`() throws {
        let source = try String(contentsOf: Self.shellSourceURL("AppShellRootView.swift"), encoding: .utf8)
        let binding = try Self.extract(
            source,
            from: "private var selectionBinding",
            to: "private var coverBinding")

        #expect(binding.contains("self.navigation.selection.barTab"))
        #expect(binding.contains("self.navigation.userSelected(newValue)"))
    }

    @Test func `shell chat and settings share one full screen cover`() throws {
        let source = try String(contentsOf: Self.shellSourceURL("AppShellRootView.swift"), encoding: .utf8)

        #expect(source.components(separatedBy: ".fullScreenCover(").count == 2)
        #expect(source.contains("AppShellChatView(navigation: self.navigation)"))
        #expect(source.contains("AppShellSettingsView(navigation: self.navigation, context: self.context)"))
    }

    @Test func `shell tabs host their screens and expose stable identifiers`() throws {
        let tabs = try String(contentsOf: Self.shellSourceURL("AppShellTabs.swift"), encoding: .utf8)
        let root = try String(contentsOf: Self.shellSourceURL("AppShellRootView.swift"), encoding: .utf8)

        for identifier in [
            "AppShell.Chat",
            "AppShell.Agents",
            "AppShell.Activity",
            "AppShell.Activity.Sections",
            "AppShell.Settings",
            "AppShell.Settings.Close",
            "AppShell.Settings.Back",
        ] {
            #expect(tabs.contains("\"\(identifier)\""))
        }
        #expect(root.contains("AppShellAgentsView(navigation: self.navigation)"))
        #expect(root.contains("AppShellOverviewView(navigation: self.navigation, context: self.context)"))
        #expect(root.contains("AppShellActivityView(navigation: self.navigation, context: self.context)"))
    }

    @Test func `activity tab offers only activity and automations`() throws {
        let tabs = try String(contentsOf: Self.shellSourceURL("AppShellTabs.swift"), encoding: .utf8)
        let activity = try Self.extract(
            tabs,
            from: "struct AppShellActivityView",
            to: "struct AppShellNativeListView")

        #expect(activity.contains("case .activity:"))
        #expect(activity.contains("case .automations:"))
        #expect(!activity.contains("case .overview:"))
        #expect(!activity.contains("AppShellOverviewView"))
    }

    @Test func `home gear button opens the full settings hub`() throws {
        let overview = try String(contentsOf: Self.shellSourceURL("AppShellOverviewView.swift"), encoding: .utf8)
        let tabs = try String(contentsOf: Self.shellSourceURL("AppShellTabs.swift"), encoding: .utf8)

        #expect(overview.contains("openSettings: self.openSettings,"))
        let action = try Self.extract(
            overview,
            from: "private func openSettings()",
            to: "private func openGateway()")
        #expect(action.contains("self.navigation.openSettings(route: nil)"))

        let settings = try Self.extract(tabs, from: "struct AppShellSettingsView", to: "private var gateway")
        #expect(settings.contains("SettingsHubScreen("))
        #expect(settings.contains("headerSidebarAction: self.closeAction"))
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

    @Test func `closing settings resets the hub`() throws {
        let source = try String(contentsOf: Self.shellSourceURL("AppShellModel.swift"), encoding: .utf8)
        let reset = try Self.extract(
            source,
            from: "private func resetSettings()",
            to: "\n    }")

        #expect(reset.contains("self.isSettingsPresented = false"))
        #expect(reset.contains("self.settingsPath.removeAll()"))
        #expect(reset.contains("self.settingsPresentation = .hub"))
    }

    // MARK: - Behaviour

    @Test func `bar has exactly agents home activity and launches on home`() {
        #expect(AppShellTab.barTabs == [.agents, .overview, .activity])
        #expect(AppShellTab.launchTab == .overview)

        #expect(AppShellTab.agents.barTab == .agents)
        #expect(AppShellTab.overview.barTab == .overview)
        #expect(AppShellTab.activity.barTab == .activity)
        #expect(AppShellTab.automations.barTab == .activity)

        let barTabs = Set(AppShellTab.allCases.map(\.barTab))
        #expect(barTabs == [.agents, .overview, .activity])
    }

    @Test func `activity sections are activity and automations`() {
        #expect(AppShellActivitySection.allCases == [.activity, .automations])
        #expect(AppShellActivitySection(tab: .automations) == .automations)
        #expect(AppShellActivitySection(tab: .activity) == .activity)
        #expect(AppShellActivitySection.activity.tab == .activity)
        #expect(AppShellActivitySection.automations.tab == .automations)
    }

    @Test func `tab accessibility identifiers use the AppShell prefix`() {
        for tab in AppShellTab.allCases {
            #expect(tab.accessibilityIdentifier == "AppShell.Tab.\(tab.rawValue)")
        }
    }

    @Test @MainActor func `default navigation starts on home`() {
        let navigation = AppShellNavigation()

        #expect(navigation.selection == .overview)
        #expect(!navigation.isSettingsPresented)
        #expect(!navigation.isChatPresented)
        #expect(AppShellLanding(legacy: .overview).tab == .overview)
    }

    @Test @MainActor func `activity tab restores the last section after leaving`() {
        let navigation = AppShellNavigation(landing: AppShellLanding(tab: .overview))

        navigation.userSelected(.activity)
        #expect(navigation.selection == .activity)

        navigation.selectActivitySection(.automations)
        #expect(navigation.selection == .automations)

        navigation.userSelected(.overview)
        #expect(navigation.selection == .overview)

        navigation.userSelected(.activity)
        #expect(navigation.selection == .automations)
    }

    @Test @MainActor func `legacy destinations land on the matching tab`() {
        let navigation = AppShellNavigation()

        navigation.land(legacy: .agentsHub)
        #expect(navigation.selection == .agents)
        #expect(navigation.agentsSection == .subagents)

        navigation.land(legacy: .cron)
        #expect(navigation.selection == .automations)
        #expect(navigation.selection.barTab == .activity)

        navigation.land(legacy: .activity)
        #expect(navigation.selection == .activity)

        navigation.land(legacy: .chat)
        #expect(navigation.selection == .overview)
        #expect(navigation.isChatPresented)
        #expect(navigation.coverKind == .chat)
    }

    @Test @MainActor func `settings and gateway landings open the settings hub from home`() {
        let navigation = AppShellNavigation()

        navigation.land(legacy: .gateway)
        #expect(navigation.selection == .overview)
        #expect(navigation.isSettingsPresented)
        #expect(navigation.coverKind == .settings)
        #expect(navigation.settingsPresentation == .gateway)
        #expect(navigation.activeSettingsRoute == .gateway)

        navigation.land(legacy: .settings)
        #expect(navigation.selection == .overview)
        #expect(navigation.isSettingsPresented)
        #expect(navigation.settingsPresentation == .hub)
        #expect(navigation.activeSettingsRoute == nil)

        navigation.land(legacy: .overview)
        #expect(!navigation.isSettingsPresented)
        #expect(navigation.activeSettingsRoute == nil)
    }

    @Test @MainActor func `opening settings keeps the selected tab and closing returns to it`() {
        let navigation = AppShellNavigation()
        navigation.land(legacy: .agents)

        navigation.openSettings(route: nil)
        #expect(navigation.selection == .agents)
        #expect(navigation.isSettingsPresented)
        #expect(navigation.coverKind == .settings)

        navigation.closeSettings()
        #expect(!navigation.isSettingsPresented)
        #expect(navigation.selection == .agents)
    }

    @Test @MainActor func `settings route pushes inside the hub`() {
        let navigation = AppShellNavigation()

        navigation.openSettings(route: .approvals)
        #expect(navigation.settingsPresentation == .hub)
        #expect(navigation.settingsPath == [.approvals])
        #expect(navigation.activeSettingsRoute == .approvals)

        navigation.showSettingsHub()
        #expect(navigation.settingsPath.isEmpty)
        #expect(navigation.activeSettingsRoute == nil)
    }

    @Test @MainActor func `chat and settings swap inside the shared cover`() {
        let navigation = AppShellNavigation()

        navigation.openChat()
        #expect(navigation.isChatPresented)
        #expect(navigation.coverKind == .chat)

        navigation.openSettings(route: nil)
        #expect(!navigation.isChatPresented)
        #expect(navigation.isSettingsPresented)
        #expect(navigation.coverKind == .settings)

        navigation.openChat()
        #expect(navigation.isChatPresented)
        #expect(!navigation.isSettingsPresented)
        #expect(navigation.coverKind == .chat)

        navigation.dismissCover()
        #expect(!navigation.isChatPresented)
        #expect(!navigation.isSettingsPresented)
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
