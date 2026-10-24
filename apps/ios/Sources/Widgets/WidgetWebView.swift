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
        coordinator.cancelTimeout()
        web.stopLoading()
        web.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WidgetWebView
        var loadedPayload: WidgetPayload?
        private var terminatedOnce = false
        private var timeoutTask: Task<Void, Never>?
        private static let loadTimeoutSeconds = 15

        init(_ parent: WidgetWebView) { self.parent = parent }

        func cancelTimeout() {
            timeoutTask?.cancel()
            timeoutTask = nil
        }

        /// Écrit l'état au tour suivant : `load` peut être appelé pendant `makeUIView`,
        /// où modifier un `@Binding` déclenche l'avertissement « Modifying state during view update ».
        private func deferState(_ next: WidgetLoadState) {
            Task { @MainActor [weak self] in
                guard let self, self.parent.state != next else { return }
                self.parent.state = next
            }
        }

        /// Falls back to the error state (with Retry) if the page never finishes loading.
        private func armTimeout() {
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.loadTimeoutSeconds))
                guard let self, !Task.isCancelled, self.parent.state == .loading else { return }
                self.parent.state = .failed(String(localized: "The widget took too long to load."))
            }
        }

        /// Reads the real content height (works even when page JavaScript is disabled: this is a native call).
        private func measure(_ web: WKWebView) {
            let script = "Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)"
            web.evaluateJavaScript(script) { [weak self] value, _ in
                let height: Double? = (value as? NSNumber)?.doubleValue
                Task { @MainActor in
                    guard let self, let height, height.isFinite, height > 0 else { return }
                    let next = CGFloat(height)
                    if abs(next - self.parent.contentHeight) > 1 { self.parent.contentHeight = next }
                }
            }
        }

        /// Late images and fonts change the height: measure again shortly after load.
        private func remeasureLater(_ web: WKWebView) {
            Task { @MainActor [weak self, weak web] in
                for delay in [300, 1000] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard let self, let web else { return }
                    self.measure(web)
                }
            }
        }

        func load(into web: WKWebView) {
            loadedPayload = parent.payload
            guard let html = WidgetDocument.html(
                for: parent.payload, network: parent.network, zoomable: parent.zoomable)
            else {
                deferState(.failed(String(localized: "This content cannot be displayed.")))
                return
            }
            deferState(.loading)
            armTimeout()
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
            timeoutTask?.cancel()
            parent.state = .loaded
            measure(web)
            remeasureLater(web)
        }

        func webView(_: WKWebView, didFail _: WKNavigation?, withError error: any Error) {
            timeoutTask?.cancel()
            parent.state = .failed(error.localizedDescription)
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation?, withError error: any Error) {
            timeoutTask?.cancel()
            parent.state = .failed(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ web: WKWebView) {
            if terminatedOnce {
                timeoutTask?.cancel()
                parent.state = .failed(String(localized: "The widget stopped unexpectedly."))
            } else {
                terminatedOnce = true
                load(into: web)
            }
        }
    }
}
