import SwiftUI

/// État de chargement d'un graphique natif.
enum WidgetChartLoadState {
    case loading
    case failed(String)
    case ready(WidgetChartSpec)
}

/// Enveloppe d'un graphique : chargement (squelette), vide, erreur avec « Réessayer », ou graphique.
/// Le contenu reste sur surface opaque ; le verre n'est utilisé que pour le bouton.
struct WidgetChartStateView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: WidgetChartLoadState
    var height: CGFloat = 240
    var retry: (() -> Void)?

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .animation(OpenClawMotion.animation(reduceMotion: reduceMotion), value: stateKey)
    }

    /// Clé équatable pour animer les changements d'état sans exiger `Equatable` sur l'enum.
    private var stateKey: Int {
        switch state {
        case .loading: 0
        case .failed: 1
        case let .ready(spec): spec.isRenderable ? 2 : 3
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            loadingView
        case let .failed(message):
            failedView(message)
        case let .ready(spec):
            readyView(spec)
        }
    }

    private var loadingView: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(height: height)
            .openClawShimmer()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Loading chart"))
    }

    @ViewBuilder
    private func readyView(_ spec: WidgetChartSpec) -> some View {
        if spec.isRenderable {
            WidgetChartView(spec: spec, height: height)
                .transition(.opacity)
        } else {
            emptyView
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(OpenClawType.title2SemiBold)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No data to display")
                .font(OpenClawType.subhead)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(OpenClawSpace.lg)
        .frame(maxWidth: .infinity, minHeight: height)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(OpenClawType.subhead)
                .multilineTextAlignment(.center)
            retryButton
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: height)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var retryButton: some View {
        if let retry {
            Button(action: retry) {
                Text("Retry").font(OpenClawType.body)
            }
            .buttonStyle(.glass)
        }
    }
}
