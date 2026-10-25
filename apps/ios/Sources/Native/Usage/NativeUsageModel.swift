import Foundation
import Observation

// Data layer of the native Usage page.
// `usage.cost` gives the per-day series (cost + tokens). `sessions.usage` is not advertised by every
// Gateway, so the per-model / per-agent breakdown is optional: when it fails, the page keeps working
// and the breakdown tabs explain that the Gateway does not report it.

struct NativeUsageDay: Identifiable, Equatable {
    let id: String
    let date: Date
    let cost: Double
    var tokens: Double = 0
}

/// One row of a per-model or per-agent breakdown.
struct NativeUsageBreakdownItem: Identifiable, Equatable {
    let id: String
    let title: String
    var subtitle: String?
    let cost: Double
    let tokens: Double
    var requests: Int?
}

struct NativeUsageSnapshot {
    let days: [NativeUsageDay]
    let totalCost: Double?
    var totalTokens: Double?
    /// `nil` means the Gateway did not provide the breakdown (unlike an empty array).
    var models: [NativeUsageBreakdownItem]?
    var agents: [NativeUsageBreakdownItem]?

    var peakDay: NativeUsageDay? {
        self.days.max(by: { $0.cost < $1.cost })
    }

    var averageCost: Double? {
        let active: [NativeUsageDay] = self.days.filter { $0.cost > 0 }
        guard !active.isEmpty else { return nil }
        let sum: Double = active.reduce(0) { $0 + $1.cost }
        return sum / Double(active.count)
    }
}

enum NativeUsageRange: Hashable {
    case week
    case month
}

enum NativeUsageGrouping: Hashable {
    case days
    case models
    case agents
}

enum NativeUsageMetric: Hashable {
    case cost
    case tokens

    func value(cost: Double, tokens: Double) -> Double {
        switch self {
        case .cost: cost
        case .tokens: tokens
        }
    }

    /// Exact figure, for rows and headlines.
    func full(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        switch self {
        case .cost: return value.formatted(.currency(code: "USD"))
        case .tokens: return Int(value.rounded()).formatted()
        }
    }

    /// Short figure, for chart axes and tight tiles.
    func compact(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        switch self {
        case .cost: return value.formatted(.currency(code: "USD").notation(.compactName))
        case .tokens: return value.formatted(.number.notation(.compactName))
        }
    }
}

enum NativeUsageError: LocalizedError {
    case unexpectedShape

    var errorDescription: String? {
        switch self {
        case .unexpectedShape:
            String(localized: "The Gateway returned an unexpected usage response.")
        }
    }
}

@MainActor
@Observable
final class NativeUsageModel {
    var state: NativeLoadState<NativeUsageSnapshot> = .idle
    /// Failure of a pull-to-refresh while content is already shown; surfaced as an alert.
    var refreshError: String?

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(NativeGateway.offlineMessage)
            return
        }
        if showSpinner { self.state = .loading }
        do {
            // usage.cost with the same params as RootSidebarModel.
            let raw: Any = try await NativeGateway.request(
                appModel: appModel,
                method: "usage.cost",
                paramsJSON: CostUsageRequest.monthParamsJSON(),
                timeoutSeconds: 12)
            guard let root = raw as? [String: Any] else { throw NativeUsageError.unexpectedShape }
            let totals: [String: Any]? = root.dict("totals")
            var snapshot = NativeUsageSnapshot(
                days: Self.days(from: root),
                totalCost: totals?.double("totalCost"),
                totalTokens: totals?.double("totalTokens"))
            let breakdown = await self.loadBreakdown(appModel: appModel)
            try Task.checkCancellation()
            snapshot.models = breakdown?.models
            snapshot.agents = breakdown?.agents
            self.state = .loaded(snapshot)
        } catch is CancellationError {
            return
        } catch {
            if !showSpinner, case .loaded = self.state {
                self.refreshError = error.localizedDescription
                return
            }
            self.state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Breakdown

    private func loadBreakdown(
        appModel: NodeAppModel) async -> (models: [NativeUsageBreakdownItem], agents: [NativeUsageBreakdownItem])?
    {
        let params: [String: Any] = [
            "range": "30d",
            "mode": "specific",
            "timeZone": TimeZone.current.identifier,
            "agentScope": "all",
            "limit": 1,
        ]
        do {
            let raw: Any = try await NativeGateway.request(
                appModel: appModel,
                method: "sessions.usage",
                paramsJSON: NativeGateway.paramsJSON(params),
                timeoutSeconds: 15)
            guard let root = raw as? [String: Any], let aggregates = root.dict("aggregates") else {
                return nil
            }
            return (
                models: Self.models(aggregates.array("byModel")),
                agents: Self.agents(aggregates.array("byAgent")))
        } catch {
            // Optional data: the Gateway may not expose sessions.usage.
            return nil
        }
    }

    private static func models(_ rows: [[String: Any]]) -> [NativeUsageBreakdownItem] {
        var result: [NativeUsageBreakdownItem] = []
        for row in rows {
            let model: String = row.string("model") ?? ""
            guard !model.isEmpty else { continue }
            let provider: String? = row.string("provider")
            let totals = Self.totals(row.dict("totals"))
            result.append(NativeUsageBreakdownItem(
                id: (provider ?? "") + "/" + model,
                title: model,
                subtitle: provider,
                cost: totals.cost,
                tokens: totals.tokens,
                requests: row.int("count")))
        }
        return result
    }

    private static func agents(_ rows: [[String: Any]]) -> [NativeUsageBreakdownItem] {
        var result: [NativeUsageBreakdownItem] = []
        for row in rows {
            let agent: String = row.string("agentId") ?? ""
            guard !agent.isEmpty else { continue }
            let totals = Self.totals(row.dict("totals"))
            result.append(NativeUsageBreakdownItem(
                id: agent,
                title: agent,
                cost: totals.cost,
                tokens: totals.tokens))
        }
        return result
    }

    private static func totals(_ dict: [String: Any]?) -> (cost: Double, tokens: Double) {
        let cost: Double = dict?.double("totalCost") ?? 0
        let tokens: Double = dict?.double("totalTokens") ?? 0
        return (cost.isFinite ? cost : 0, tokens.isFinite ? tokens : 0)
    }

    // MARK: - Daily series

    private static func days(from root: [String: Any]) -> [NativeUsageDay] {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        var result: [NativeUsageDay] = []
        for entry in root.array("daily") {
            guard let dateString = entry.string("date"), let date = parser.date(from: dateString) else {
                continue
            }
            let cost: Double = entry.double("totalCost") ?? 0
            let tokens: Double = entry.double("totalTokens") ?? 0
            result.append(NativeUsageDay(
                id: dateString,
                date: date,
                cost: cost.isFinite ? cost : 0,
                tokens: tokens.isFinite ? tokens : 0))
        }
        return result.sorted { $0.date < $1.date }
    }
}
