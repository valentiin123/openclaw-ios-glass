import OpenClawKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - Direction

/// Direction of a horizontal tab swipe, in tab-bar order (Agents, Home, Activity).
/// A finger moving left reveals the next tab on the right (`forward`).
enum AppShellTabSwipeDirection {
    case forward
    case backward
}

// MARK: - Recognizer

/// Discrete horizontal swipe recognizer. It stays in `.possible` until the finger has travelled
/// `minDistance` points with a clear horizontal dominance (`|dx| > dominance * |dy|`), then
/// begins once. It fails as soon as the movement is vertical, so vertical scrolling is never
/// delayed. `cancelsTouchesInView` only matters after it began: views under the finger receive
/// `touchesCancelled`, so no button fires and no text gets selected by the swipe.
final class AppShellTabSwipeRecognizer: UIGestureRecognizer {
    static let minDistance: CGFloat = 24
    static let dominance: CGFloat = 1.5

    private(set) var direction: AppShellTabSwipeDirection?
    private var startPoint: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        self.direction = nil
        guard self.numberOfTouches == 1, let touch = touches.first else {
            self.state = .failed
            return
        }
        self.startPoint = touch.location(in: self.view)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if self.state == .began || self.state == .changed {
            self.state = .changed
            return
        }
        guard self.state == .possible else { return }
        guard self.numberOfTouches == 1, let touch = touches.first else {
            self.state = .failed
            return
        }
        let point: CGPoint = touch.location(in: self.view)
        let dx: CGFloat = point.x - self.startPoint.x
        let dy: CGFloat = point.y - self.startPoint.y
        let absX: CGFloat = abs(dx)
        let absY: CGFloat = abs(dy)
        if absX >= Self.minDistance, absX > Self.dominance * absY {
            self.direction = dx < 0 ? .forward : .backward
            self.state = .began
        } else if absY >= Self.minDistance || absX > Self.minDistance * 3 {
            self.state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if self.state == .began || self.state == .changed {
            self.state = .ended
        } else {
            self.state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if self.state == .began || self.state == .changed {
            self.state = .cancelled
        } else {
            self.state = .failed
        }
    }

    override func reset() {
        super.reset()
        self.direction = nil
        self.startPoint = .zero
    }
}

// MARK: - Installer

/// Invisible anchor that installs one `AppShellTabSwipeRecognizer` on the window, so a swipe is
/// recognized anywhere on the page. Whether a touch may start a swipe is decided per touch in
/// `gestureRecognizer(_:shouldReceive:)`, so covers, sheets, pushed pages and the tab bar never
/// see the gesture.
struct AppShellTabSwipeInstaller: UIViewRepresentable {
    /// Shell-level gate (no cover, no sheet, Home stack at its root).
    let canSwipe: @MainActor () -> Bool
    let onSwipe: @MainActor (AppShellTabSwipeDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(canSwipe: self.canSwipe, onSwipe: self.onSwipe)
    }

