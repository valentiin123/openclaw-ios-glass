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

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            content
                .padding(.top, 64)
            controls
        }
        .sheet(item: $shareItem) { WidgetShareSheet(image: $0.image) }
        .alert(String(localized: "Could not export"), isPresented: $exportFailed) {
            Button { exportFailed = false } label: { Text(String(localized: "OK")).font(OpenClawType.body) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch payload {
        case let .chart(spec):
            ScrollView([.horizontal, .vertical]) {
                WidgetChartView(spec: spec, height: 360)
                    .padding(16)
                    .frame(minWidth: UIScreen.main.bounds.width)
                    .scaleEffect(min(max(scale * pinch, 1), 5), anchor: .topLeading)
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = min(max(scale * value.magnification, 1), 5) })
            .onTapGesture(count: 2) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scale = scale > 1 ? 1 : 2 }
            }
            .accessibilityElement(children: .contain)
        default:
            ZStack {
                WidgetWebView(
                    payload: payload, network: network, zoomable: true,
                    state: $state, contentHeight: $contentHeight, controller: controller)
                if state == .loading { ProgressView().accessibilityLabel(String(localized: "Loading widget")) }
                if case let .failed(message) = state {
                    Text(message).font(OpenClawType.body).padding()
                }
            }
        }
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
                Spacer()
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
            .padding(.top, 8)
        }
    }
}
