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
    case gatewayStatus

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
        case .notifications, .talkVoice, .gatewayStatus: nil
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
        case .gatewayStatus: String(localized: "Gateway status")
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
        case .gatewayStatus: "heart.text.square"
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

// MARK: - Page shell

struct NativeSettingsPill: Equatable {
    var label: String
    var tone: OpenClawStatusTone
}

/// Owns the page toast and injects it, so copy gestures anywhere below confirm through one glass capsule.
private struct NativeSettingsToastScope: ViewModifier {
    @State private var toast: GlassToastModel = GlassToastModel()

    func body(content: Content) -> some View {
        content
            .environment(self.toast)
            .glassToastHost(self.toast)
    }
}

/// Page shell: NavigationStack (unless embedded in a parent stack), inline title, sidebar toolbar item,
/// and an optional "Done" button when the page is presented as a sheet (`onClose`).
struct NativeSettingsPage<Content: View>: View {
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    var onClose: (() -> Void)?
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
            .font(OpenClawType.body)
            .scrollContentBackground(.hidden)
            .background { OpenClawProBackground() }
            .modifier(NativeSettingsToastScope())
            .navigationTitle(self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let action = self.headerSidebarAction {
                    OpenClawSidebarToolbarItem(action: action, placement: .topBarLeading)
                }
                if let onClose = self.onClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onClose) {
                            Text("Done")
                                .font(OpenClawType.subheadSemiBold)
                        }
                        .accessibilityIdentifier("NativeSettings.Done")
                    }
                }
            }
    }
}

// MARK: - Section chrome

/// Section header in the app typography. Stays a quiet label: no glass, no caps.
struct NativeSettingsHeader: View {
    let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(self.key)
            .font(OpenClawType.footnoteSemiBold)
    }
}

/// Section header for text computed at runtime.
struct NativeSettingsVerbatimHeader: View {
    let text: String

    var body: some View {
        Text(verbatim: self.text)
            .font(OpenClawType.footnoteSemiBold)
    }
}

/// Section footer in the app typography.
struct NativeSettingsFooter: View {
    let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(self.key)
            .font(OpenClawType.footnote)
    }
}

// MARK: - Row

/// One settings row: tinted icon tile (or emoji), title, optional detail, optional status pill.
/// Opaque list surface, no glass. At accessibility text sizes the pill moves under the text.
struct NativeSettingsRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 30
    let title: String
    var detail: String?
    var systemImage: String
    var emoji: String?
    var tint: Color = .secondary
    var pill: NativeSettingsPill?
    var detailLineLimit: Int? = 2

    var body: some View {
        let stacked: Bool = self.typeSize.isAccessibilitySize
        HStack(alignment: .center, spacing: OpenClawSpace.md) {
            self.tile
            VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
                Text(verbatim: self.title)
                    .font(OpenClawType.body)
                if let detail = self.detail {
                    Text(verbatim: detail)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(self.detailLineLimit)
                }
                if stacked, let pill = self.pill {
                    self.pillView(pill)
                }
            }
            Spacer(minLength: OpenClawSpace.sm)
            if !stacked, let pill = self.pill {
                self.pillView(pill)
            }
        }
        .frame(minHeight: OpenClawHitTarget.minimum)
        .openClawAnimation(value: self.pill)
        .accessibilityElement(children: .combine)
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            if let emoji = self.emoji {
                Text(verbatim: emoji)
                    .font(OpenClawType.callout)
            } else {
                Image(systemName: self.systemImage)
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(self.tint)
            }
        }
        .frame(width: self.tileSide, height: self.tileSide)
        .background(self.tint.opacity(0.14), in: shape)
        .accessibilityHidden(true)
    }

    private func pillView(_ pill: NativeSettingsPill) -> some View {
        OpenClawStatusPill(label: .verbatim(pill.label), tone: pill.tone)
    }
}

// MARK: - Inline state

/// Inline loading/error/content state for a section inside a form.
struct NativeSettingsInlineState<Value, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: NativeLoadState<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    /// `NativeLoadState` is not Equatable: the phase is the value that drives the cross-fade.
    private var phase: Int {
        switch self.state {
        case .idle, .loading: 0
        case .failed: 1
        case .loaded: 2
        }
    }

    var body: some View {
        Group {
            switch self.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum)
                    .accessibilityLabel(Text("Loading"))
                    .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
            case let .failed(message):
                VStack(alignment: .leading, spacing: OpenClawSpace.sm) {
                    Text(verbatim: message)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                    OpenClawGlassButton(title: "Retry", systemImage: "arrow.clockwise") {
                        Task { await self.retry() }
                    }
                }
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
            case let .loaded(value):
                self.content(value)
                    .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
            }
        }
        .openClawAnimation(value: self.phase)
    }
}

// MARK: - System Settings + clipboard

/// Opens the app's page in the iOS Settings app.
struct NativeSettingsSystemSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            self.openURL(url)
        } label: {
            HStack(spacing: OpenClawSpace.md) {
                Label {
                    Text("Open iOS Settings")
                        .font(OpenClawType.subheadSemiBold)
                } icon: {
                    Image(systemName: "gearshape")
                }
                Spacer(minLength: OpenClawSpace.sm)
                Image(systemName: "arrow.up.forward")
                    .font(OpenClawType.captionSemiBold)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}

extension View {
    /// Trailing swipe action offering to copy `value`. Shows nothing when the value is empty.
    /// Delegates to the shared glass copy gesture (toast, VoiceOver announcement, haptic).
    func nativeSettingsCopySwipe(_ value: String?) -> some View {
        self.glassCopySwipe(value)
    }

    /// Long-press menu offering to copy `value`. Shows nothing when the value is empty.
    /// Delegates to the shared glass copy gesture (toast, VoiceOver announcement, haptic).
    func nativeSettingsCopyMenu(_ value: String?) -> some View {
        self.glassCopyMenu(value)
    }
}
