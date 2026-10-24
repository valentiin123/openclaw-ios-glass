import Charts
import SwiftUI

/// Graphique natif (barres, lignes, secteurs) sur surface opaque. Aucun Liquid Glass ici.
struct WidgetChartView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let spec: WidgetChartSpec
    var height: CGFloat = 240

    @State private var appeared = false
    @State private var selectedX: String?

    /// Point aplati avec tous ses textes précalculés : le compilateur n'a plus rien à inférer dans le builder.
    private struct FlatPoint: Identifiable {
        let id: Int
        let x: String
        let y: Double
        let series: String
        let accessibilityValue: String
    }

    private var chartHeight: CGFloat {
        if spec.kind == .sparkline { return 56 }
        // Dynamic Type : on laisse plus de place aux légendes et aux axes.
        return typeSize.isAccessibilitySize ? height * 1.4 : height
    }

    /// Points de la première série non vide, indexés par position (axe X numérique pour la sparkline).
    private var sparklinePoints: [FlatPoint] {
        let first = self.spec.series.first(where: { series in !series.points.isEmpty })
        let source: [WidgetChartSpec.Point] = first?.points ?? []
        var result: [FlatPoint] = []
        for (index, point) in source.enumerated() {
            let valueText: String = point.y.formatted()
            result.append(FlatPoint(
                id: index,
                x: point.x,
                y: point.y,
                series: first?.name ?? "",
                accessibilityValue: valueText))
        }
        return result
    }

    /// Texte de la valeur sélectionnée au doigt (graphique en lignes).
    private var selectionText: String? {
        guard let selectedX else { return nil }
        let match = self.flatPoints.first(where: { point in point.x == selectedX })
        guard let match else { return nil }
        return match.x + " · " + match.accessibilityValue
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
            selectionReadout
        }
        .onAppear {
            guard !appeared else { return }
            if reduceMotion { appeared = true } else {
                withAnimation(OpenClawMotion.animation(reduceMotion: reduceMotion)) { appeared = true }
            }
        }
    }

    @ViewBuilder
    private var selectionReadout: some View {
        if spec.kind == .line, let text = selectionText {
            Text(verbatim: text)
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch spec.kind {
        case .bar:
            self.barChart
        case .line:
            self.lineChart
        case .area:
            self.areaChart
        case .pie:
            self.pieChart
        case .sparkline:
            self.sparklineChart
        }
    }

    private var sparklineChart: some View {
        let data: [FlatPoint] = self.sparklinePoints
        let xKey: Text = self.xAxisKey
        let yKey: Text = self.yAxisKey
        return Chart(data) { (point: FlatPoint) in
            AreaMark(
                x: .value(xKey, point.id),
                y: .value(yKey, point.y))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor.opacity(0.15))
            LineMark(
                x: .value(xKey, point.id),
                y: .value(yKey, point.y))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
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
        .chartXSelection(value: self.$selectedX)
        .modifier(AxisLabels(x: self.spec.xLabel, y: self.spec.yLabel, legend: self.showsLegend))
    }

    private var areaChart: some View {
        let data: [FlatPoint] = self.flatPoints
        let xKey: Text = self.xAxisKey
        let yKey: Text = self.yAxisKey
        let sKey: Text = self.seriesKey
        return Chart(data) { (point: FlatPoint) in
            AreaMark(
                x: .value(xKey, point.x),
                y: .value(yKey, point.y))
                .foregroundStyle(by: .value(sKey, point.series))
                .interpolationMethod(.monotone)
                .opacity(0.35)
                .accessibilityLabel(point.x)
                .accessibilityValue(point.accessibilityValue)
            LineMark(
                x: .value(xKey, point.x),
                y: .value(yKey, point.y))
                .foregroundStyle(by: .value(sKey, point.series))
                .interpolationMethod(.monotone)
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
