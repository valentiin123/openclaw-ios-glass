import OpenClawKit
import SwiftUI

// MARK: - Root

/// Root of the native shell: an iOS 26 `TabView` (Liquid Glass tab bar drawn by the system).
///
/// - Three tabs only, left to right: Agents, Home, Activity. Home hosts only the Overview and
///   is selected at launch (`AppShellTab.launchTab`). Activity hosts Activity and Automations
///   behind a segmented control.
/// - There is no Settings tab: the Settings hub opens full screen from the gear button of Home.
///   There is no Chat tab either: the system chat (main session) opens full screen from the
///   Home "More" menu ("Talk to OpenClaw").
/// - Chat and Settings share one full-screen cover (`AppShellNavigation.coverKind`), so
///   switching from one to the other swaps the content instead of presenting twice.
/// - The tab bar is never hidden or inset by hand: every hosted screen lets the system apply
///   the bottom safe area. The full-screen cover hides the tab bar, so the chat composer never
///   overlaps it and stays above the keyboard.
/// - Glass stays on navigation and controls; hosted screens keep their opaque grouped backgrounds.
struct AppShellRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var navigation: AppShellNavigation
    let context: AppShellContext

    /// The bar only knows three tabs; Automations maps to the Activity tab.
    private var selectionBinding: Binding<AppShellTab> {
        Binding<AppShellTab>(
            get: { self.navigation.selection.barTab },
            set: { newValue in self.navigation.userSelected(newValue) })
    }

    /// True while either the chat or the Settings hub is shown over the shell.
    private var coverBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.navigation.isChatPresented || self.navigation.isSettingsPresented },
            set: { newValue in
                if !newValue {
                    self.navigation.dismissCover()
                }
            })
    }

    var body: some View {
        TabView(selection: self.selectionBinding) {
            Tab(
                AppShellTab.agents.title,
                systemImage: AppShellTab.agents.systemImage,
                value: AppShellTab.agents)
            {
                AppShellAgentsView(navigation: self.navigation)
            }

            Tab(
                AppShellTab.overview.title,
                systemImage: AppShellTab.overview.systemImage,
                value: AppShellTab.overview)
            {
                AppShellOverviewView(navigation: self.navigation, context: self.context)
            }

            Tab(
                AppShellTab.activity.title,
                systemImage: AppShellTab.activity.systemImage,
                value: AppShellTab.activity)
            {
                AppShellActivityView(navigation: self.navigation, context: self.context)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sensoryFeedback(.selection, trigger: self.navigation.selection.barTab)
        .appShellTabSwipe(navigation: self.navigation)
        .fullScreenCover(isPresented: self.coverBinding) {
            self.animatedCover
        }
        .accessibilityIdentifier("AppShell.Root")
    }

    /// Switching between Chat and Settings cross-fades (with a light scale) instead of cutting.
    private var animatedCover: some View {
        self.cover
            .openClawAnimation(value: self.navigation.coverKind)
    }

    @ViewBuilder
    private var cover: some View {
        switch self.navigation.coverKind {
        case .chat:
            AppShellChatView(navigation: self.navigation)
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        case .settings:
            AppShellSettingsView(navigation: self.navigation, context: self.context)
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        }
    }
}
