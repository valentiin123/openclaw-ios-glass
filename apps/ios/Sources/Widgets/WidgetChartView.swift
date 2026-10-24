import Charts
import SwiftUI

/// Graphique natif (barres, lignes, secteurs) sur surface opaque. Aucun Liquid Glass ici.
struct WidgetChartView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let spec: WidgetChartSpec
    var height: CGFloat = 240

    @State private var appeared = false

    private var chartHeight: CGFloat {
        // Dynamic Type : on laisse plus de place aux légendes et aux axes.
        typeSize.isAccessibilitySize ? height * 1.4 : height
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
            Chart {
                ForEach(Array(spec.series.enumerated()), id: \.offset) { _, series in
                    ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                        BarMark(x: .value(spec.xLabel ?? "X", point.x),
                                y: .value(spec.yLabel ?? "Y", point.y))
                            .foregroundStyle(by: .value("Series", series.name))
                            .position(by: .value("Series", series.name))
                            .accessibilityLabel(point.x)
                            .accessibilityValue("\(series.name): \(point.y.formatted())")
                    }
                }
            }
            .modifier(AxisLabels(x: spec.xLabel, y: spec.yLabel, legend: spec.series.count > 1))
        case .line:
            Chart {
                ForEach(Array(spec.series.enumerated()), id: \.offset) { _, series in
                    ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value(spec.xLabel ?? "X", point.x),
                                 y: .value(spec.yLabel ?? "Y", point.y))
                            .foregroundStyle(by: .value("Series", series.name))
                            .interpolationMethod(.monotone)
                            .accessibilityLabel(point.x)
                            .accessibilityValue("\(series.name): \(point.y.formatted())")
                        PointMark(x: .value(spec.xLabel ?? "X", point.x),
                                  y: .value(spec.yLabel ?? "Y", point.y))
                            .foregroundStyle(by: .value("Series", series.name))
                            .accessibilityHidden(true)
                    }
                }
            }
            .modifier(AxisLabels(x: spec.xLabel, y: spec.yLabel, legend: spec.series.count > 1))
        case .pie:
            // Un secteur par point de la première série non vide.
            let points = spec.series.first { !$0.points.isEmpty }?.points.filter { $0.y > 0 } ?? []
            Chart(Array(points.enumerated()), id: \.offset) { _, point in
                SectorMark(angle: .value("Value", point.y),
                           innerRadius: .ratio(0.5),
                           angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(by: .value("Category", point.x))
                    .accessibilityLabel(point.x)
                    .accessibilityValue(point.y.formatted())
            }
            .chartLegend(position: .bottom, alignment: .center)
        }
    }
}

private struct AxisLabels: ViewModifier {
    let x: String?
    let y: String?
    let legend: Bool

    func body(content: Content) -> some View {
        content
            .chartXAxisLabel(x ?? "", alignment: .center)
            .chartYAxisLabel(y ?? "", alignment: .center)
            .chartLegend(legend ? .visible : .hidden)
    }
}
