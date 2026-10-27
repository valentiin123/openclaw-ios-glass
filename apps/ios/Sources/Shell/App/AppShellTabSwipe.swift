import OpenClawKit
import SwiftUI
import UIKit

// MARK: - Installer

/// Invisible anchor that installs one `UIPanGestureRecognizer` on the window, so a horizontal
/// drag is recognized anywhere on a tab page. The recognizer reports the live translation to the
/// pager (`AppShellPagerState.dragX`), so the pages follow the finger.
///
/// - It fails as soon as the first movement is not clearly horizontal (`gestureRecognizerShouldBegin`),
///   so vertical scrolling is never delayed.
/// - `cancelsTouchesInView` cancels the touches under the finger once it begins: no button fires,
///   no text gets selected.
/// - It never runs alongside another recognizer. A horizontal scroll view that already owns the
///   touch is detected when the touch starts and the swipe is not offered at all.
/// - Whether a touch may start a swipe is decided per touch in `gestureRecognizer(_:shouldReceive:)`,
///   so covers, sheets, pushed pages and the left screen edge (back gesture) never see it.
struct AppShellTabSwipeInstaller: UIViewRepresentable {
    /// Shell-level gate (no cover, no sheet, Home stack at its root).
    let canSwipe: @MainActor () -> Bool
    let onBegan: @MainActor () -> Void
    let onChanged: @MainActor (CGFloat) -> Void
    let onEnded: @MainActor (CGFloat, CGFloat) -> Void
    let onCancelled: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(installer: self)
    }

    func makeUIView(context: Context) -> AnchorView {
        let view: AnchorView = AnchorView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.update(with: self)
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
        /// The first movement must be this many times wider than tall.
        private static let dominance: CGFloat = 1.5

        private var installer: AppShellTabSwipeInstaller
        private let recognizer: UIPanGestureRecognizer = UIPanGestureRecognizer()
        private weak var window: UIWindow?
        private var touchStartedInHorizontalScroller: Bool = false

        init(installer: AppShellTabSwipeInstaller) {
            self.installer = installer
            super.init()
            self.recognizer.maximumNumberOfTouches = 1
            self.recognizer.cancelsTouchesInView = true
            self.recognizer.delaysTouchesBegan = false
            self.recognizer.delaysTouchesEnded = false
            self.recognizer.delegate = self
            self.recognizer.addTarget(self, action: #selector(self.handle(_:)))
        }

        func update(with newInstaller: AppShellTabSwipeInstaller) {
            self.installer = newInstaller
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
            guard let pan = gesture as? UIPanGestureRecognizer else { return }
            let translation: CGPoint = pan.translation(in: pan.view)
            let velocity: CGPoint = pan.velocity(in: pan.view)
            switch pan.state {
            case .began:
                self.installer.onBegan()
                self.installer.onChanged(translation.x)
            case .changed:
                self.installer.onChanged(translation.x)
            case .ended:
                self.installer.onEnded(translation.x, velocity.x)
            case .cancelled, .failed:
                self.installer.onCancelled()
            default:
                break
            }
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window = self.window else { return false }
            let location: CGPoint = touch.location(in: window)
            if location.x < Self.edgeInset { return false }
            if !self.installer.canSwipe() { return false }
            if Self.hasPresentation(window.rootViewController) { return false }
            if !Self.isRootTabContent(touch.view) { return false }
            self.touchStartedInHorizontalScroller = Self.isInsideHorizontalScroller(touch.view)
            return true
        }

        /// Fails immediately when the first recognized movement is vertical or diagonal, or when
        /// the touch started in a horizontal scroller.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            if self.touchStartedInHorizontalScroller { return false }
            let translation: CGPoint = pan.translation(in: pan.view)
            let absX: CGFloat = abs(translation.x)
            let absY: CGFloat = abs(translation.y)
            return absX > Self.dominance * absY
        }

        /// Whoever begins first wins: a row swipe action or a slider that already recognized
        /// keeps its gesture, and we never run alongside them.
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

        /// True when the touch is not on a control that owns horizontal drags and no pushed page
        /// exists in any navigation controller above the touch.
        private static func isRootTabContent(_ view: UIView?) -> Bool {
            var current: UIView? = view
            while let candidate = current {
                if candidate is UISlider || candidate is UISwitch || candidate is UISegmentedControl {
                    return false
                }
                current = candidate.superview
            }
            var responder: UIResponder? = view
            while let candidate = responder {
                if let navigation = candidate as? UINavigationController, navigation.viewControllers.count > 1 {
                    return false
                }
                responder = candidate.next
            }
            return true
        }

        /// True when an ancestor scroll view can scroll horizontally (carousels, paged content).
        private static func isInsideHorizontalScroller(_ view: UIView?) -> Bool {
            var current: UIView? = view
            while let candidate = current {
                if let scroll = candidate as? UIScrollView, scroll.isScrollEnabled {
                    let scrollsHorizontally: Bool = scroll.contentSize.width > scroll.bounds.width + 1
                    if scrollsHorizontally { return true }
                }
                current = candidate.superview
            }
            return false
        }
    }
}

