import Charts
import SwiftUI

// Compact Liquid Glass card for a chart widget: title, latest value, change since the previous
// point and a sparkline. Tapping opens the full screen widget (the caller decides how).
// The glass surface is chrome; the sparkline is a flat mark on top of it.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Summary

/// Values derived once from a `WidgetChartSpec` so the view body has nothing to infer.
struct WidgetGlassSummary: Equatable {
    struct Sample: Identifiable, Equatable {
        let id: Int
        let value: Double
    }

    let title: String
    let latest: Double
    /// Relative change versus the previous point. nil when there is no usable previous point.
    let delta: Double?
    let samples: [Sample]

    init?(spec: WidgetChartSpec) {
        let first = spec.series.first(where: { series in !series.points.isEmpty })
        guard let series = first else { return nil }
        let values: [Double] = series.points.map { point in point.y }
        guard let last = values.last else { return nil }
        var built: [Sample] = []
        for (index, value) in values.enumerated() {
            built.append(Sample(id: index, value: value))
        }
        var change: Double?
        if values.count > 1 {
            let previous: Double = values[values.count - 2]
            if previous != 0 {
                change = (last - previous) / abs(previous)
            }
        }
        let name: String = spec.title ?? series.name
        self.title = name
        self.latest = last
        self.delta = change
        self.samples = built
    }
}

// MARK: - Card

struct WidgetCompactGlassCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let summary: WidgetGlassSummary
    let onOpen: () -> Void

    private let radius: CGFloat = 22
    private let sparkHeight: CGFloat = 44

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: self.radius, style: .continuous)
    }

    private var deltaTint: Color {
        guard let delta = self.summary.delta else { return OpenClawBrand.textSecondary }
        return delta >= 0 ? OpenClawBrand.ok : OpenClawBrand.danger
    }

    private var deltaSymbol: String {
        guard let delta = self.summary.delta else { return "minus" }
        return delta >= 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private var deltaText: String {
        guard let delta = self.summary.delta else { return "-" }
        return delta.formatted(.percent.precision(.fractionLength(0)))
    }

    private var accessibilityText: String {
        let value: String = self.summary.latest.formatted()
        return self.summary.title + ", " + value + ", " + self.deltaText
    }

    var body: some View {
        Button(action: self.onOpen) {
            self.card
        }
        .buttonStyle(.openClawPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.accessibilityText))
        .accessibilityHint(Text("Opens full screen"))
        .accessibilityAddTraits(.isButton)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.header
            self.value
            self.sparkline
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(self.shape)
        .openClawGlass(in: self.shape, interactive: true)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(verbatim: self.summary.title)
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            NGPill(text: self.deltaText, systemImage: self.deltaSymbol, tint: self.deltaTint)
        }
    }

    private var value: some View {
        Text(self.summary.latest, format: .number.notation(.compactName))
            .font(OpenClawType.title2SemiBold)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
            .openClawAnimation(value: self.summary.latest)
    }

    private var sparkline: some View {
        let samples: [WidgetGlassSummary.Sample] = self.summary.samples
        let tint: Color = self.deltaTint
        let lastID: Int = samples.last?.id ?? -1
        return Chart(samples) { (sample: WidgetGlassSummary.Sample) in
            AreaMark(
                x: .value("Index", sample.id),
                y: .value("Value", sample.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint.opacity(0.18))
            LineMark(
                x: .value("Index", sample.id),
                y: .value("Value", sample.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
            if sample.id == lastID {
                PointMark(
                    x: .value("Index", sample.id),
                    y: .value("Value", sample.value))
                    .symbolSize(36)
                    .foregroundStyle(tint)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: self.sparkHeight)
        .openClawChartReveal()
        .accessibilityHidden(true)
    }
}
