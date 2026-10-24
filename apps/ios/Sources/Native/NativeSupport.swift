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

/// Thin wrapper over the operator session. Only methods found in the repo are called by callers.
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
}

/// Tolerant JSON accessors: shapes without a verified schema are never force-decoded.
extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
    func array(_ key: String) -> [[String: Any]] { (self[key] as? [[String: Any]]) ?? [] }
    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
}

enum NativeFormat {
    static func relative(ms: Int?) -> String? {
        guard let ms else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        return date.formatted(.relative(presentation: .named))
    }
}

/// Generic list shell: loading / empty / error + pull-to-refresh.
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
                    .openClawGlassButtonIfAvailable()
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

private extension View {
    @ViewBuilder
    func openClawGlassButtonIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
