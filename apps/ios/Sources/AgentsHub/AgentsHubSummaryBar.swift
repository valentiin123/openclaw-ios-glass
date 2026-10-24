import SwiftUI

/// Compteurs de l'arbre sur une seule ligne sobre. Ce sont des données (contenu), donc pas de Liquid Glass
/// ni d'animation décorative : la couleur porte le sens, le changement de valeur utilise le ressort partagé.
struct AgentsHubSummaryBar: View {
    let total: Int
    let active: Int
    let failed: Int
    let isLive: Bool

    var body: some View {
        HStack(spacing: OpenClawSpace.lg) {
            liveBadge
            countLabel(symbol: "person.2.fill", value: total, tint: nil)
            countLabel(symbol: "play.circle.fill", value: active, tint: activeTint)
            countLabel(symbol: "exclamationmark.triangle.fill", value: failed, tint: failedTint)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: spokenSummary))
    }

    private var activeTint: Color? {
        active > 0 ? Color.accentColor : nil
    }

    private var failedTint: Color? {
        failed > 0 ? Color.red : nil
    }

    @ViewBuilder
    private var liveBadge: some View {
        if isLive {
            AgentsHubLiveBadge()
        }
    }

    private func countLabel(symbol: String, value: Int, tint: Color?) -> some View {
        let color: Color = tint ?? Color.secondary
        return HStack(spacing: OpenClawSpace.xs) {
            Image(systemName: symbol)
                .font(OpenClawType.caption2SemiBold)
                .accessibilityHidden(true)
            Text(verbatim: String(value))
                .font(OpenClawType.captionSemiBold)
                .contentTransition(.numericText())
        }
        .foregroundStyle(color)
        .openClawAnimation(value: value)
    }

    private var spokenSummary: String {
        let base: String = "\(total) descendants, \(active) active, \(failed) failed"
        return isLive ? base + ", live" : base
    }
}
