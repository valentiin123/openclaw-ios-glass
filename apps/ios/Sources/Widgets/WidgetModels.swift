import Foundation

/// Contenu d'un widget généré par l'assistant, indépendant du transport.
public enum WidgetPayload: Hashable, Sendable {
    case html(String, allowsScripts: Bool)
    case svg(String)
    case chart(WidgetChartSpec)

    public var kindLabel: String {
        switch self {
        case .html: String(localized: "Widget")
        case .svg: String(localized: "Illustration")
        case let .chart(spec): spec.kind.localizedName
        }
    }
}

public struct WidgetChartSpec: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case bar, line, pie

        var localizedName: String {
            switch self {
            case .bar: String(localized: "Bar chart")
            case .line: String(localized: "Line chart")
            case .pie: String(localized: "Pie chart")
            }
        }
    }

    public struct Point: Codable, Hashable, Sendable {
        public let x: String
        public let y: Double
        public init(x: String, y: Double) { self.x = x; self.y = y }
    }

    public struct Series: Codable, Hashable, Sendable {
        public let name: String
        public let points: [Point]
        public init(name: String, points: [Point]) { self.name = name; self.points = points }
    }

    public let kind: Kind
    public let title: String?
    public let xLabel: String?
    public let yLabel: String?
    public let series: [Series]

    public init(kind: Kind, title: String? = nil, xLabel: String? = nil, yLabel: String? = nil, series: [Series]) {
        self.kind = kind
        self.title = title
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.series = series
    }

    /// Plafonds défensifs : une donnée géante ne doit pas figer l'UI.
    public static let maxSeries = 8
    public static let maxPointsPerSeries = 500

    public var isRenderable: Bool {
        !self.series.isEmpty && self.series.contains { !$0.points.isEmpty } &&
            self.series.allSatisfy { $0.points.allSatisfy { $0.y.isFinite } }
    }

    /// Version bornée et assainie, sûre à passer à Swift Charts.
    public var sanitized: WidgetChartSpec {
        let limited = self.series.prefix(Self.maxSeries).map { series in
            Series(
                name: series.name,
                points: series.points.prefix(Self.maxPointsPerSeries).filter { $0.y.isFinite })
        }
        return WidgetChartSpec(
            kind: self.kind, title: self.title, xLabel: self.xLabel, yLabel: self.yLabel, series: limited)
    }

    /// Résumé lu par VoiceOver ; les marques gardent leurs propres labels.
    public var accessibilitySummary: String {
        let sanitized = self.sanitized
        let count = sanitized.series.reduce(0) { $0 + $1.points.count }
        let head = [sanitized.title, sanitized.kind.localizedName].compactMap(\.self).joined(separator: ", ")
        return String(
            format: String(localized: "%@, %lld series, %lld data points"),
            head, Int64(sanitized.series.count), Int64(count))
    }

    public static func decode(json: String) -> WidgetChartSpec? {
        guard let data = json.data(using: .utf8),
              let spec = try? JSONDecoder().decode(WidgetChartSpec.self, from: data),
              spec.isRenderable
        else { return nil }
        return spec.sanitized
    }
}

public enum WidgetPayloadDetector {
    /// Interprète un bloc de code du chat. `language` vient de la fence (```chart, ```svg, ```html).
    public static func payload(language: String?, body: String, allowsScripts: Bool = false) -> WidgetPayload? {
        let lang = language?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 512 * 1024 else { return nil }
        switch lang {
        case "chart", "openclaw-chart":
            return WidgetChartSpec.decode(json: trimmed).map(WidgetPayload.chart)
        case "svg":
            return trimmed.lowercased().contains("<svg") ? .svg(trimmed) : nil
        case "html", "widget":
            return .html(trimmed, allowsScripts: allowsScripts)
        default:
            return nil
        }
    }
}
