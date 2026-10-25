import OpenClawKit
import SwiftUI

/// Dashboard pages are fully native: they always show the SwiftUI Settings screens.
/// No web content is embedded here. `EmbeddedDashboardContent` and
/// `SettingsHubScreen.usesDashboard` stay available for tests and legacy callers only.
struct DashboardPageScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationPath: [SettingsRoute] = []
    let path: String
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var onClose: (() -> Void)?
    var onRouteChange: ((SettingsRoute?) -> Void)?
    var onApprovalNotificationsRoute: ((String?) -> Void)?

    var body: some View {
        NavigationStack(path: self.$navigationPath) {
            self.root
                .toolbar {
                    if let onClose {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: onClose) {
                                Text("Done")
                                    .font(OpenClawType.subheadSemiBold)
                            }
                            .accessibilityIdentifier("DashboardPage.Close")
                        }
                    }
                }
                .navigationDestination(for: SettingsRoute.self) { route in
                    SettingsProTab(
                        directRoute: route,
                        registersNavigationDestinations: false,
                        onApprovalNotificationsRoute: self.onApprovalNotificationsRoute)
                }
        }
        .onChange(of: self.navigationPath) { _, path in
            self.onRouteChange?(path.last)
        }
        .animation(OpenClawMotion.animation(reduceMotion: self.reduceMotion), value: self.navigationPath.count)
        .openClawHaptic(.selection, trigger: self.navigationPath.count)
    }

    private var root: some View {
        SettingsProTab(
            registersNavigationDestinations: false,
            headerSidebarAction: self.headerSidebarAction,
            onApprovalNotificationsRoute: self.onApprovalNotificationsRoute)
    }
}
