import Charts
import SwiftUI
import UIKit

/// Native Usage page: glass range + metric switches, glass headline tiles, Swift Charts
/// (cost / tokens per day, per model, per agent) and matching lists.
/// Data types live in `Usage/NativeUsageModel.swift`, building blocks in `Usage/NativeUsageViews.swift`.
/// Gestures: pull to refresh, touch-and-hold scrubbing on charts, swipe and long press to copy a figure.
struct NativeUsageScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = NativeUsageModel()
    @State private var selectedDate: Date?
    @State private var selectedTitle: String?
    @State private var range: NativeUsageRange = .month
    @State private var grouping: NativeUsageGrouping = .days
    @State private var metric: NativeUsageMetric = .cost
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
            .background { OpenClawProBackground() }
            .nativeChrome(title: self.title, sidebar: self.headerSidebarAction)
            .nativeErrorAlert(self.$model.refreshError)
        }
        .task { await self.model.load(appModel: self.appModel, showSpinner: true) }
        .onChange(of: self.range) { _, _ in self.selectedDate = nil }
        .onChange(of: self.grouping) { _, _ in
            self.selectedDate = nil
            self.selectedTitle = nil
        }
        .onChange(of: self.metric) { _, _ in self.selectedTitle = nil }
        .sensoryFeedback(.selection, trigger: self.grouping)
        .sensoryFeedback(.selection, trigger: self.metric)
        .sensoryFeedback(.selection, trigger: self.range)
    }

    // MARK: - Derived data

    private func visibleDays(_ snapshot: NativeUsageSnapshot) -> [NativeUsageDay] {
        switch self.range {
        case .week: Array(snapshot.days.suffix(7))
        case .month: snapshot.days
        }
    }

    /// Tokens are only offered when the Gateway reported some.
    private func hasTokens(_ snapshot: NativeUsageSnapshot) -> Bool {
        snapshot.days.contains { $0.tokens > 0 } || (snapshot.totalTokens ?? 0) > 0
    }

    private func effectiveMetric(_ snapshot: NativeUsageSnapshot) -> NativeUsageMetric {
        self.hasTokens(snapshot) ? self.metric : .cost
    }

    // MARK: - Content

    private func content(_ snapshot: NativeUsageSnapshot) -> some View {
        let days: [NativeUsageDay] = self.visibleDays(snapshot)
        let metric: NativeUsageMetric = self.effectiveMetric(snapshot)
        return List {
            Section {
                self.tiles(snapshot: snapshot, days: days)
                    .ngCardRow()
                self.controls(snapshot: snapshot)
                    .ngCardRow()
            }
            switch self.grouping {
            case .days:
                self.daysSections(days: days, metric: metric)
            case .models:
                self.breakdownSections(
                    items: snapshot.models,
                    header: "By model",
                    metric: metric)
            case .agents:
                self.breakdownSections(
                    items: snapshot.agents,
                    header: "By agent",
                    metric: metric)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await self.model.load(appModel: self.appModel, showSpinner: false) }
        .openClawAnimation(value: self.range)
        .openClawAnimation(value: self.grouping)
        .openClawAnimation(value: self.metric)
    }

    // MARK: - Tiles

    private func tiles(snapshot: NativeUsageSnapshot, days: [NativeUsageDay]) -> some View {
        let costSum: Double = days.reduce(0) { $0 + $1.cost }
        let tokenSum: Double = days.reduce(0) { $0 + $1.tokens }
        let totalCost: Double = (self.range == .month ? snapshot.totalCost : nil) ?? costSum
        let totalTokens: Double = (self.range == .month ? snapshot.totalTokens : nil) ?? tokenSum
        let activeCost: [Double] = days.map(\.cost).filter { $0 > 0 }
        var data: [NativeUsageTileData] = [
            NativeUsageTileData(
                id: "total",
                title: String(localized: "Total cost"),
                value: NativeUsageMetric.cost.full(totalCost),
                systemImage: "dollarsign.circle",
                tint: OpenClawBrand.accent),
        ]
        if !activeCost.isEmpty {
            let average: Double = activeCost.reduce(0, +) / Double(activeCost.count)
            data.append(NativeUsageTileData(
                id: "average",
                title: String(localized: "Average per active day"),
                value: NativeUsageMetric.cost.full(average),
                systemImage: "chart.line.flattrend.xyaxis",
                tint: OpenClawBrand.info))
        }
        if let peak = days.map(\.cost).max(), peak > 0 {
            data.append(NativeUsageTileData(
                id: "peak",
                title: String(localized: "Peak day"),
                value: NativeUsageMetric.cost.full(peak),
                systemImage: "arrow.up.right",
                tint: OpenClawBrand.warn))
        }
        if self.hasTokens(snapshot) {
            data.append(NativeUsageTileData(
                id: "tokens",
                title: String(localized: "Tokens"),
                value: NativeUsageMetric.tokens.compact(totalTokens),
                systemImage: "text.alignleft",
                tint: OpenClawBrand.ok))
        }
        return NativeUsageTileGrid(tiles: data)
    }

    // MARK: - Controls

    private func controls(snapshot: NativeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OpenClawGlassSegmented(selection: self.$range, options: self.rangeOptions)
            OpenClawGlassChipRow {
                OpenClawGlassChip(
                    title: "Days",
                    systemImage: "calendar",
                    isSelected: self.grouping == .days)
                {
                    self.setGrouping(.days)
                }
                OpenClawGlassChip(
                    title: "Models",
                    systemImage: "cpu",
                    isSelected: self.grouping == .models)
                {
                    self.setGrouping(.models)
                }
                OpenClawGlassChip(
                    title: "Agents",
                    systemImage: "person.2",
                    isSelected: self.grouping == .agents)
                {
                    self.setGrouping(.agents)
                }
                if self.hasTokens(snapshot) {
                    OpenClawGlassChip(
                        title: self.metric == .cost ? "Cost" : "Tokens",
                        systemImage: "arrow.left.arrow.right",
                        isSelected: false,
                        tint: OpenClawBrand.info)
                    {
                        self.toggleMetric()
                    }
                }
            }
            .padding(.horizontal, -OpenClawProMetric.pagePadding)
        }
    }

    private var rangeOptions: [OpenClawGlassSegmented<NativeUsageRange>.Option] {
        [
            OpenClawGlassSegmented<NativeUsageRange>.Option(.week, title: "7 days"),
            OpenClawGlassSegmented<NativeUsageRange>.Option(.month, title: "31 days"),
        ]
    }

    private func setGrouping(_ value: NativeUsageGrouping) {
        guard value != self.grouping else { return }
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) { self.grouping = value }
    }

    private func toggleMetric() {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.metric = self.metric == .cost ? .tokens : .cost
        }
    }

    // MARK: - Days

    @ViewBuilder
    private func daysSections(days: [NativeUsageDay], metric: NativeUsageMetric) -> some View {
        if !days.isEmpty {
            Section {
                NativeUsageDayChart(
                    days: days,
                    metric: metric,
                    range: self.range,
                    selectedDate: self.$selectedDate)
                    .ngCardRow()
            } header: {
                NativeSettingsHeader(metric == .cost ? "Daily cost" : "Daily tokens")
            }
            Section {
                let peak: Double = days.map { metric.value(cost: $0.cost, tokens: $0.tokens) }.max() ?? 0
                ForEach(days.reversed()) { day in
                    let value: Double = metric.value(cost: day.cost, tokens: day.tokens)
                    let label: String = day.date.formatted(.dateTime.weekday(.abbreviated).month().day())
                    NativeUsageRow(
                        title: label,
                        value: metric.full(value),
                        detail: self.otherMetricText(cost: day.cost, tokens: day.tokens, metric: metric),
                        fraction: peak > 0 ? value / peak : 0)
                        .ngCardRow()
                        .swipeActions(edge: .trailing) { self.copyAction(metric.full(value)) }
                        .contextMenu { self.copyMenu(metric.full(value)) }
                }
            } header: {
                NativeSettingsHeader("Days")
            }
        }
    }

    // MARK: - Models / agents

    @ViewBuilder
    private func breakdownSections(
        items: [NativeUsageBreakdownItem]?,
        header: LocalizedStringKey,
        metric: NativeUsageMetric) -> some View
    {
        if let items {
            let sorted: [NativeUsageBreakdownItem] = items.sorted {
                metric.value(cost: $0.cost, tokens: $0.tokens) > metric.value(cost: $1.cost, tokens: $1.tokens)
            }
            if sorted.isEmpty {
                Section {
                    NativeInlineNotice(
                        message: String(localized: "No usage recorded"),
                        systemImage: "chart.bar.xaxis")
                        .ngCardRow()
                }
            } else {
                Section {
                    NativeUsageBreakdownChart(
                        items: Array(sorted.prefix(8)),
                        metric: metric,
                        selectedTitle: self.$selectedTitle)
                        .ngCardRow()
                } header: {
                    NativeSettingsHeader(header)
                }
                Section {
                    let peak: Double = sorted.map { metric.value(cost: $0.cost, tokens: $0.tokens) }.max() ?? 0
                    ForEach(sorted) { item in
                        let value: Double = metric.value(cost: item.cost, tokens: item.tokens)
                        NativeUsageRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            value: metric.full(value),
                            detail: self.otherMetricText(cost: item.cost, tokens: item.tokens, metric: metric),
                            fraction: peak > 0 ? value / peak : 0)
                            .ngCardRow()
                            .swipeActions(edge: .trailing) { self.copyAction(item.title) }
                            .contextMenu {
                                self.copyMenu(item.title)
                                self.copyMenu(metric.full(value))
                            }
                    }
                } header: {
                    NativeSettingsHeader("Details")
                }
            }
        } else {
            Section {
                NativeInlineNotice(
                    message: String(localized: "This Gateway does not report usage by model or agent."),
                    systemImage: "info.circle")
                    .ngCardRow()
            }
        }
    }

    // MARK: - Helpers

    private func otherMetricText(cost: Double, tokens: Double, metric: NativeUsageMetric) -> String? {
        switch metric {
        case .cost:
            return tokens > 0 ? NativeUsageMetric.tokens.compact(tokens) : nil
        case .tokens:
            return cost > 0 ? NativeUsageMetric.cost.full(cost) : nil
        }
    }

    private func copyAction(_ text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .tint(OpenClawBrand.info)
    }

    private func copyMenu(_ text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
        } label: {
            Label {
                Text(verbatim: text)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
    }
}
