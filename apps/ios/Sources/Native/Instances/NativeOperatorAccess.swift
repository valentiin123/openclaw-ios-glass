import Foundation
import OpenClawKit

/// Snapshot of what the current operator connection may do.
/// Pattern taken from `AgentsHubScreen.refreshCapabilities`: advertised scopes + advertised methods.
/// Without a live route (or without advertised scopes) every action stays disabled.
struct NativeOperatorAccess: Equatable {
    var scopes: Set<String>
    var supportedMethods: Set<String>

    static let none = NativeOperatorAccess(scopes: [], supportedMethods: [])

    /// `operator.admin` satisfies every scope check.
    func hasScope(_ scope: String) -> Bool {
        self.scopes.contains(scope) || self.scopes.contains("operator.admin")
    }

    /// Write also implies read on the Gateway; admin implies both.
    var canRead: Bool {
        self.hasScope("operator.read") || self.hasScope("operator.write")
    }

    func allows(method: String, scope: String) -> Bool {
        self.hasScope(scope) && self.supportedMethods.contains(method)
    }

    @MainActor
    static func load(appModel: NodeAppModel, methods: [String]) async -> NativeOperatorAccess {
        let session = appModel.operatorSession
        guard let route = await session.currentRoute() else { return .none }
        let advertised: Set<String>? = await session.currentOperatorScopes(ifCurrentRoute: route)
        let scopes: Set<String> = advertised ?? []
        var supported = Set<String>()
        for method in methods {
            let result: Bool? = await session.supportsServerMethod(method, ifCurrentRoute: route)
            if result == true {
                supported.insert(method)
            }
        }
        return NativeOperatorAccess(scopes: scopes, supportedMethods: supported)
    }
}

enum NativeJSON {
    /// Serializes request params; falls back to an empty object on failure.
    static func string(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
