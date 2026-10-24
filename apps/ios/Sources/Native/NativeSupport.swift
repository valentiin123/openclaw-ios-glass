import Foundation
import Observation
import SwiftUI

/// Loading state shared by every native destination.
enum NativeLoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

/// Thin wrapper over the operator session. Only methods found in the repo or in
/// packages/gateway-protocol are called by callers.
@MainActor
enum NativeGateway {
    static func request(
        appModel: NodeAppModel,
        method: String,
        paramsJSON: String = "{}",
        timeoutSeconds: Int = 12) async throws -> Any
    {
        let data = try await appModel.operatorSession.request(
            method: method,
            paramsJSON: paramsJSON,
            timeoutSeconds: timeoutSeconds)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Same as `request` but builds the params JSON from a dictionary.
    static func send(
        appModel: NodeAppModel,
        method: String,
        params: [String: Any],
        timeoutSeconds: Int = 15) async throws -> Any
    {
        try await self.request(
            appModel: appModel,
            method: method,
            paramsJSON: Self.paramsJSON(params),
            timeoutSeconds: timeoutSeconds)
    }

    static func paramsJSON(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object) else { return "{}" }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static let offlineMessage: String = String(localized: "The operator connection is offline.")
}

/// Tolerant JSON accessors: shapes without a verified schema are never force-decoded.
extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func double(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
    func array(_ key: String) -> [[String: Any]] { (self[key] as? [[String: Any]]) ?? [] }
    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func strings(_ key: String) -> [String] { (self[key] as? [String]) ?? [] }
}

enum NativeFormat {
    static func date(ms: Int?) -> Date? {
        guard let ms else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    static func relative(ms: Int?) -> String? {
        guard let date = Self.date(ms: ms) else { return nil }
        return date.formatted(.relative(presentation: .named))
    }

    static func dateTime(ms: Int?) -> String? {
        guard let date = Self.date(ms: ms) else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func duration(ms: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        let seconds = TimeInterval(ms) / 1000
        if seconds < 1 { return "\(ms) ms" }
        return formatter.string(from: seconds) ?? "-"
    }

    static func humanized(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " · ")
    }

    static func joined(_ parts: [String?], separator: String = " · ") -> String? {
        let values = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: separator)
    }
}

// MARK: - Shared views

/// Generic shell: loading / empty / error. Pull-to-refresh lives on the content.
struct NativeStateView<Value, Content: View>: View {
    let state: NativeLoadState<Value>
    let isEmpty: (Value) -> Bool
    let emptyTitle: LocalizedStringKey
    let emptyIcon: String
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch self.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading"))
        case let .failed(message):
            ContentUnavailableView {
                Label("Could not load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: message)
            } actions: {
                Button("Retry") { Task { await self.retry() } }
                    .nativeGlassButton()
            }
        case let .loaded(value):
            if self.isEmpty(value) {
                ContentUnavailableView(self.emptyTitle, systemImage: self.emptyIcon)
            } else {
                self.content(value)
            }
        }
    }
}

/// Quiet capsule badge. No glass: color carries the meaning.
struct NativeBadge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(verbatim: self.text)
            .font(OpenClawType.caption2SemiBold)
            .foregroundStyle(self.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(self.color.opacity(0.14))
            }
    }
}

/// Opaque, discreet content surface (never glass).
struct NativeSurface<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        self.content
            .padding(self.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: OpenClawProMetric.cardRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
    }
}

/// Horizontal chip bar. The selected chip is a glass capsule (control), others are flat.
struct NativeChipBar: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
    }

    let items: [Item]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(self.items) { item in
                    self.chip(item)
                }
            }
            .padding(.horizontal, OpenClawProMetric.pagePadding)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ item: Item) -> some View {
        let isSelected = item.id == self.selection
        return Button {
            self.selection = item.id
        } label: {
            Text(verbatim: item.title)
                .font(OpenClawType.subheadSemiBold)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            NativeChipBackground(isSelected: isSelected)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NativeChipBackground: View {
    let isSelected: Bool

    var body: some View {
        if self.isSelected {
            Color.clear.openClawGlassCapsule(tint: OpenClawBrand.accent.opacity(0.16), interactive: true)
        } else {
            Capsule().fill(Color(uiColor: .tertiarySystemFill))
        }
    }
}

/// Dashboard page shown in a sheet for pages that have no native screen yet.
struct NativeWebPage: Identifiable, Equatable {
    let path: String
    let title: String

    var id: String {
        self.path
    }
}

extension View {
    /// Inline title + the shared sidebar reveal button.
    func nativeChrome(title: String, sidebar: OpenClawSidebarHeaderAction?) -> some View {
        self.navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let sidebar {
                    OpenClawSidebarToolbarItem(action: sidebar, placement: .topBarLeading)
                }
            }
    }

    /// Alert bound to an optional message; nil dismisses it.
    func nativeErrorAlert(_ message: Binding<String?>) -> some View {
        let isPresented = Binding<Bool>(
            get: { message.wrappedValue != nil },
            set: { shown in
                if !shown { message.wrappedValue = nil }
            })
        return self.alert("Action failed", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: message.wrappedValue ?? "")
        }
    }

    /// Presents a Dashboard (web) page in a sheet with a Done button.
    func nativeWebSheet(_ page: Binding<NativeWebPage?>) -> some View {
        self.sheet(item: page) { item in
            DashboardPageScreen(
                path: item.path,
                title: item.title,
                onClose: { page.wrappedValue = nil })
        }
    }

    @ViewBuilder
    func nativeGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
