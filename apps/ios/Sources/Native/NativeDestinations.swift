import OpenClawKit
import SwiftUI

/// Routes a Dashboard path to a native screen. Unknown paths keep the WebView page.
struct NativeDestinationRouter: View {
    let path: String
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var onRouteChange: ((SettingsRoute?) -> Void)?
    var onApprovalNotificationsRoute: ((String?) -> Void)?

    static func hasNativeScreen(for path: String) -> Bool {
        [
            DashboardRouteMap.activityPagePath,
            DashboardRouteMap.workboardPagePath,
            DashboardRouteMap.skillWorkshopPagePath,
            DashboardRouteMap.devicesSettingsPath,
            DashboardRouteMap.dreamingPagePath,
            DashboardRouteMap.usagePagePath,
            DashboardRouteMap.cronJobsPagePath,
        ].contains(path)
    }

    var body: some View {
        switch self.path {
        case DashboardRouteMap.activityPagePath:
            NativeListScreen(
                title: self.title,
                emptyTitle: "No recent activity",
                emptyIcon: "waveform.path.ecg",
                headerSidebarAction: self.headerSidebarAction,
                loader: NativeLoaders.activity)
        case DashboardRouteMap.skillWorkshopPagePath:
            NativeListScreen(
                title: self.title,
                emptyTitle: "No Workshop skills yet",
                emptyIcon: "hammer",
                headerSidebarAction: self.headerSidebarAction,
                loader: NativeLoaders.skillWorkshop)
        case DashboardRouteMap.devicesSettingsPath:
            NativeListScreen(
                title: self.title,
                emptyTitle: "No connected devices",
                emptyIcon: "dot.radiowaves.left.and.right",
                headerSidebarAction: self.headerSidebarAction,
                loader: NativeLoaders.presence)
        case DashboardRouteMap.dreamingPagePath:
            NativeListScreen(
                title: self.title,
                emptyTitle: "No dream diary entries",
                emptyIcon: "moon.stars",
                headerSidebarAction: self.headerSidebarAction,
                loader: NativeLoaders.dreams)
        case DashboardRouteMap.cronJobsPagePath:
            NativeListScreen(
                title: self.title,
                emptyTitle: "No automations",
                emptyIcon: "timer",
                headerSidebarAction: self.headerSidebarAction,
                loader: NativeLoaders.cron)
        case DashboardRouteMap.usagePagePath:
            NativeUsageScreen(title: self.title, headerSidebarAction: self.headerSidebarAction)
        case DashboardRouteMap.workboardPagePath:
            NativeUnavailableScreen(
                title: self.title,
                message: String(localized: "No verified Gateway list method exists for the Workboard yet. Open it in the Dashboard."),
                headerSidebarAction: self.headerSidebarAction)
        default:
            DashboardPageScreen(
                path: self.path,
                title: self.title,
                headerSidebarAction: self.headerSidebarAction,
                onRouteChange: self.onRouteChange,
                onApprovalNotificationsRoute: self.onApprovalNotificationsRoute)
        }
    }
}

/// Read-only fallback when no verified Gateway method backs a destination.
struct NativeUnavailableScreen: View {
    let title: String
    let message: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(self.title, systemImage: "rectangle.on.rectangle.slash")
            } description: {
                Text(verbatim: self.message)
            }
            .navigationTitle(self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let headerSidebarAction {
                    OpenClawSidebarToolbarItem(action: headerSidebarAction, placement: .topBarLeading)
                }
            }
        }
    }
}

/// Gateway methods used here exist in packages/gateway-protocol or the iOS app.
/// Response shapes without a verified schema are read tolerantly.
@MainActor
enum NativeLoaders {
    static let activity: NativeListModel.Loader = { app in
        let obj = try await NativeGateway.request(
            appModel: app, method: "audit.activity.list", paramsJSON: #"{"limit":100}"#)
        let events = (obj as? [String: Any])?.array("events") ?? []
        let rows = events.enumerated().map { index, e -> NativeRow in
            let status = e.string("status") ?? "unknown"
            let kind = e.string("kind") ?? e.string("action") ?? "event"
            return NativeRow(
                id: e.string("eventId") ?? "event-\(index)",
                title: e.string("action") ?? kind,
                subtitle: e.string("agentId") ?? e.string("channel"),
                trailing: NativeFormat.relative(ms: e.int("occurredAt")),
                systemImage: status == "failed" ? "exclamationmark.triangle" : "waveform.path.ecg",
                tint: status == "failed" ? .red : .secondary)
        }
        return (rows, nil)
    }

    static let skillWorkshop: NativeListModel.Loader = { app in
        let obj = try await NativeGateway.request(appModel: app, method: "skills.workshop.list")
        let skills = (obj as? [String: Any])?.array("skills") ?? []
        let rows = skills.map { s in
            NativeRow(
                id: s.string("name") ?? UUID().uuidString,
                title: s.string("name") ?? "-",
                subtitle: s.string("description"),
                trailing: NativeFormat.relative(ms: s.int("updatedAtMs")),
                systemImage: "hammer")
        }
        return (rows, nil)
    }

    static let presence: NativeListModel.Loader = { app in
        let obj = try await NativeGateway.request(
            appModel: app, method: "presence.query", paramsJSON: #"{"action":"list","include":["devices"]}"#)
        let root = obj as? [String: Any]
        var rows: [NativeRow] = []
        for person in root?.array("people") ?? [] {
            for d in person.array("devices") {
                rows.append(NativeRow(
                    id: d.string("id") ?? UUID().uuidString,
                    title: d.string("name") ?? "-",
                    subtitle: person.string("name"),
                    trailing: d.string("kind"),
                    systemImage: "iphone.gen3",
                    tint: .green))
            }
        }
        let note = (root?.bool("truncated") == true)
            ? String(localized: "List truncated by the Gateway.") : nil
        return (rows, note)
    }

    /// Response shape of doctor.memory.dreamDiary is not verified: read common keys only.
    static let dreams: NativeListModel.Loader = { app in
        let obj = try await NativeGateway.request(appModel: app, method: "doctor.memory.dreamDiary")
        let root = obj as? [String: Any]
        let entries = root?.array("entries") ?? root?.array("items") ?? []
        let rows = entries.enumerated().map { i, e in
            NativeRow(
                id: e.string("id") ?? "dream-\(i)",
                title: e.string("title") ?? e.string("summary") ?? String(localized: "Dream"),
                subtitle: e.string("content"),
                trailing: nil,
                systemImage: "moon.stars")
        }
        return (rows, String(localized: "Response shape not verified against a schema."))
    }

    static let cron: NativeListModel.Loader = { app in
        let obj = try await NativeGateway.request(
            appModel: app, method: "cron.list",
            paramsJSON: #"{"includeDisabled":true,"limit":200,"offset":0,"sortBy":"name","sortDir":"asc"}"#)
        let jobs = (obj as? [String: Any])?.array("jobs") ?? []
        let rows = jobs.map { j in
            let enabled = j.bool("enabled") ?? true
            return NativeRow(
                id: j.string("id") ?? UUID().uuidString,
                title: j.string("name") ?? j.string("id") ?? "-",
                subtitle: j.string("description"),
                trailing: enabled ? nil : String(localized: "Disabled"),
                systemImage: enabled ? "timer" : "pause.circle",
                tint: enabled ? .secondary : .orange)
        }
        return (rows, nil)
    }
}
