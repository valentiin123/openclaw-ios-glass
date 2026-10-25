import AVFoundation
import CoreLocation
import OpenClawKit
import Photos
import SwiftUI
import UIKit
import UserNotifications

/// Presentation helpers for permission rows.
enum NativePermissionPresentation {
    static func title(_ permission: DeviceSettingsPermission) -> String {
        switch permission {
        case .notifications: return String(localized: "Notifications")
        case .accessibility: return String(localized: "Accessibility")
        case .screenRecording: return String(localized: "Screen Recording")
        case .microphone: return String(localized: "Microphone")
        case .camera: return String(localized: "Camera")
        case .speechRecognition: return String(localized: "Speech Recognition")
        case .location: return String(localized: "Location")
        case .eventPosting: return String(localized: "Event Posting")
        case .contacts: return String(localized: "Contacts")
        case .calendars: return String(localized: "Calendars")
        case .reminders: return String(localized: "Reminders")
        case .photos: return String(localized: "Photos")
        }
    }

    static func icon(_ permission: DeviceSettingsPermission) -> String {
        switch permission {
        case .notifications: return "bell"
        case .accessibility: return "accessibility"
        case .screenRecording: return "record.circle"
        case .microphone: return "mic"
        case .camera: return "camera"
        case .speechRecognition: return "text.bubble"
        case .location: return "location"
        case .eventPosting: return "keyboard"
        case .contacts: return "person.crop.circle"
        case .calendars: return "calendar"
        case .reminders: return "checklist"
        case .photos: return "photo"
        }
    }

    static func pill(_ status: DeviceSettingsPermissionStatus) -> NativeSettingsPill {
        switch status {
        case .granted:
            return NativeSettingsPill(label: String(localized: "Allowed"), tone: .ok)
        case .limited:
            return NativeSettingsPill(label: String(localized: "Limited"), tone: .warn)
        case .denied:
            return NativeSettingsPill(label: String(localized: "Denied"), tone: .warn)
        case .notDetermined:
            return NativeSettingsPill(label: String(localized: "Not asked"), tone: .muted)
        case .unavailable:
            return NativeSettingsPill(label: String(localized: "Unavailable"), tone: .muted)
        }
    }

    /// Permissions the app can prompt for in place (others go through iOS Settings).
    static func canPromptInApp(_ permission: DeviceSettingsPermission) -> Bool {
        switch permission {
        case .camera, .microphone, .speechRecognition, .contacts, .calendars, .reminders, .photos:
            return true
        case .notifications, .location, .accessibility, .screenRecording, .eventPosting:
            return false
        }
    }
}

struct NativePermissionItem: Identifiable, Equatable {
    let permission: DeviceSettingsPermission
    let status: DeviceSettingsPermissionStatus

    var id: String {
        self.permission.rawValue
    }
}

@MainActor
@Observable
final class NativePermissionsModel {
    var items: [NativePermissionItem] = []
    var requestingID: String?
    /// False until the first `reload()` finished, so the list shows a spinner instead of a blank screen.
    var hasLoaded: Bool = false
    private let requester = IOSDeviceSettingsPermissions()

    func reload() async {
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        let settings: UNNotificationSettings = await center.notificationSettings()
        let locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus
        let photosStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let entries: [DeviceSettingsSnapshot.Permissions.Entry] = IOSDeviceSettingsPermissions.entries(
            notificationStatus: settings.authorizationStatus,
            locationAuthorization: locationStatus,
            locationServicesEnabled: true,
            photosAuthorization: photosStatus)
        var next: [NativePermissionItem] = []
        for entry in entries {
            let item = NativePermissionItem(permission: entry.id, status: entry.status)
            next.append(item)
        }
        self.items = next
        self.hasLoaded = true
    }

