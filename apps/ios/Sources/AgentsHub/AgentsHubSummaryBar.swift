import SwiftUI

/// Compteurs de l'arbre sur des capsules Liquid Glass (contrôles/chrome uniquement, jamais derrière du contenu lu).
/// Les capsules partagent un seul `GlassEffectContainer` : elles fusionnent et se déforment ensemble.
struct AgentsHubSummaryBar: View {
    let total: Int
    let active: Int
    let failed: Int
    let isLive: Bool

    var body: some View {
        GlassEffectContainer(spacing: OpenClawGlassMetric.containerSpacing) {
            row
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: spokenSummary))
    }

    private var row: some View {
        HStack(spacing: OpenClawSpace.sm) {
            liveCapsule
            countCapsule(symbol: "person.2.fill", value: total, tint: nil)
            countCapsule(symbol: "play.circle.fill", value: active, tint: activeTint)
            countCapsule(symbol: "exclamationmark.triangle.fill", value: failed, tint: failedTint)
        }
    }

    private var activeTint: Color? {
        active > 0 ? Color.accentColor : nil
    }

    private var failedTint: Color? {
        failed > 0 ? Color.red : nil
    }

    @ViewBuilder
    private var liveCapsule: some View {
        if isLive {
            AgentsHubLiveBadge()
                .openClawPulse()
                .padding(.horizontal, OpenClawGlassMetric.chipHorizontalPadding)
                .padding(.vertical, OpenClawGlassMetric.chipVerticalPadding)
                .openClawGlassCapsule(tint: Color.accentColor.opacity(OpenClawOpacity.selectedTint))
        }
    }

    private func countCapsule(symbol: String, value: Int, tint: Color?) -> some View {
        let shade: Color? = tint.map { color in color.opacity(OpenClawOpacity.selectedTint) }
        return HStack(spacing: OpenClawSpace.xs) {
            Image(systemName: symbol)
                .font(OpenClawType.caption2SemiBold)
                .accessibilityHidden(true)
            Text(verbatim: String(value))
                .font(OpenClawType.captionSemiBold)
                .contentTransition(.numericText())
        }
        .foregroundStyle(tint ?? Color.secondary)
        .padding(.horizontal, OpenClawGlassMetric.chipHorizontalPadding)
        .padding(.vertical, OpenClawGlassMetric.chipVerticalPadding)
        .openClawGlassCapsule(tint: shade)
        .openClawAnimation(value: value)
    }

    private var spokenSummary: String {
        let base: String = "\(total) descendants, \(active) active, \(failed) failed"
        return isLive ? base + ", live" : base
    }
}
