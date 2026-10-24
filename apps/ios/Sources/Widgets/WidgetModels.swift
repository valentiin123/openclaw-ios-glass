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
        case bar, line, area, pie, sparkline

        var localizedName: String {
            switch self {
            case .bar: String(localized: "Bar chart")
            case .line: String(localized: "Line chart")
            case .area: String(localized: "Area chart")
            case .pie: String(localized: "Pie chart")
            case .sparkline: String(localized: "Sparkline")
            }
        }

        /// Accepte les synonymes courants produits par les modèles ("column", "donut", ...).
        static func parse(_ raw: String) -> Kind? {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "bar", "bars", "column", "columns", "histogram": Kind.bar
            case "line", "lines": Kind.line
            case "area", "areas": Kind.area
            case "pie", "donut", "doughnut": Kind.pie
            case "sparkline", "spark": Kind.sparkline
            default: nil
            }
        }

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let kind = Kind.parse(raw) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unknown chart kind: \(raw)"))
            }
            self = kind
        }
    }

    public struct Point: Codable, Hashable, Sendable {
        public let x: String
        public let y: Double

        public init(x: String, y: Double) {
            self.x = x
            self.y = y
        }

        private enum CodingKeys: String, CodingKey { case x, y }

        /// `x` peut être un texte ou un nombre ; `y` un nombre ou un texte numérique.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let text = try? container.decode(String.self, forKey: .x) {
                self.x = text
            } else if let number = try? container.decode(Double.self, forKey: .x) {
                self.x = Self.label(number)
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.x,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing x"))
            }
            if let number = try? container.decode(Double.self, forKey: .y) {
                self.y = number
            } else if let text = try? container.decode(String.self, forKey: .y), let number = Double(text) {
                self.y = number
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .y, in: container, debugDescription: "y must be a number")
            }
        }

        fileprivate static func label(_ number: Double) -> String {
            if number.isFinite, number == number.rounded(), abs(number) < 1e15 {
                return String(Int64(number))
            }
            return String(number)
        }
    }

    public struct Series: Codable, Hashable, Sendable {
        public let name: String
        public let points: [Point]

        public init(name: String, points: [Point]) {
            self.name = name
            self.points = points
        }

        private enum CodingKeys: String, CodingKey { case name, points }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            self.points = try container.decode([Point].self, forKey: .points)
        }
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

    private enum DecodingKeys: String, CodingKey {
        case kind, type, title, xLabel, yLabel, series, data, points, labels, values
    }

    /// Décodage tolérant : `kind` ou `type`, `series` ou `points`/`data`, ou `labels` + `values`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DecodingKeys.self)
        var parsedKind = try container.decodeIfPresent(Kind.self, forKey: .kind)
        if parsedKind == nil { parsedKind = try container.decodeIfPresent(Kind.self, forKey: .type) }
        self.kind = parsedKind ?? .bar
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.xLabel = try container.decodeIfPresent(String.self, forKey: .xLabel)
        self.yLabel = try container.decodeIfPresent(String.self, forKey: .yLabel)

        var parsedSeries: [Series] = try container.decodeIfPresent([Series].self, forKey: .series) ?? []
        if parsedSeries.isEmpty {
            var flat: [Point] = try container.decodeIfPresent([Point].self, forKey: .points) ?? []
            if flat.isEmpty { flat = try container.decodeIfPresent([Point].self, forKey: .data) ?? [] }
            if flat.isEmpty,
               let labels = try container.decodeIfPresent([String].self, forKey: .labels),
               let values = try container.decodeIfPresent([Double].self, forKey: .values)
            {
                flat = zip(labels, values).map { Point(x: $0, y: $1) }
            }
            if !flat.isEmpty { parsedSeries = [Series(name: "", points: flat)] }
        }
        self.series = parsedSeries
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
