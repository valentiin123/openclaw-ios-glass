import Charts
import SwiftUI

/// Graphique natif (barres, lignes, secteurs) sur surface opaque. Aucun Liquid Glass ici.
struct WidgetChartView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let spec: WidgetChartSpec
    var height: CGFloat = 240

    @State private var appeared = false

    /// Point aplati avec tous ses textes précalculés : le compilateur n'a plus rien à inférer dans le builder.
    private struct FlatPoint: Identifiable {
        let id: Int
        let x: String
        let y: Double
        let series: String
        let accessibilityValue: String
    }

    private var chartHeight: CGFloat {
        // Dynamic Type : on laisse plus de place aux légendes et aux axes.
        typeSize.isAccessibilitySize ? height * 1.4 : height
    }

    private var flatPoints: [FlatPoint] {
        var result: [FlatPoint] = []
        var counter = 0
        for series in self.spec.series {
            let seriesName: String = series.name
            for point in series.points {
                let valueText: String = point.y.formatted()
                let described: String = seriesName + ": " + valueText
                let flat = FlatPoint(
                    id: counter,
                    x: point.x,
                    y: point.y,
                    series: seriesName,
                    accessibilityValue: described)
                result.append(flat)
                counter += 1
            }
        }
        return result
    }

    private var xAxisKey: Text {
        Text(verbatim: self.spec.xLabel ?? "X")
    }

    private var yAxisKey: Text {
        Text(verbatim: self.spec.yLabel ?? "Y")
    }

    private var seriesKey: Text {
        Text(verbatim: "Series")
    }

    private var showsLegend: Bool {
        self.spec.series.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = spec.title, !title.isEmpty {
                Text(title)
                    .font(OpenClawType.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            chart
                .frame(height: chartHeight)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(spec.accessibilitySummary)
        }
        .onAppear {
            guard !appeared else { return }
            if reduceMotion { appeared = true } else {
                withAnimation(OpenClawMotion.animation(reduceMotion: reduceMotion)) { appeared = true }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch spec.kind {
        case .bar:
            self.barChart
        case .line:
            self.lineChart
        case .pie:
            self.pieChart
        }
    }

    private var barChart: some View {
        let data: [FlatPoint] = self.flatPoints
        let xKey: Text = self.xAxisKey
        let yKey: Text = self.yAxisKey
        let sKey: Text = self.seriesKey
        return Chart(data) { (point: FlatPoint) in
            BarMark(
                x: .value(xKey, point.x),
                y: .value(yKey, point.y))
                .foregroundStyle(by: .value(sKey, point.series))
                .position(by: .value(sKey, point.series))
                .accessibilityLabel(point.x)
                .accessibilityValue(point.accessibilityValue)
        }
        .modifier(AxisLabels(x: self.spec.xLabel, y: self.spec.yLabel, legend: self.showsLegend))
    }

    private var lineChart: some View {
        let data: [FlatPoint] = self.flatPoints
        let xKey: Text = self.xAxisKey
        let yKey: Text = self.yAxisKey
        let sKey: Text = self.seriesKey
        return Chart(data) { (point: FlatPoint) in
            LineMark(
                x: .value(xKey, point.x),
                y: .value(yKey, point.y))
                .foregroundStyle(by: .value(sKey, point.series))
                .interpolationMethod(.monotone)
                .accessibilityLabel(point.x)
                .accessibilityValue(point.accessibilityValue)
            PointMark(
                x: .value(xKey, point.x),
                y: .value(yKey, point.y))
                .foregroundStyle(by: .value(sKey, point.series))
                .accessibilityHidden(true)
        }
        .modifier(AxisLabels(x: self.spec.xLabel, y: self.spec.yLabel, legend: self.showsLegend))
    }

    private var pieChart: some View {
        // Un secteur par point de la première série non vide.
        let firstSeries = self.spec.series.first(where: { series in !series.points.isEmpty })
        let allPoints = firstSeries?.points ?? []
        let positive = allPoints.filter { point in point.y > 0 }
        var slices: [FlatPoint] = []
        for (index, point) in positive.enumerated() {
            let valueText: String = point.y.formatted()
            slices.append(FlatPoint(
                id: index,
                x: point.x,
                y: point.y,
                series: point.x,
                accessibilityValue: valueText))
        }
        let categoryKey: Text = Text(verbatim: "Category")
        let valueKey: Text = Text(verbatim: "Value")
        return Chart(slices) { (slice: FlatPoint) in
            SectorMark(
                angle: .value(valueKey, slice.y),
                innerRadius: .ratio(0.5),
                angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(by: .value(categoryKey, slice.x))
                .accessibilityLabel(slice.x)
                .accessibilityValue(slice.accessibilityValue)
        }
        .chartLegend(position: .bottom, alignment: .center)
    }
}

private struct AxisLabels: ViewModifier {
    let x: String?
    let y: String?
    let legend: Bool

    func body(content: Content) -> some View {
        let legendVisibility: Visibility = self.legend ? .visible : .hidden
        content
            .chartXAxisLabel(self.x ?? "", alignment: .center)
            .chartYAxisLabel(self.y ?? "", alignment: .center)
            .chartLegend(legendVisibility)
    }
}
