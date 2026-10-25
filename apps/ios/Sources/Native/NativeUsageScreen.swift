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

enum NativeUsageRange: Hashable {
    case week
    case month
}

/// Native Usage page: range switch, headline total, Swift Charts bar chart with scrubbing, per-day list.
/// Content sits on opaque grouped surfaces; glass only comes from system bars and controls.
struct NativeUsageScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @State private var model = NativeUsageModel()
    @State private var selectedDate: Date?
    @State private var range: NativeUsageRange = .month
    let title: String
    var headerSidebarAction: OpenClawSidebarHeaderAction?

    private static let segments: [NativeSegment<NativeUsageRange>] = [
        NativeSegment(id: .week, title: String(localized: "7 days")),
        NativeSegment(id: .month, title: String(localized: "31 days")),
    ]

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
            .safeAreaInset(edge: .top, spacing: 0) {
                NativeSegmentedBar(segments: Self.segments, selection: self.$range)
            }
            .nativeChrome(title: self.title, sidebar: self.headerSidebarAction)
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        .onChange(of: self.range) { _, _ in self.selectedDate = nil }
    }

    private func visibleDays(_ snapshot: NativeUsageSnapshot) -> [NativeUsageDay] {
        switch self.range {
        case .week: Array(snapshot.days.suffix(7))
        case .month: snapshot.days
        }
    }

    private func content(_ snapshot: NativeUsageSnapshot) -> some View {
        let days: [NativeUsageDay] = self.visibleDays(snapshot)
        let sum: Double = days.reduce(0) { $0 + $1.cost }
        let total: Double = (self.range == .month ? snapshot.totalCost : nil) ?? sum
        return List {
            Section {
                NativeUsageSummary(
                    total: total,
                    average: Self.average(days),
                    peak: days.max(by: { $0.cost < $1.cost })?.cost)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if !days.isEmpty {
                Section {
                    self.chart(days)
                } header: {
                    Text("Daily cost")
                }
                Section {
                    ForEach(days.reversed()) { day in
                        NativeUsageDayRow(day: day)
                            .swipeActions(edge: .trailing) { self.copyAction(for: day) }
                            .contextMenu { self.menu(for: day) }
                    }
                } header: {
                    Text("Days")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await self.model.load(appModel: self.appModel, showSpinner: false) }
        .openClawAnimation(value: self.range)
    }

    private func chart(_ days: [NativeUsageDay]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            self.selectionHeader(days)
            Chart {
                ForEach(days) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Cost", day.cost))
                        .foregroundStyle(self.barColor(for: day))
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                        .accessibilityValue(day.cost.formatted(.currency(code: "USD")))
                }
                if let average = Self.average(days) {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
                if let selected = self.selectedDay(in: days) {
                    RuleMark(x: .value("Day", selected.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(
                            position: .top,
                            spacing: 4,
                            overflowResolution: AnnotationOverflowResolution(x: .fit(to: .chart), y: .disabled))
                        {
                            ChartSelectionTooltip(
                                title: selected.date.formatted(.dateTime.weekday(.abbreviated).month().day()),
                                value: selected.cost.formatted(.currency(code: "USD")))
                        }
                }
            }
            .chartXSelection(value: self.$selectedDate)
            .chartXAxis {
                // 7 jours : un libellé par jour ; 31 jours : un libellé par semaine, sinon l'axe est illisible.
                AxisMarks(values: .stride(by: .day, count: self.range == .week ? 1 : 7)) { _ in
                    AxisTick()
                    AxisValueLabel(
                        format: self.range == .week
                            ? Date.FormatStyle().weekday(.abbreviated)
                            : Date.FormatStyle().month(.abbreviated).day(),
                        centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let cost = value.as(Double.self) {
                            Text(cost, format: .currency(code: "USD").notation(.compactName))
                        }
                    }
                }
            }
            .frame(minHeight: 200)
            .openClawChartReveal()
            .openClawAnimation(value: self.selectedDate)
            .accessibilityLabel(Text("Daily cost chart"))
            .accessibilityValue(Text(Self.summary(days)))
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func selectionHeader(_ days: [NativeUsageDay]) -> some View {
        if let selected = self.selectedDay(in: days) {
            HStack {
                Text(selected.date, format: .dateTime.weekday(.abbreviated).month().day())
                    .font(OpenClawType.subheadSemiBold)
                Spacer()
                Text(selected.cost, format: .currency(code: "USD"))
                    .font(OpenClawType.subheadSemiBold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        } else {
            Text("Touch and hold the chart to inspect a day.")
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
        }
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
    private func copyAction(for day: NativeUsageDay) -> some View {
        Button {
            UIPasteboard.general.string = day.cost.formatted(.currency(code: "USD"))
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .tint(OpenClawBrand.info)
    }

    @ViewBuilder
    private func menu(for day: NativeUsageDay) -> some View {
        Button {
            UIPasteboard.general.string = day.cost.formatted(.currency(code: "USD"))
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }

    private static func average(_ days: [NativeUsageDay]) -> Double? {
        let active: [NativeUsageDay] = days.filter { $0.cost > 0 }
        guard !active.isEmpty else { return nil }
        return active.reduce(0) { $0 + $1.cost } / Double(active.count)
    }

    private static func summary(_ days: [NativeUsageDay]) -> String {
        let peak = days.max(by: { $0.cost < $1.cost })
        let peakText: String = peak.map { $0.cost.formatted(.currency(code: "USD")) } ?? "-"
        return String(localized: "\(days.count) days, peak \(peakText)")
    }
}

/// Headline total with two quiet secondary figures. One opaque surface, no glass.
private struct NativeUsageSummary: View {
    let total: Double
    let average: Double?
    let peak: Double?

    var body: some View {
        NativeSurface {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total cost")
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                    Text(self.total, format: .currency(code: "USD"))
                        .font(OpenClawType.title2SemiBold)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                HStack(alignment: .top, spacing: 16) {
                    if let average {
                        self.figure(title: "Average per active day", value: average)
                    }
                    if let peak {
                        self.figure(title: "Peak day", value: peak)
                    }
                }
            }
        }
    }

    private func figure(title: LocalizedStringKey, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD"))
                .font(OpenClawType.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct NativeUsageDayRow: View {
    let day: NativeUsageDay

    var body: some View {
        LabeledContent {
            Text(self.day.cost, format: .currency(code: "USD"))
                .monospacedDigit()
        } label: {
            Text(self.day.date, format: .dateTime.weekday(.abbreviated).month().day())
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
