import Charts
import SwiftUI

// Building blocks of the native Usage page.
// Glass is used for controls and headline tiles; reading content (rows, charts) stays on quiet surfaces.

// MARK: - Tiles

struct NativeUsageTileData: Identifiable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .secondary
}

/// Row of glass headline tiles (total, average, peak, ...).
struct NativeUsageTileGrid: View {
    let tiles: [NativeUsageTileData]

    var body: some View {
        OpenClawGlassControlGroup {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(self.tiles) { tile in
                    self.tileView(tile)
                }
            }
        }
    }

    private func tileView(_ tile: NativeUsageTileData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: tile.systemImage)
                    .font(OpenClawType.captionSemiBold)
                    .foregroundStyle(tile.tint)
                    .accessibilityHidden(true)
                Text(verbatim: tile.title)
                    .font(OpenClawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(verbatim: tile.value)
                .font(OpenClawType.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .openClawGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            tint: tile.tint.opacity(0.10))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Row

/// One day / model / agent: title, figure, and a thin share bar relative to the largest row.
struct NativeUsageRow: View {
    let title: String
    var subtitle: String?
    let value: String
    var detail: String?
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: self.title)
                        .font(OpenClawType.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle = self.subtitle {
                        Text(verbatim: subtitle)
                            .font(OpenClawType.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: self.value)
                        .font(OpenClawType.subheadSemiBold)
                        .monospacedDigit()
                    if let detail = self.detail {
                        Text(verbatim: detail)
                            .font(OpenClawType.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            self.shareBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .ngCardSurface(radius: 14)
        .accessibilityElement(children: .combine)
    }

    private var shareBar: some View {
        let clamped: Double = min(max(self.fraction.isFinite ? self.fraction : 0, 0), 1)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(uiColor: .tertiarySystemFill))
                Capsule()
                    .fill(OpenClawBrand.accent.opacity(0.75))
                    .frame(width: clamped > 0 ? max(4, proxy.size.width * clamped) : 0)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Daily chart

/// Bars per day with an average rule and touch scrubbing.
struct NativeUsageDayChart: View {
    let days: [NativeUsageDay]
    let metric: NativeUsageMetric
    let range: NativeUsageRange
    @Binding var selectedDate: Date?

    @State private var style: NativeUsageChartStyle = .bars

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                self.selectionHeader
                    .frame(maxWidth: .infinity, alignment: .leading)
                NativeUsageStylePicker(style: self.$style, options: [.bars, .line])
            }
            Chart {
                ForEach(self.days) { day in
                    if self.style == .line {
                        LineMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Value", self.value(day)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(OpenClawBrand.accent)
                            .accessibilityLabel(day.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                            .accessibilityValue(self.metric.full(self.value(day)))
                    } else {
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Value", self.value(day)))
                            .foregroundStyle(self.barColor(for: day))
                            .cornerRadius(3)
                            .accessibilityLabel(day.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                            .accessibilityValue(self.metric.full(self.value(day)))
                    }
                }
                if let average = self.average {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
                if let selected = self.selectedDay {
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
                                value: self.metric.full(self.value(selected)))
                        }
                }
            }
            .chartXSelection(value: self.$selectedDate)
            .chartXAxis {
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
                        if let number = value.as(Double.self) {
                            Text(verbatim: self.metric.compact(number))
                        }
                    }
                }
            }
            .frame(minHeight: 200)
            .openClawChartReveal()
            .openClawAnimation(value: self.selectedDate)
            .accessibilityLabel(Text("Daily usage chart"))
            .accessibilityValue(Text(verbatim: self.summary))
        }
        .padding(14)
        .ngCardSurface(radius: 16)
    }

    private func value(_ day: NativeUsageDay) -> Double {
        self.metric.value(cost: day.cost, tokens: day.tokens)
    }

    private var average: Double? {
        let active: [Double] = self.days.map { self.value($0) }.filter { $0 > 0 }
        guard !active.isEmpty else { return nil }
        return active.reduce(0, +) / Double(active.count)
    }

    private var selectedDay: NativeUsageDay? {
        guard let selected = self.selectedDate else { return nil }
        return self.days.first { Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    private func barColor(for day: NativeUsageDay) -> Color {
        guard let selected = self.selectedDate else { return OpenClawBrand.accent }
        let same: Bool = Calendar.current.isDate(day.date, inSameDayAs: selected)
        return same ? OpenClawBrand.accent : OpenClawBrand.accent.opacity(0.4)
    }

    private var summary: String {
        let peak: Double? = self.days.map { self.value($0) }.max()
        let peakText: String = peak.map { self.metric.full($0) } ?? "-"
        return String(localized: "\(self.days.count) days, peak \(peakText)")
    }

    @ViewBuilder
    private var selectionHeader: some View {
        if let selected = self.selectedDay {
            HStack {
                Text(selected.date, format: .dateTime.weekday(.abbreviated).month().day())
                    .font(OpenClawType.subheadSemiBold)
                Spacer()
                Text(verbatim: self.metric.full(self.value(selected)))
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
}

// MARK: - Breakdown chart

/// Horizontal bars per model or per agent, with touch selection on the category axis.
struct NativeUsageBreakdownChart: View {
    let items: [NativeUsageBreakdownItem]
    let metric: NativeUsageMetric
    @Binding var selectedTitle: String?

    @State private var style: NativeUsageChartStyle = .bars

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            self.selectionHeader
                .frame(maxWidth: .infinity, alignment: .leading)
            NativeUsageStylePicker(style: self.$style, options: [.bars, .share])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.headerRow
            if self.style == .share {
                NativeUsageShareChart(
                    items: self.items,
                    metric: self.metric,
                    selectedTitle: self.$selectedTitle)
            } else {
                self.barsChart
            }
        }
        .padding(14)
        .ngCardSurface(radius: 16)
    }

    private var barsChart: some View {
            Chart(self.items) { item in
                BarMark(
                    x: .value("Value", self.value(item)),
                    y: .value("Name", item.title))
                    .foregroundStyle(self.barColor(for: item))
                    .cornerRadius(4)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(self.metric.full(self.value(item)))
            }
            .chartYSelection(value: self.$selectedTitle)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(verbatim: self.metric.compact(number))
                        }
                    }
                }
            }
            .frame(height: CGFloat(max(self.items.count, 1)) * 36 + 28)
            .openClawChartReveal()
            .openClawAnimation(value: self.selectedTitle)
    }

    private func value(_ item: NativeUsageBreakdownItem) -> Double {
        self.metric.value(cost: item.cost, tokens: item.tokens)
    }

    private func barColor(for item: NativeUsageBreakdownItem) -> Color {
        guard let selected = self.selectedTitle else { return OpenClawBrand.accent }
        return item.title == selected ? OpenClawBrand.accent : OpenClawBrand.accent.opacity(0.4)
    }

    @ViewBuilder
    private var selectionHeader: some View {
        if let title = self.selectedTitle, let item = self.items.first(where: { $0.title == title }) {
            HStack {
                Text(verbatim: item.title)
                    .font(OpenClawType.subheadSemiBold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(verbatim: self.metric.full(self.value(item)))
                    .font(OpenClawType.subheadSemiBold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        } else {
            Text("Touch and hold the chart to inspect a bar.")
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
