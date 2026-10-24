import SwiftUI
import UIKit
import WebKit

public enum WidgetLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}

/// Pont entre la vue SwiftUI et la WKWebView (capture d'image pour copie/partage).
@MainActor
public final class WidgetWebController: ObservableObject {
    fileprivate weak var webView: WKWebView?

    public init() {}

    public func snapshot() async -> UIImage? {
        guard let webView else { return nil }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.scrollView.contentSize)
        return await withCheckedContinuation { cont in
            webView.takeSnapshot(with: config) { image, _ in cont.resume(returning: image) }
        }
    }
}

/// WKWebView sandboxée : stockage non persistant, JS selon `allowsScripts`, CSP injectée,
/// aucune navigation sortante (liens annulés), pas de fenêtres, pas de réseau hors hôtes autorisés.
struct WidgetWebView: UIViewRepresentable {
    let payload: WidgetPayload
    let network: WidgetNetworkPolicy
    let zoomable: Bool
    @Binding var state: WidgetLoadState
    @Binding var contentHeight: CGFloat
    let controller: WidgetWebController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        var scripts = false
        if case let .html(_, allows) = payload { scripts = allows }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = scripts
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsInlineMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.dataDetectorTypes = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsLinkPreview = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = zoomable
        web.scrollView.bounces = zoomable
        controller.webView = web
        context.coordinator.load(into: web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedPayload != payload {
            context.coordinator.load(into: web)
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
        web.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WidgetWebView
        var loadedPayload: WidgetPayload?
        private var terminatedOnce = false

        init(_ parent: WidgetWebView) { self.parent = parent }

        func load(into web: WKWebView) {
            loadedPayload = parent.payload
            guard let html = WidgetDocument.html(
                for: parent.payload, network: parent.network, zoomable: parent.zoomable)
            else {
                parent.state = .failed(String(localized: "This content cannot be displayed."))
                return
            }
            parent.state = .loading
            // baseURL nil : origine opaque, aucun accès aux ressources locales.
            web.loadHTMLString(html, baseURL: nil)
        }

        func webView(
            _: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void)
        {
            // Seul le chargement initial du document est permis ; liens, formulaires et redirections sont annulés.
            let isInitialLoad = action.navigationType == .other
                && (action.request.url == nil || action.request.url?.scheme == "about")
            decisionHandler(isInitialLoad ? .allow : .cancel)
        }

        func webView(_ web: WKWebView, didFinish _: WKNavigation?) {
            web.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] value, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let h = value as? Double { self.parent.contentHeight = CGFloat(h) }
                    self.parent.state = .loaded
                }
            }
        }

        func webView(_: WKWebView, didFail _: WKNavigation?, withError error: any Error) {
            parent.state = .failed(error.localizedDescription)
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation?, withError error: any Error) {
            parent.state = .failed(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ web: WKWebView) {
            if terminatedOnce {
                parent.state = .failed(String(localized: "The widget stopped unexpectedly."))
            } else {
                terminatedOnce = true
                load(into: web)
            }
        }
    }
}
