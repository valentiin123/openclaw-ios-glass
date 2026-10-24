import SwiftUI

/// Routes a `NativeSettingsDestination` to its native SwiftUI screen.
/// `onClose` adds a "Done" button when the screen is presented as a sheet.
@MainActor
struct NativeSettingsRouter: View {
    let destination: NativeSettingsDestination
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    var onClose: (() -> Void)?

    /// True when a Dashboard path has a native settings screen.
    static func hasNativeScreen(forPath path: String) -> Bool {
        NativeSettingsDestination.destination(forPath: path) != nil
    }

    /// Returns the native screen for a Dashboard path, or `nil` so callers keep the WebView page.
    static func screen(
        forPath path: String,
        headerSidebarAction: OpenClawSidebarHeaderAction? = nil,
        embedded: Bool = false) -> NativeSettingsRouter?
    {
        guard let destination = NativeSettingsDestination.destination(forPath: path) else { return nil }
        return NativeSettingsRouter(
            destination: destination,
            headerSidebarAction: headerSidebarAction,
            embedded: embedded)
    }

    var body: some View {
        switch self.destination {
        case .appearance:
            NativeAppearanceScreen(
                headerSidebarAction: self.headerSidebarAction,
                embedded: self.embedded,
                onClose: self.onClose)
        case .notifications:
            NativeNotificationsScreen(
                headerSidebarAction: self.headerSidebarAction,
                embedded: self.embedded,
                onClose: self.onClose)
        case .permissions:
            NativePermissionsScreen(
                headerSidebarAction: self.headerSidebarAction,
                embedded: self.embedded,
                onClose: self.onClose)
        case .talkVoice:
            NativeTalkVoiceScreen(
                headerSidebarAction: self.headerSidebarAction,
                embedded: self.embedded,
                onClose: self.onClose)
        case .channels:
            NativeChannelsScreen(
                headerSidebarAction: self.headerSidebarAction,
                embedded: self.embedded,
                onClose: self.onClose)
        case .skills:
            NativeSkillsScreen(
                headerSidebarAction: self.headerSidebarAction,
                embedded: self.embedded,
                onClose: self.onClose)
        }
    }
}