    func makeUIView(context: Context) -> AnchorView {
        let view: AnchorView = AnchorView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.canSwipe = self.canSwipe
        context.coordinator.onSwipe = self.onSwipe
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class AnchorView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window = self.window {
                self.coordinator?.attach(to: window)
            } else {
                self.coordinator?.detach()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Touches starting closer than this to the left edge belong to the back gesture.
        private static let edgeInset: CGFloat = 24

        var canSwipe: @MainActor () -> Bool
        var onSwipe: @MainActor (AppShellTabSwipeDirection) -> Void
        private let recognizer: AppShellTabSwipeRecognizer = AppShellTabSwipeRecognizer()
        private weak var window: UIWindow?

        init(
            canSwipe: @escaping @MainActor () -> Bool,
            onSwipe: @escaping @MainActor (AppShellTabSwipeDirection) -> Void)
        {
            self.canSwipe = canSwipe
            self.onSwipe = onSwipe
            super.init()
            self.recognizer.cancelsTouchesInView = true
            self.recognizer.delaysTouchesBegan = false
            self.recognizer.delaysTouchesEnded = false
            self.recognizer.delegate = self
            self.recognizer.addTarget(self, action: #selector(self.handle(_:)))
        }

        func attach(to newWindow: UIWindow) {
            if self.window === newWindow { return }
            self.detach()
            newWindow.addGestureRecognizer(self.recognizer)
            self.window = newWindow
        }

        func detach() {
            self.window?.removeGestureRecognizer(self.recognizer)
            self.window = nil
        }

        @objc private func handle(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began,
                  let swipe = gesture as? AppShellTabSwipeRecognizer,
                  let direction = swipe.direction
            else { return }
            self.onSwipe(direction)
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window = self.window else { return false }
            let location: CGPoint = touch.location(in: window)
            if location.x < Self.edgeInset { return false }
            if !self.canSwipe() { return false }
            if Self.hasPresentation(window.rootViewController) { return false }
            return Self.isRootTabContent(touch.view)
        }

        /// Whoever begins first wins: a horizontal scroller, a row swipe action or a slider that
        /// already recognized keeps its gesture, and we never run alongside them.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
        {
            false
        }

        // MARK: UIKit checks

        /// True when a sheet, a full-screen cover or an alert is presented anywhere in the tree.
        private static func hasPresentation(_ controller: UIViewController?) -> Bool {
            guard let controller else { return false }
            if controller.presentedViewController != nil { return true }
            for child in controller.children {
                if self.hasPresentation(child) { return true }
            }
            return false
        }

        /// True when the touch is on the root of a tab: not on the tab bar, not on a control that
        /// owns horizontal drags, no pushed page in any navigation controller above the touch,
        /// and the tab bar is visible.
        private static func isRootTabContent(_ view: UIView?) -> Bool {
            var current: UIView? = view
            while let candidate = current {
                if candidate is UITabBar || candidate is UISlider || candidate is UISwitch
                    || candidate is UISegmentedControl
                {
                    return false
                }
                current = candidate.superview
            }
            var responder: UIResponder? = view
            while let candidate = responder {
                if let navigation = candidate as? UINavigationController, navigation.viewControllers.count > 1 {
                    return false
                }
                if let tabs = candidate as? UITabBarController, tabs.tabBar.isHidden {
                    return false
                }
                responder = candidate.next
            }
            return true
        }
    }
}

// MARK: - Modifier

private struct AppShellTabSwipeModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let navigation: AppShellNavigation

    func body(content: Content) -> some View {
        let navigation: AppShellNavigation = self.navigation
        let reduceMotion: Bool = self.reduceMotion
        return content.background(
            AppShellTabSwipeInstaller(
                canSwipe: { Self.canSwipe(navigation) },
                onSwipe: { (direction: AppShellTabSwipeDirection) in
                    Self.switchTab(navigation, direction: direction, reduceMotion: reduceMotion)
                }))
    }

    /// Shell state: no chat or Settings cover, no Home sheet, Home stack at its root.
    /// Pushed pages inside the Agents and Activity stacks are caught by the UIKit checks.
    @MainActor
    private static func canSwipe(_ navigation: AppShellNavigation) -> Bool {
        if navigation.isChatPresented || navigation.isSettingsPresented { return false }
        if navigation.presentedMore != nil { return false }
        return navigation.homePath.isEmpty
    }

    /// Moves one bar tab left or right. Does nothing at either end. Uses `userSelected`, which
    /// restores the Activity section; the section itself is never changed by a swipe. The root
    /// `.sensoryFeedback(.selection, trigger: selection.barTab)` supplies the haptic.
    @MainActor
    private static func switchTab(
        _ navigation: AppShellNavigation,
        direction: AppShellTabSwipeDirection,
        reduceMotion: Bool)
    {
        let tabs: [AppShellTab] = AppShellTab.barTabs
        guard let index = tabs.firstIndex(of: navigation.selection.barTab) else { return }
        let step: Int = direction == .forward ? 1 : -1
        let target: Int = index + step
        guard tabs.indices.contains(target) else { return }
        let destination: AppShellTab = tabs[target]
        OpenClawMotion.perform(reduceMotion: reduceMotion) {
            navigation.userSelected(destination)
        }
    }
}

extension View {
    /// Horizontal swipe anywhere on the shell switches the bar tab (Agents, Home, Activity).
    func appShellTabSwipe(navigation: AppShellNavigation) -> some View {
        self.modifier(AppShellTabSwipeModifier(navigation: navigation))
    }
}
