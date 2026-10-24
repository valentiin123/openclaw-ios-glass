import Charts
import Observation
import SwiftUI

struct NativeUsageDay: Identifiable, Equatable {
    let id: String
    let date: Date
    let cost: Double
}

struct NativeUsageSnapshot {
    let days: [NativeUsageDay]
    let totalCost: Double?
}

@MainActor
@Observable
final class NativeUsageModel {
    var state: NativeLoadState<NativeUsageSnapshot> = .idle

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(String(localized: "The operator connection is offline."))
            return
        }
        if showSpinner { self.state = .loading }
        do {
            // usage.cost with the same params as RootSidebarModel (verified in the repo).
            let data = try await appModel.operatorSession.request(
                method: "usage.cost",
                paramsJSON: CostUsageRequest.monthParamsJSON(),
                timeoutSeconds: 12)
            let summary = try JSONDecoder().decode(CostUsageSummaryLite.self, from: data)
            let parser = DateFormatter()
            parser.calendar = Calendar(identifier: .gregorian)
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "yyyy-MM-dd"
            let days = (summary.daily ?? []).compactMap { entry -> NativeUsageDay? in
                guard let date = parser.date(from: entry.date) else { return nil }
                return NativeUsageDay(id: entry.date, date: date, cost: entry.totalCost ?? 0)
            }
            self.state = .loaded(NativeUsageSnapshot(days: days, totalCost: summary.totalCost))
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }
}

/// Native Usage page: Swift Charts bar chart of daily cost plus a total. No glass on content.
struct NativeUsageScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model = NativeUsageModel()
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    var body: some View {
        NavigationStack {
            NativeStateView(
                state: self.model.state,
                isEmpty: { $0.days.isEmpty && $0.totalCost == nil },
                emptyTitle: "No usage recorded",
                emptyIcon: "chart.bar.xaxis",
                retry: { await self.model.load(appModel: self.appModel, showSpinner: true) })
            { snapshot in
                List {
                    if let total = snapshot.totalCost {
                        Section("Last 31 days") {
                            LabeledContent("Total cost") {
                                Text(total, format: .currency(code: "USD"))
                                    .monospacedDigit()
                            }
                        }
                    }
                    if !snapshot.days.isEmpty {
                        Section("Daily cost") {
                            Chart(snapshot.days) { day in
                                BarMark(
                                    x: .value("Day", day.date, unit: .day),
                                    y: .value("Cost", day.cost))
                            }
                            .frame(minHeight: 180)
                            .accessibilityLabel(Text("Daily cost chart"))
                            .accessibilityValue(Text(Self.summary(snapshot.days)))
                            ForEach(snapshot.days.reversed()) { day in
                                LabeledContent {
                                    Text(day.cost, format: .currency(code: "USD")).monospacedDigit()
                                } label: {
                                    Text(day.date, format: .dateTime.month().day())
                                }
                            }
                        }
                    }
                }
                .refreshable { await self.model.load(appModel: self.appModel, showSpinner: false) }
            }
            .navigationTitle(self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let headerSidebarAction {
                    OpenClawSidebarToolbarItem(action: headerSidebarAction, placement: .topBarLeading)
                }
            }
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
    }

    private static func summary(_ days: [NativeUsageDay]) -> String {
        let peak = days.max(by: { $0.cost < $1.cost })
        let peakText = peak.map { $0.cost.formatted(.currency(code: "USD")) } ?? "-"
        return String(localized: "\(days.count) days, peak \(peakText)")
    }
}