    func request(_ permission: DeviceSettingsPermission) async {
        guard NativePermissionPresentation.canPromptInApp(permission) else { return }
        self.requestingID = permission.rawValue
        let isCurrent: @MainActor @Sendable () -> Bool = { true }
        do {
            try await self.requester.request(permission, isCurrent: isCurrent)
        } catch {
            // Cancelled or superseded; the reload below shows the real state.
        }
        self.requestingID = nil
        await self.reload()
    }
}

/// Native replacement for the Dashboard `/settings/device/permissions` page.
/// Reads real iOS authorization states; no Gateway call is involved.
/// Rows that can be asked in place expose a trailing swipe action and a context-menu entry;
/// the inline "Allow" button stays for discoverability and VoiceOver.
@MainActor
struct NativePermissionsScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var model = NativePermissionsModel()
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    var onClose: (() -> Void)?

    var body: some View {
        NativeSettingsPage(
            title: NativeSettingsDestination.permissions.title,
            headerSidebarAction: self.headerSidebarAction,
            embedded: self.embedded,
            onClose: self.onClose)
        {
            self.list
        }
        .task { await self.model.reload() }
        .onChange(of: self.scenePhase) { _, phase in
            if phase == .active {
                Task { await self.model.reload() }
            }
        }
    }

    private var list: some View {
        List {
            if !self.model.hasLoaded {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum)
                        .accessibilityLabel(Text("Loading"))
                }
            } else {
                Section {
                    ForEach(Array(self.model.items.enumerated()), id: \.element.id) { (index: Int, item: NativePermissionItem) in
                        self.row(item)
                            .openClawEntrance(index: index)
                    }
                } footer: {
                    NativeSettingsFooter("Denied permissions can only be changed in iOS Settings.")
                }
                Section {
                    NativeSettingsSystemSettingsButton()
                        .openClawEntrance(index: self.model.items.count)
                }
            }
        }
        .refreshable { await self.model.reload() }
        .openClawAnimation(value: self.model.items)
        .sensoryFeedback(trigger: self.model.requestingID) { (old: String?, new: String?) -> SensoryFeedback? in
            (old != nil && new == nil) ? .success : nil
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        self.openURL(url)
    }

    private func canAsk(_ item: NativePermissionItem) -> Bool {
        item.status == .notDetermined && NativePermissionPresentation.canPromptInApp(item.permission)
    }

    private func row(_ item: NativePermissionItem) -> some View {
        let title: String = NativePermissionPresentation.title(item.permission)
        let icon: String = NativePermissionPresentation.icon(item.permission)
        let pill: NativeSettingsPill = NativePermissionPresentation.pill(item.status)
        let canAsk: Bool = self.canAsk(item)
        let busy: Bool = self.model.requestingID != nil
        return HStack(spacing: OpenClawSpace.sm) {
            NativeSettingsRow(title: title, systemImage: icon, tint: pill.tone.color, pill: pill)
            if canAsk {
                Button {
                    Task { await self.model.request(item.permission) }
                } label: {
                    Group {
                        if self.model.requestingID == item.id {
                            ProgressView()
                        } else {
                            Text("Allow")
                                .font(OpenClawType.subheadSemiBold)
                        }
                    }
                    .frame(minWidth: OpenClawHitTarget.minimum, minHeight: OpenClawHitTarget.minimum)
                }
                .buttonStyle(.openClawGlassAction(.regular, tint: OpenClawBrand.accent))
                .disabled(busy)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canAsk {
                Button {
                    Task { await self.model.request(item.permission) }
                } label: {
                    Label("Allow", systemImage: "checkmark.circle")
                }
                .tint(OpenClawBrand.accent)
                .disabled(busy)
            }
        }
        .glassActionsMenu(copying: nil) {
            if canAsk {
                Button {
                    Task { await self.model.request(item.permission) }
                } label: {
                    Label("Allow", systemImage: "checkmark.circle")
                }
                .disabled(busy)
            }
            if item.status != .granted {
                Button {
                    self.openSystemSettings()
                } label: {
                    Label("Open iOS Settings", systemImage: "gearshape")
                }
            }
        }
    }
}