// MARK: - Modifier

private struct AppShellTabSwipeModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let navigation: AppShellNavigation
    let pager: AppShellPagerState

    func body(content: Content) -> some View {
        let navigation: AppShellNavigation = self.navigation
        let pager: AppShellPagerState = self.pager
        let reduceMotion: Bool = self.reduceMotion
        return content.background(
            AppShellTabSwipeInstaller(
                canSwipe: { Self.canSwipe(navigation) },
                onBegan: { Self.begin(pager) },
                onChanged: { (translation: CGFloat) in
                    Self.change(navigation, pager: pager, translation: translation, reduceMotion: reduceMotion)
                },
                onEnded: { (translation: CGFloat, velocity: CGFloat) in
                    Self.finish(
                        navigation,
                        pager: pager,
                        translation: translation,
                        velocity: velocity,
                        reduceMotion: reduceMotion)
                },
                onCancelled: { Self.cancel(pager, reduceMotion: reduceMotion) }))
    }

    /// Shell state: no chat or Settings cover, no Home sheet, Home stack at its root.
    /// Pushed pages inside the Agents and Activity stacks are caught by the UIKit checks.
    @MainActor
    private static func canSwipe(_ navigation: AppShellNavigation) -> Bool {
        if navigation.isChatPresented || navigation.isSettingsPresented { return false }
        if navigation.presentedMore != nil { return false }
        return navigation.homePath.isEmpty
    }

    @MainActor
    private static func begin(_ pager: AppShellPagerState) {
        pager.isDragging = true
    }

    /// Moves the pages with the finger, clamped so nothing moves past the first or last tab.
    /// Under Reduce Motion the pages stay still during the drag and only switch on release.
    @MainActor
    private static func change(
        _ navigation: AppShellNavigation,
        pager: AppShellPagerState,
        translation: CGFloat,
        reduceMotion: Bool)
    {
        if reduceMotion { return }
        let index: Int = AppShellPagerMath.index(of: navigation.selection)
        pager.dragX = AppShellPagerMath.clamp(
            dragX: translation,
            index: index,
            count: AppShellTab.barTabs.count,
            width: pager.pageWidth)
    }

    /// Settles on the nearest page. `dragX` returns to 0 while the selected index changes, so the
    /// strip offset stays continuous and the spring carries the pages (and the bar indicator)
    /// to their final place.
    @MainActor
    private static func finish(
        _ navigation: AppShellNavigation,
        pager: AppShellPagerState,
        translation: CGFloat,
        velocity: CGFloat,
        reduceMotion: Bool)
    {
        let tabs: [AppShellTab] = AppShellTab.barTabs
        let index: Int = AppShellPagerMath.index(of: navigation.selection)
        let clamped: CGFloat = AppShellPagerMath.clamp(
            dragX: translation,
            index: index,
            count: tabs.count,
            width: pager.pageWidth)
        let target: Int = AppShellPagerMath.settleTarget(
            index: index,
            translation: clamped,
            velocity: velocity,
            width: pager.pageWidth,
            count: tabs.count)
        OpenClawMotion.perform(reduceMotion: reduceMotion) {
            pager.dragX = 0
            pager.isDragging = false
            if target != index, tabs.indices.contains(target) {
                navigation.userSelected(tabs[target])
            }
        }
    }

    @MainActor
    private static func cancel(_ pager: AppShellPagerState, reduceMotion: Bool) {
        OpenClawMotion.perform(reduceMotion: reduceMotion) {
            pager.dragX = 0
            pager.isDragging = false
        }
    }
}

extension View {
    /// Horizontal drag anywhere on the shell moves the pager (Agents, Home, Activity).
    func appShellTabSwipe(navigation: AppShellNavigation, pager: AppShellPagerState) -> some View {
        self.modifier(AppShellTabSwipeModifier(navigation: navigation, pager: pager))
    }
}
