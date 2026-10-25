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

// MARK: - Summary strip

/// One tile with the four headline figures. The whole tile opens Sessions.
struct OverviewStatStrip: View {
    let stats: [OverviewStat]
    let hint: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count: Int = self.dynamicTypeSize.isAccessibilitySize ? 2 : 4
        let item: GridItem = GridItem(.flexible(), spacing: 8, alignment: .topLeading)
        return Array(repeating: item, count: count)
    }

    private var spokenSummary: String {
        let parts: [String] = self.stats.map { stat in
            "\(stat.title) \(stat.value)"
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: self.action) {
            self.grid
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.spokenSummary))
        .accessibilityHint(Text(verbatim: self.hint))
        .accessibilityAddTraits(.isButton)
    }

    private var grid: some View {
        LazyVGrid(columns: self.columns, alignment: .leading, spacing: 12) {
            ForEach(self.stats) { stat in
                self.cell(stat)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overviewTile()
    }

    private func cell(_ stat: OverviewStat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: stat.value)
                .font(OpenClawType.headline)
                .foregroundStyle(OpenClawBrand.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: stat.title)
                .font(OpenClawType.caption2Medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Gateway

/// Read-only status tile. The Gateway settings entry stays on the glass header button.
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
        HStack(alignment: .center, spacing: 10) {
            Rectangle()
                .fill(self.statusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            self.texts
            Spacer(minLength: 8)
            self.agentsColumn
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: OverviewMetric.minTarget, alignment: .leading)
        .overviewTile()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.spokenSummary))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: self.statusTitle)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(self.statusColor)
                .lineLimit(1)
            Text(verbatim: self.address)
                .font(OpenClawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var agentsColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: self.agents)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("Agents")
                .font(OpenClawType.caption2Medium)
                .foregroundStyle(.secondary)
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
            ForEach(self.items) { item in
                self.row(item)
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overviewTile(tint: OpenClawBrand.warn)
    }

    private var header: some View {
        HStack(spacing: 6) {
            AgentTileBubbleView(kind: .alert)
                .frame(width: 16)
            Text("Attention")
                .font(OpenClawType.captionSemiBold)
                .foregroundStyle(OpenClawBrand.warn)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: OverviewAttentionItem) -> some View {
        Button(action: item.action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(OpenClawBrand.warn)
                    .accessibilityHidden(true)
                Text(verbatim: item.title)
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(verbatim: item.value)
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(OpenClawBrand.warn)
                Image(systemName: "chevron.right")
                    .font(OpenClawType.captionSemiBold)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: OverviewMetric.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(OverviewPressStyle(reduceMotion: self.reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.title), \(item.value)"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Usage

/// 31-day cost with a small square-bar trend. The tile opens Usage.
struct OverviewUsageTile: View {
    let title: String
    let cost: String
    let values: [Double]
    let hint: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barWidth: CGFloat = 4
    private let barMaxHeight: CGFloat = 28
    private let barMinHeight: CGFloat = 3

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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.title)
                    .font(OpenClawType.caption2Medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(verbatim: self.cost)
                    .font(OpenClawType.title3SemiBold)
                    .foregroundStyle(OpenClawBrand.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            self.bars
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: OverviewMetric.minTarget, alignment: .leading)
        .overviewTile()
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<self.values.count, id: \.self) { index in
                self.bar(self.values[index])
            }
        }
        .frame(height: self.barMaxHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func bar(_ value: Double) -> some View {
        Rectangle()
            .fill(OpenClawBrand.accent.opacity(0.75))
            .frame(width: self.barWidth, height: self.barHeight(value))
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
        HStack(alignment: .center, spacing: 12) {
            AgentTileSpriteView(kind: .ghost)
                .frame(width: self.spriteSize, height: self.spriteSize)
                .saturation(0)
                .opacity(0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.title)
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(.primary)
                Text(verbatim: self.detail)
                    .font(OpenClawType.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: OverviewMetric.minTarget, alignment: .leading)
        .overviewTile()
        .accessibilityElement(children: .combine)
    }
}
