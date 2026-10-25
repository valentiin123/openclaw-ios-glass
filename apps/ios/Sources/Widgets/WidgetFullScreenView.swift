import SwiftUI
import UIKit

/// Plein écran : contenu sur surface opaque, zoom pincé (graphiques) ou zoom WebKit (HTML/SVG).
/// Liquid Glass uniquement sur les contrôles (fermer, partager).
struct WidgetFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let payload: WidgetPayload
    let title: String?
    let network: WidgetNetworkPolicy

    @State private var state: WidgetLoadState = .loading
    @State private var contentHeight: CGFloat = 0
    @StateObject private var controller = WidgetWebController()
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var shareItem: WidgetShareItem?
    @State private var exportFailed = false
    @State private var reloadToken = UUID()
    @State private var dragOffset: CGFloat = 0

    /// Glisser vers le bas pour fermer. Seuil par distance ou par vitesse ; retour au repos sinon.
    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 300 {
                    dismiss()
                } else {
                    OpenClawMotion.perform(reduceMotion: reduceMotion) { dragOffset = 0 }
                }
            }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(1 - min(dragOffset / 600, 0.5))
                .ignoresSafeArea()
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    controls
                }
                .offset(y: dragOffset)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: scale)
        .sensoryFeedback(.error, trigger: exportFailed) { _, new in new }
        .sheet(item: $shareItem) { WidgetShareSheet(image: $0.image) }
        .alert(String(localized: "Could not export"), isPresented: $exportFailed) {
            Button { exportFailed = false } label: { Text(String(localized: "OK")).font(OpenClawType.body) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch payload {
        case let .chart(spec):
            GeometryReader { proxy in
                // Le zoom redimensionne réellement le graphique (rendu net, étendue de défilement correcte)
                // au lieu d'étirer un rendu de taille fixe avec scaleEffect.
                let zoom: CGFloat = min(max(scale * pinch, 1), 5)
                ScrollView([.horizontal, .vertical]) {
                    WidgetChartView(spec: spec, height: 360 * zoom)
                        .padding(16)
                        .frame(width: proxy.size.width * zoom, alignment: .topLeading)
                }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = min(max(scale * value.magnification, 1), 5) })
            .simultaneousGesture(dragToDismiss, including: scale > 1 ? .subviews : .all)
            .onTapGesture(count: 2) {
                OpenClawMotion.perform(reduceMotion: reduceMotion) { scale = scale > 1 ? 1 : 2 }
            }
            .accessibilityElement(children: .contain)
        default:
            ZStack {
                WidgetWebView(
                    payload: payload, network: network, zoomable: true,
                    state: $state, contentHeight: $contentHeight, controller: controller)
                    .id(reloadToken)
                if state == .loading { ProgressView().accessibilityLabel(String(localized: "Loading widget")) }
                if case let .failed(message) = state {
                    failureView(message)
                }
            }
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(OpenClawType.body).multilineTextAlignment(.center)
            Button {
                state = .loading
                reloadToken = UUID()
            } label: {
                Text(String(localized: "Retry")).font(OpenClawType.body)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.glass)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        GlassEffectContainer {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(String(localized: "Close"))
                // Poignée : zone de glisser pour fermer, utilisable aussi pour HTML/SVG (le scroll web garde ses gestes).
                Capsule()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .gesture(dragToDismiss)
                    .accessibilityHidden(true)
                Button {
                    Task {
                        if let image = await WidgetExport.image(for: payload, controller: controller) {
                            shareItem = WidgetShareItem(image: image)
                        } else { exportFailed = true }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(String(localized: "Share"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
