import OpenClawKit
import SwiftUI
import UIKit

// MARK: - Injected context

/// Everything the shell needs from its host (`RootTabs`). The host owns lifecycle,
/// sheets, onboarding and gateway-setup delivery; the shell only renders and routes.
struct AppShellContext {
    /// Shared roster/usage/cron model, refreshed by the host (see INTEGRATION.md).
    let sidebarModel: RootSidebarModel
    /// False while onboarding is on screen so embedded Settings cannot consume the one-shot link.
    let acceptsGatewaySetupRequests: Bool
    let gatewaySetupRequest: GatewaySetupRequest?
    let onGatewaySetupRequestHandled: (Int) -> Void
    let onSettingsRouteChange: (SettingsRoute?) -> Void
    let onApprovalNotificationsRoute: (String?) -> Void
}

// MARK: - Swipe-back for screens that hide the navigation bar

/// Several hosted screens draw their own header and hide the system navigation bar.
/// UIKit then disables the interactive pop gesture. This anchor re-enables it so the
/// edge swipe-back stays consistent across every pushed screen.
struct AppShellSwipeBackEnabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        AnchorView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class AnchorView: UIView {
        private let popDelegate = PopDelegate()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard self.window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder, !(current is UINavigationController) {
                responder = current.next
            }
            guard let navigation = responder as? UINavigationController else { return }
            self.popDelegate.navigation = navigation
            navigation.interactivePopGestureRecognizer?.delegate = self.popDelegate
            navigation.interactivePopGestureRecognizer?.isEnabled = true
        }
    }

    private final class PopDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var navigation: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let depth: Int = self.navigation?.viewControllers.count ?? 0
            return depth > 1
        }
    }
}

extension View {
    func appShellSwipeBack() -> some View {
        self.background(AppShellSwipeBackEnabler())
    }
}

// MARK: - Glass controls

/// Floating "Done" control for sheets. Glass is reserved for controls; the sheet content
/// behind it stays opaque. Bottom placement keeps it in thumb reach.
struct AppShellDoneButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Text("Done")
                .font(OpenClawType.subheadSemiBold)
                .padding(.horizontal, OpenClawSpace.xl)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .openClawGlassCapsule(interactive: true)
        .accessibilityIdentifier("AppShell.Done")
        .padding(.bottom, OpenClawSpace.sm)
    }
}
