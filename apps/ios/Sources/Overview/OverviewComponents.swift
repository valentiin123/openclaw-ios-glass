import OpenClawChatUI
import SwiftUI

// Presentational pieces of the Overview. They take plain values (no app model access) so the
// owning view keeps all state. Same family as the Agents board tiles: opaque rectangles with a
// hairline border, discreet pixel art, playful state wording. No glass here.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Run state

/// Maps a session onto the playful tile states of the Agents board (labels, tints, sleep).
enum OverviewRunState {
    static func state(for session: OpenClawChatSessionEntry?) -> AgentTileState {
        guard let session = session else { return .napping }
        let status: AgentsHubRunStatus = AgentsHubRunStatus(session)
        switch status {
        case .running: return .working
        case .waitingOnChildren: return .delegating
        case .failed: return .failed
        case .done: return .done
        case .idle: return .napping
        }
    }
}

// MARK: - Header

/// Page title: discreet pixel robot, title, monospaced gateway line, then the header buttons.
/// Opaque surfaces only; Liquid Glass stays on the tab bar.
struct OverviewHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: String
    private let trailing: Trailing

    @ScaledMetric(relativeTo: .title2) private var spriteSize: CGFloat = 30

    init(
        title: LocalizedStringKey,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing)
    {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: OpenClawSpace.md) {
            self.mark
            self.texts
                .layoutPriority(1)
            Spacer(minLength: OpenClawSpace.sm)
            self.trailing
        }
        .frame(maxWidth: .infinity, minHeight: OverviewMetric.minTarget, alignment: .leading)
    }

    private var mark: some View {
        AgentTileSpriteView(kind: .robot)
            .frame(width: self.spriteSize, height: self.spriteSize)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.xxs) {
            Text(self.title)
                .font(OpenClawType.title2SemiBold)
                .foregroundStyle(OpenClawPalette.texteFort)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
            Text(verbatim: self.subtitle)
                .font(OpenClawType.monoSmall)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Square header button: opaque card, hairline border, accent glyph. The visible square is
/// `headerButtonSize`, the hit target is 44 pt.
struct OverviewHeaderButton: View {
    let systemName: String
    let label: Text
    var hint: Text?
    var identifier: String = ""
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: self.action) {
            self.target
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
        .accessibilityLabel(self.label)
        .accessibilityHint(self.hint ?? Text(verbatim: ""))
        .accessibilityIdentifier(self.identifier)
    }

    private var target: some View {
        self.face
            .frame(width: OverviewMetric.minTarget, height: OverviewMetric.minTarget)
            .contentShape(Rectangle())
    }

    private var face: some View {
        Image(systemName: self.systemName)
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(OpenClawBrand.accent)
            .frame(width: OverviewMetric.headerButtonSize, height: OverviewMetric.headerButtonSize)
            .overviewTile()
    }
}

// MARK: - Summary strip

/// One tile with the four headline figures, separated by hairlines. The whole tile opens Sessions.
/// Wide text sizes fold the strip into a 2 x 2 table.
struct OverviewStatStrip: View {
    let stats: [OverviewStat]
    let hint: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int {
        self.dynamicTypeSize.isAccessibilitySize ? 2 : 4
    }

    private var rows: [[OverviewStat]] {
        let size: Int = self.columnCount
        var result: [[OverviewStat]] = []
        var start: Int = 0
        while start < self.stats.count {
            let end: Int = min(start + size, self.stats.count)
            let slice: [OverviewStat] = Array(self.stats[start..<end])
            result.append(slice)
            start = end
        }
        return result
    }

