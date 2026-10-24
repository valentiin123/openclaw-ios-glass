import Charts
import Observation
import SwiftUI
import UIKit

struct NativeUsageDay: Identifiable, Equatable {
    let id: String
    let date: Date
    let cost: Double
}

struct NativeUsageSnapshot {
    let days: [NativeUsageDay]
    let totalCost: Double?

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

@MainActor
@Observable
final class NativeUsageModel {
    var state: NativeLoadState<NativeUsageSnapshot> = .idle

    func load(appModel: NodeAppModel, showSpinner: Bool) async {
        guard appModel.isOperatorGatewayConnected else {
            self.state = .failed(NativeGateway.offlineMessage)
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
            let days: [NativeUsageDay] = Self.days(from: summary)
            self.state = .loaded(NativeUsageSnapshot(days: days, totalCost: summary.totalCost))
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    private static func days(from summary: CostUsageSummaryLite) -> [NativeUsageDay] {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        var result: [NativeUsageDay] = []
        for entry in summary.daily ?? [] {
            guard let date = parser.date(from: entry.date) else { continue }
            result.append(NativeUsageDay(id: entry.date, date: date, cost: entry.totalCost ?? 0))
        }
        return result
    }
}

/// Native Usage page: summary tiles, Swift Charts bar chart with scrubbing, per-day list.
/// Content sits on opaque grouped surfaces; no glass on content.
struct NativeUsageScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model = NativeUsageModel()
    @State private var selectedDate: Date?
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
                self.content(snapshot)
            }
            .nativeChrome(title: self.title, sidebar: self.headerSidebarAction)
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
    }

    private func content(_ snapshot: NativeUsageSnapshot) -> some View {
        List {
            Section {
                NativeUsageSummary(snapshot: snapshot)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if !snapshot.days.isEmpty {
                Section {
                    self.chart(snapshot)
                } header: {
                    Text("Daily cost")
                }
                Section {
                    ForEach(snapshot.days.reversed()) { day in
                        NativeUsageDayRow(day: day, peak: snapshot.peakDay?.id == day.id)
                            .contextMenu { self.menu(for: day) }
                    }
                } header: {
                    Text("Days")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await self.model.load(appModel: self.appModel, showSpinner: false) }
    }

    private func chart(_ snapshot: NativeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selected = self.selectedDay(in: snapshot.days) {
                HStack {
                    Text(selected.date, format: .dateTime.weekday(.abbreviated).month().day())
                        .font(OpenClawType.subheadSemiBold)
                    Spacer()
                    Text(selected.cost, format: .currency(code: "USD"))
                        .font(OpenClawType.subheadSemiBold)
                        .monospacedDigit()
                }
            }
            Chart(snapshot.days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Cost", day.cost))
                    .foregroundStyle(self.barColor(for: day))
            }
            .chartXSelection(value: self.$selectedDate)
            .frame(minHeight: 200)
            .accessibilityLabel(Text("Daily cost chart"))
            .accessibilityValue(Text(Self.summary(snapshot.days)))
        }
        .padding(.vertical, 6)
    }

    private func barColor(for day: NativeUsageDay) -> Color {
        guard let selected = self.selectedDate else { return OpenClawBrand.accent }
        let same: Bool = Calendar.current.isDate(day.date, inSameDayAs: selected)
        return same ? OpenClawBrand.accent : OpenClawBrand.accent.opacity(0.4)
    }

    private func selectedDay(in days: [NativeUsageDay]) -> NativeUsageDay? {
        guard let selected = self.selectedDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    @ViewBuilder
    private func menu(for day: NativeUsageDay) -> some View {
        Button {
            UIPasteboard.general.string = day.cost.formatted(.currency(code: "USD"))
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }

    private static func summary(_ days: [NativeUsageDay]) -> String {
        let peak = days.max(by: { $0.cost < $1.cost })
        let peakText: String = peak.map { $0.cost.formatted(.currency(code: "USD")) } ?? "-"
        return String(localized: "\(days.count) days, peak \(peakText)")
    }
}

private struct NativeUsageSummary: View {
    let snapshot: NativeUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let total = self.snapshot.totalCost {
                self.tile(title: "Last 31 days", value: total.formatted(.currency(code: "USD")))
            }
            HStack(spacing: 12) {
                if let average = self.snapshot.averageCost {
                    self.tile(title: "Average per active day", value: average.formatted(.currency(code: "USD")))
                }
                if let peak = self.snapshot.peakDay {
                    self.tile(title: "Peak day", value: peak.cost.formatted(.currency(code: "USD")))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(title: LocalizedStringKey, value: String) -> some View {
        NativeSurface {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
                Text(verbatim: value)
                    .font(OpenClawType.headline)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NativeUsageDayRow: View {
    let day: NativeUsageDay
    let peak: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if self.peak {
                    NativeBadge(text: String(localized: "Peak"), color: OpenClawBrand.warn)
                }
                Text(self.day.cost, format: .currency(code: "USD"))
                    .monospacedDigit()
            }
        } label: {
            Text(self.day.date, format: .dateTime.weekday(.abbreviated).month().day())
        }
        .accessibilityElement(children: .combine)
    }
}
