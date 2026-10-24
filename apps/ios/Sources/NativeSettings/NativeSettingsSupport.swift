import Foundation
import Observation
import OpenClawKit
import SwiftUI
import UIKit

// MARK: - Destinations

/// Native replacements for the Settings pages that used to be rendered by the Dashboard WebView.
enum NativeSettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case appearance
    case notifications
    case permissions
    case talkVoice
    case channels
    case skills

    var id: String {
        self.rawValue
    }

    /// Dashboard path replaced by this screen. `nil` when `DashboardRouteMap` has no verified constant.
    var dashboardPath: String? {
        switch self {
        case .appearance: DashboardRouteMap.appearanceSettingsPath
        case .permissions: DashboardRouteMap.devicePermissionsSettingsPath
        case .channels: DashboardRouteMap.channelsSettingsPath
        case .skills: DashboardRouteMap.skillsPagePath
        case .notifications, .talkVoice: nil
        }
    }

    var title: String {
        switch self {
        case .appearance: String(localized: "Appearance")
        case .notifications: String(localized: "Notifications")
        case .permissions: String(localized: "Permissions")
        case .talkVoice: String(localized: "Talk & Voice")
        case .channels: String(localized: "Channels")
        case .skills: String(localized: "Skills")
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "circle.lefthalf.filled"
        case .notifications: "bell.badge"
        case .permissions: "hand.raised"
        case .talkVoice: "waveform"
        case .channels: "bubble.left.and.bubble.right"
        case .skills: "sparkles"
        }
    }

    static func destination(forPath path: String) -> NativeSettingsDestination? {
        for candidate in NativeSettingsDestination.allCases where candidate.dashboardPath == path {
            return candidate
        }
        return nil
    }
}

// MARK: - JSON + Gateway helpers

enum NativeSettingsJSON {
    static func encode(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object) else { return "{}" }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

@MainActor
enum NativeSettingsGateway {
    /// Calls a Gateway method and returns the top-level JSON object (empty when the payload is not an object).
    static func call(
        appModel: NodeAppModel,
        method: String,
        params: [String: Any] = [:],
        timeoutSeconds: Int = 12) async throws -> [String: Any]
    {
        let json: String = NativeSettingsJSON.encode(params)
        let object: Any = try await NativeGateway.request(
            appModel: appModel,
            method: method,
            paramsJSON: json,
            timeoutSeconds: timeoutSeconds)
        let dictionary: [String: Any] = (object as? [String: Any]) ?? [:]
        return dictionary
    }
}

// MARK: - Loader

@MainActor
@Observable
final class NativeSettingsLoader<Value> {
    typealias Load = @MainActor (NodeAppModel) async throws -> Value

    var state: NativeLoadState<Value> = .idle
    private let load: Load

    init(load: @escaping Load) {
        self.load = load
    }

    func refresh(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(String(localized: "The operator connection is offline."))
            return
        }
        if showSpinner { self.state = .loading }
        do {
            let value: Value = try await self.load(appModel)
            self.state = .loaded(value)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Shared views

struct NativeSettingsPill: Equatable {
    var label: String
    var tone: OpenClawStatusTone
}

/// Page shell: NavigationStack (unless embedded in a parent stack), inline title, sidebar toolbar item.
struct NativeSettingsPage<Content: View>: View {
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        if self.embedded {
            self.page
        } else {
            NavigationStack {
                self.page
            }
        }
    }

    private var page: some View {
        self.content
            .navigationTitle(self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let action = self.headerSidebarAction {
                    OpenClawSidebarToolbarItem(action: action, placement: .topBarLeading)
                }
            }
    }
}

/// One settings row: icon, title, optional detail, optional status pill. Opaque list surface, no glass.
struct NativeSettingsRow: View {
    let title: String
    var detail: String?
    var systemImage: String
    var tint: Color = .secondary
    var pill: NativeSettingsPill?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: self.systemImage)
                .font(OpenClawType.body)
                .foregroundStyle(self.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.title)
                    .font(OpenClawType.body)
                if let detail = self.detail {
                    Text(verbatim: detail)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let pill = self.pill {
                OpenClawStatusPill(label: .verbatim(pill.label), tone: pill.tone)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// Inline loading/error/content state for a section inside a form.
struct NativeSettingsInlineState<Value, Content: View>: View {
    let state: NativeLoadState<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch self.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel(Text("Loading"))
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: message)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await self.retry() }
                } label: {
                    Text("Retry")
                        .font(OpenClawType.subheadSemiBold)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
            }
        case let .loaded(value):
            self.content(value)
        }
    }
}

/// Opens the app's page in the iOS Settings app.
struct NativeSettingsSystemSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            self.openURL(url)
        } label: {
            Label {
                Text("Open iOS Settings")
                    .font(OpenClawType.subheadSemiBold)
            } icon: {
                Image(systemName: "gearshape")
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }
}