    private var spokenSummary: String {
        let parts: [String] = self.stats.map { stat in
            "\(stat.title) \(stat.value)"
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: self.action) {
            self.table
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.spokenSummary))
        .accessibilityHint(Text(verbatim: self.hint))
        .accessibilityAddTraits(.isButton)
    }

    private var table: some View {
        let allRows: [[OverviewStat]] = self.rows
        return VStack(spacing: 0) {
            ForEach(0..<allRows.count, id: \.self) { (rowIndex: Int) in
                self.rowView(allRows[rowIndex], showsRule: rowIndex > 0)
            }
        }
        .frame(maxWidth: .infinity)
        .overviewTile()
    }

    private func rowView(_ row: [OverviewStat], showsRule: Bool) -> some View {
        VStack(spacing: 0) {
            if showsRule {
                self.horizontalRule
            }
            self.cells(row)
        }
    }

    private func cells(_ row: [OverviewStat]) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<row.count, id: \.self) { (index: Int) in
                self.cellWithRule(row[index], showsRule: index > 0)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cellWithRule(_ stat: OverviewStat, showsRule: Bool) -> some View {
        HStack(spacing: 0) {
            if showsRule {
                self.verticalRule
            }
            self.cell(stat)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var horizontalRule: some View {
        Rectangle()
            .fill(OpenClawBrand.hairlineBorderStrong)
            .frame(height: OpenClawProMetric.borderWidth)
    }

    private var verticalRule: some View {
        Rectangle()
            .fill(OpenClawBrand.hairlineBorderStrong)
            .frame(width: OpenClawProMetric.borderWidth)
    }

    private func cell(_ stat: OverviewStat) -> some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
            self.cellTitle(stat)
            Text(verbatim: stat.value)
                .font(OpenClawType.title3SemiBold)
                .foregroundStyle(OpenClawPalette.texteFort)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, OpenClawSpace.md)
        .padding(.vertical, OpenClawSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cellTitle(_ stat: OverviewStat) -> some View {
        HStack(spacing: OpenClawSpace.xs) {
            Rectangle()
                .fill(stat.marker)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(verbatim: stat.title)
                .font(OpenClawType.caption2Medium)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Gateway

/// Read-only status tile. The Settings entry stays on the header gear button.
struct OverviewGatewayTile: View {
    let statusTitle: String
    let statusColor: Color
    let address: String
    let agents: String

    private var spokenSummary: String {
        let gateway: String = String(format: String(localized: "Gateway %@"), self.statusTitle)
        return "\(gateway), \(self.address), \(String(localized: "Agents")) \(self.agents)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: OpenClawSpace.md) {
            Rectangle()
                .fill(self.statusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            self.texts
            Spacer(minLength: OpenClawSpace.sm)
            self.agentsColumn
        }
        .padding(OpenClawSpace.md)
        .frame(maxWidth: .infinity, minHeight: OverviewMetric.minTarget, alignment: .leading)
        .overviewTile()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.spokenSummary))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.xxs) {
            Text(verbatim: self.statusTitle)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(self.statusColor)
                .lineLimit(1)
            Text(verbatim: self.address)
                .font(OpenClawType.monoSmall)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var agentsColumn: some View {
        VStack(alignment: .trailing, spacing: OpenClawSpace.xxs) {
            Text(verbatim: self.agents)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(OpenClawPalette.texteFort)
                .lineLimit(1)
            Text("Agents")
                .font(OpenClawType.caption2Medium)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .lineLimit(1)
        }
    }
}

// MARK: - Attention

struct OverviewAttentionItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
    let action: () -> Void
}

/// Pending approvals and automation issues. Only shown when something needs the person.
struct OverviewAttentionTile: View {
    let items: [OverviewAttentionItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            ForEach(self.items) { (item: OverviewAttentionItem) in
                self.row(item)
            }
        }
        .padding(.bottom, OpenClawSpace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overviewTile(tint: OpenClawBrand.warn)
    }

    private var header: some View {
        HStack(spacing: OpenClawSpace.sm) {
            AgentTileBubbleView(kind: .alert)
                .frame(width: 16)
            Text("Attention")
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawBrand.warn)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OpenClawSpace.md)
        .padding(.top, OpenClawSpace.md)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: OverviewAttentionItem) -> some View {
        Button(action: item.action) {
            self.rowLabel(item)
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.title), \(item.value)"))
        .accessibilityAddTraits(.isButton)
    }

    private func rowLabel(_ item: OverviewAttentionItem) -> some View {
        HStack(spacing: OpenClawSpace.md) {
            Image(systemName: item.systemImage)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(OpenClawBrand.warn)
                .accessibilityHidden(true)
            Text(verbatim: item.title)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(OpenClawPalette.texteFort)
                .multilineTextAlignment(.leading)
            Spacer(minLength: OpenClawSpace.sm)
            Text(verbatim: item.value)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(OpenClawBrand.warn)
            Image(systemName: "chevron.right")
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, OpenClawSpace.md)
        .frame(minHeight: OverviewMetric.minTarget)
        .contentShape(Rectangle())
    }
}

// MARK: - Usage

/// 31-day cost with a full-width square-bar trend (last day highlighted). The tile opens Usage.
struct OverviewUsageTile: View {
    let title: String
    let cost: String
    let values: [Double]
    let hint: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barMaxHeight: CGFloat = 36
    private let barMinHeight: CGFloat = 3
    private let barSpacing: CGFloat = 3

    private var maximum: Double {
        self.values.max() ?? 0
    }

    var body: some View {
        Button(action: self.action) {
            self.content
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(self.title), \(self.cost)"))
        .accessibilityHint(Text(verbatim: self.hint))
        .accessibilityAddTraits(.isButton)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.md) {
            self.topRow
            self.bars
        }
        .padding(OpenClawSpace.md)
        .frame(maxWidth: .infinity, minHeight: OverviewMetric.minTarget, alignment: .leading)
        .overviewTile()
    }

    private var topRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: OpenClawSpace.sm) {
            VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
                Text(verbatim: self.title)
                    .font(OpenClawType.caption2Medium)
                    .foregroundStyle(OpenClawPalette.texteAtténué)
                    .lineLimit(1)
                Text(verbatim: self.cost)
                    .font(OpenClawType.title2SemiBold)
                    .foregroundStyle(OpenClawPalette.texteFort)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: OpenClawSpace.sm)
            Image(systemName: "chevron.right")
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawPalette.texteAtténué)
                .accessibilityHidden(true)
        }
    }

    private var bars: some View {
        let count: Int = self.values.count
        return HStack(alignment: .bottom, spacing: self.barSpacing) {
            ForEach(0..<count, id: \.self) { (index: Int) in
                self.bar(self.values[index], isLast: index == count - 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: self.barMaxHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func bar(_ value: Double, isLast: Bool) -> some View {
        let opacity: Double = isLast ? 1 : 0.45
        return Rectangle()
            .fill(OpenClawBrand.accent.opacity(opacity))
            .frame(height: self.barHeight(value))
            .frame(maxWidth: .infinity)
    }

    private func barHeight(_ value: Double) -> CGFloat {
        guard self.maximum > 0 else { return self.barMinHeight }
        let ratio: Double = value / self.maximum
        let height: CGFloat = CGFloat(ratio) * self.barMaxHeight
        return max(self.barMinHeight, height)
    }
}

// MARK: - Empty state

/// Sleeping pixel ghost with a short message. Replaces the icon-badge empty rows on the Overview.
struct OverviewEmptyTile: View {
    let title: String
    let detail: String

    @ScaledMetric(relativeTo: .body) private var spriteSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .center, spacing: OpenClawSpace.md) {
            AgentTileSpriteView(kind: .ghost)
                .frame(width: self.spriteSize, height: self.spriteSize)
                .saturation(0)
                .opacity(0.55)
            VStack(alignment: .leading, spacing: OpenClawSpace.xxs) {
                Text(verbatim: self.title)
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(OpenClawPalette.texteFort)
                Text(verbatim: self.detail)
                    .font(OpenClawType.caption)
                    .foregroundStyle(OpenClawPalette.texteAtténué)
            }
            Spacer(minLength: 0)
        }
        .padding(OpenClawSpace.md)
        .frame(maxWidth: .infinity, minHeight: OverviewMetric.minTarget, alignment: .leading)
        .overviewTile()
        .accessibilityElement(children: .combine)
    }
}
