import Charts
import SwiftUI

// Donut chart for the per-model / per-agent share of usage.
// Reading content stays on the opaque card surface; the only glass is the shared selection tooltip.

struct NativeUsageShareChart: View {
    let items: [NativeUsageBreakdownItem]
    let metric: NativeUsageMetric
    @Binding var selectedTitle: String?

    @State private var selectedAngle: Double?

    private static let palette: [Color] = NativeUsagePalette.colors

    private var slices: [NativeUsageBreakdownItem] {
        self.items.filter { self.value($0) > 0 }
    }

    private var total: Double {
        self.slices.reduce(0) { $0 + self.value($1) }
    }

    private var colorRange: [Color] {
        self.slices.indices.map { Self.palette[$0 % Self.palette.count] }
    }

    private var selectedItem: NativeUsageBreakdownItem? {
        guard let title = self.selectedTitle else { return nil }
        return self.slices.first { $0.title == title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if self.slices.isEmpty {
                Text("No usage recorded")
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
            } else {
                self.donut
                self.legend
            }
        }
    }

    private var donut: some View {
        let titles: [String] = self.slices.map { $0.title }
        return Chart(self.slices) { item in
            SectorMark(
                angle: .value("Value", self.value(item)),
                innerRadius: .ratio(0.62),
                angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(by: .value("Name", item.title))
                .opacity(self.selectedTitle == nil || self.selectedTitle == item.title ? 1 : 0.4)
                .accessibilityLabel(item.title)
                .accessibilityValue(self.metric.full(self.value(item)))
        }
        .chartForegroundStyleScale(domain: titles, range: self.colorRange)
        .chartLegend(.hidden)
        .chartAngleSelection(value: self.$selectedAngle)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame {
                    let rect: CGRect = geometry[frame]
                    self.centerLabel
                        .frame(width: rect.width * 0.5)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(height: 200)
        .openClawChartReveal()
        .openClawAnimation(value: self.selectedTitle)
        .sensoryFeedback(.selection, trigger: self.selectedTitle)
        .onChange(of: self.selectedAngle) { _, angle in
            self.selectedTitle = self.item(at: angle)?.title
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            if let item = self.selectedItem {
                Text(verbatim: item.title)
                    .font(OpenClawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: self.percent(self.value(item)))
                    .font(OpenClawType.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                Text(verbatim: self.metric.compact(self.total))
                    .font(OpenClawType.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], spacing: 6) {
            ForEach(Array(self.slices.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.palette[index % Self.palette.count])
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(verbatim: item.title)
                        .font(OpenClawType.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: self.percent(self.value(item)))
                        .font(OpenClawType.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func value(_ item: NativeUsageBreakdownItem) -> Double {
        self.metric.value(cost: item.cost, tokens: item.tokens)
    }

    private func percent(_ value: Double) -> String {
        guard self.total > 0 else { return "-" }
        return (value / self.total).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Maps the cumulative angle value reported by `chartAngleSelection` to a slice.
    private func item(at angle: Double?) -> NativeUsageBreakdownItem? {
        guard let angle else { return nil }
        var running: Double = 0
        for item in self.slices {
            running += self.value(item)
            if angle <= running { return item }
        }
        return nil
    }
}
