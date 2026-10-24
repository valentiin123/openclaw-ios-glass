import SwiftUI
import UIKit

/// Point d'entrée public : affiche un widget ou graphique dans le chat.
/// Contenu sur surface opaque ; Liquid Glass uniquement sur les contrôles (menu d'actions).
public struct WidgetCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    public let payload: WidgetPayload
    public let title: String?
    public let network: WidgetNetworkPolicy

    @State private var state: WidgetLoadState = .loading
    @State private var contentHeight: CGFloat = 0
    @State private var showFullScreen = false
    @State private var shareItem: WidgetShareItem?
    @State private var errorMessage: String?
    @StateObject private var controller = WidgetWebController()
    @State private var reloadToken = UUID()
    @State private var showSource = false

    public init(payload: WidgetPayload, title: String? = nil, network: WidgetNetworkPolicy = .none) {
        self.payload = payload
        self.title = title
        self.network = network
    }

    private var isChart: Bool {
        if case .chart = payload { return true }
        return false
    }

    private var inlineHeight: CGFloat {
        let base = min(max(contentHeight, 160), 480)
        return typeSize.isAccessibilitySize ? min(base * 1.25, 600) : base
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ZStack {
                content
                overlayState
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { showFullScreen = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(String(localized: "Opens full screen"))
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            WidgetFullScreenView(payload: payload, title: title, network: network)
        }
        .sheet(item: $shareItem) { item in WidgetShareSheet(image: item.image) }
        .alert(String(localized: "Could not export"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }))
        {
            Button { errorMessage = nil } label: { Text(String(localized: "OK")).font(OpenClawType.body) }
        } message: {
            Text(errorMessage ?? "").font(OpenClawType.body)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(title ?? payload.kindLabel)
                .font(OpenClawType.subhead)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Menu {
                Button { Task { await export(copy: true) } } label: {
                    Label { Text(String(localized: "Copy image")).font(OpenClawType.body) }
                        icon: { Image(systemName: "doc.on.doc") }
                }
                Button { Task { await export(copy: false) } } label: {
                    Label { Text(String(localized: "Share")).font(OpenClawType.body) }
                        icon: { Image(systemName: "square.and.arrow.up") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "Widget actions"))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch payload {
        case let .chart(spec):
            chartContent(spec)
        default:
            WidgetWebView(
                payload: payload, network: network, zoomable: false,
                state: $state, contentHeight: $contentHeight, controller: controller)
                .id(reloadToken)
                .frame(height: inlineHeight)
                .opacity(state == .loaded ? 1 : 0)
                .animation(OpenClawMotion.animation(reduceMotion: reduceMotion), value: state)
                .accessibilityLabel(title ?? payload.kindLabel)
        }
    }

    private func chartContent(_ spec: WidgetChartSpec) -> some View {
        WidgetChartStateView(state: .ready(spec), height: spec.kind == .sparkline ? 56 : 240)
            .padding(12)
            .onAppear { state = .loaded }
    }

    @ViewBuilder
    private var overlayState: some View {
        switch state {
        case .loading where !isChart:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 96)
                .accessibilityLabel(String(localized: "Loading widget"))
        case let .failed(message):
            failureView(message)
        default:
            EmptyView()
        }
    }

    /// Texte brut du contenu, utilisé comme repli quand le rendu échoue.
    private var sourceText: String? {
        switch payload {
        case let .html(source, _): source
        case let .svg(source): source
        case .chart: nil
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(OpenClawType.subhead)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button {
                    showSource = false
                    state = .loading
                    reloadToken = UUID()
                } label: {
                    Text(String(localized: "Retry")).font(OpenClawType.body).frame(minHeight: 44)
                }
                .buttonStyle(.glass)
                if sourceText != nil {
                    Button {
                        OpenClawMotion.perform(reduceMotion: reduceMotion) { showSource.toggle() }
                    } label: {
                        Text(showSource ? String(localized: "Hide source") : String(localized: "Show source"))
                            .font(OpenClawType.body)
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            if showSource, let sourceText {
                ScrollView {
                    Text(verbatim: String(sourceText.prefix(8000)))
                        .font(OpenClawType.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .transition(OpenClawMotion.appear(reduceMotion: reduceMotion))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color(.secondarySystemBackground))
        .accessibilityElement(children: .contain)
    }

    private func export(copy: Bool) async {
        guard let image = await WidgetExport.image(for: payload, controller: controller) else {
            errorMessage = String(localized: "The widget image could not be captured.")
            return
        }
        if copy { UIPasteboard.general.image = image } else { shareItem = WidgetShareItem(image: image) }
    }
}

struct WidgetShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct WidgetShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

enum WidgetExport {
    @MainActor
    static func image(for payload: WidgetPayload, controller: WidgetWebController) async -> UIImage? {
        switch payload {
        case let .chart(spec):
            let view = WidgetChartView(spec: spec, height: 320)
                .padding(16)
                .frame(width: 640)
                .background(Color(.systemBackground))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            return renderer.uiImage
        default:
            return await controller.snapshot()
        }
    }
}
