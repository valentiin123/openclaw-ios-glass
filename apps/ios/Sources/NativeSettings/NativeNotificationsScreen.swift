import Observation
import SwiftUI
import UserNotifications

/// Snapshot of the system notification settings for this app (local data, no Gateway call).
struct NativeNotificationState: Equatable {
    var status: UNAuthorizationStatus
    var alert: UNNotificationSetting
    var sound: UNNotificationSetting
    var badge: UNNotificationSetting
}

@MainActor
@Observable
final class NativeNotificationsModel {
    var current: NativeNotificationState?

    func refresh() async {
        let settings: UNNotificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        let next = NativeNotificationState(
            status: settings.authorizationStatus,
            alert: settings.alertSetting,
            sound: settings.soundSetting,
            badge: settings.badgeSetting)
        self.current = next
    }

    func requestAuthorization() async {
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        do {
            _ = try await center.requestAuthorization(options: options)
        } catch {
            // The refreshed status below is the source of truth.
        }
        await self.refresh()
    }
}

enum NativeNotificationsPresentation {
    static func statusPill(_ status: UNAuthorizationStatus) -> NativeSettingsPill {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return NativeSettingsPill(label: String(localized: "Allowed"), tone: .ok)
        case .denied:
            return NativeSettingsPill(label: String(localized: "Denied"), tone: .warn)
        case .notDetermined:
            return NativeSettingsPill(label: String(localized: "Not asked yet"), tone: .muted)
        @unknown default:
            return NativeSettingsPill(label: String(localized: "Unknown"), tone: .muted)
        }
    }

    static func settingPill(_ setting: UNNotificationSetting) -> NativeSettingsPill {
        switch setting {
        case .enabled:
            return NativeSettingsPill(label: String(localized: "On"), tone: .ok)
        case .disabled:
            return NativeSettingsPill(label: String(localized: "Off"), tone: .muted)
        case .notSupported:
            return NativeSettingsPill(label: String(localized: "Unavailable"), tone: .muted)
        @unknown default:
            return NativeSettingsPill(label: String(localized: "Unknown"), tone: .muted)
        }
    }
}

/// Native replacement for the Dashboard notifications page.
/// Shows the iOS authorization state; per-category routing stays on the Gateway side.
@MainActor
struct NativeNotificationsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: NativeNotificationsModel = NativeNotificationsModel()
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    var onClose: (() -> Void)?

    var body: some View {
        NativeSettingsPage(
            title: NativeSettingsDestination.notifications.title,
            headerSidebarAction: self.headerSidebarAction,
            embedded: self.embedded)
        {
            self.list
        }
        .task { await self.model.refresh() }
        .onChange(of: self.scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await self.model.refresh() }
        }
    }

    private var list: some View {
        List {
            if let state = self.model.current {
                self.statusSection(state)
                self.categoriesSection(state)
            } else {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel(Text("Loading"))
                }
            }
        }
        .refreshable { await self.model.refresh() }
    }

    @ViewBuilder
    private func statusSection(_ state: NativeNotificationState) -> some View {
        let pill: NativeSettingsPill = NativeNotificationsPresentation.statusPill(state.status)
        Section {
            NativeSettingsRow(
                title: String(localized: "Notifications"),
                detail: nil,
                systemImage: "bell.badge",
                tint: .secondary,
                pill: pill)
            if state.status == .notDetermined {
                Button {
                    Task { await self.model.requestAuthorization() }
                } label: {
                    Text("Allow notifications")
                        .font(OpenClawType.subheadSemiBold)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            } else {
                NativeSettingsSystemSettingsButton()
            }
        } footer: {
            Text("Approval requests and agent replies can reach you as notifications. Change the delivery style in iOS Settings.")
                .font(OpenClawType.footnote)
        }
    }

    @ViewBuilder
    private func categoriesSection(_ state: NativeNotificationState) -> some View {
        let alertPill: NativeSettingsPill = NativeNotificationsPresentation.settingPill(state.alert)
        let soundPill: NativeSettingsPill = NativeNotificationsPresentation.settingPill(state.sound)
        let badgePill: NativeSettingsPill = NativeNotificationsPresentation.settingPill(state.badge)
        Section {
            NativeSettingsRow(
                title: String(localized: "Alerts"),
                detail: nil,
                systemImage: "text.bubble",
                tint: .secondary,
                pill: alertPill)
            NativeSettingsRow(
                title: String(localized: "Sounds"),
                detail: nil,
                systemImage: "speaker.wave.2",
                tint: .secondary,
                pill: soundPill)
            NativeSettingsRow(
                title: String(localized: "Badges"),
                detail: nil,
                systemImage: "app.badge",
                tint: .secondary,
                pill: badgePill)
        }
    }
}
