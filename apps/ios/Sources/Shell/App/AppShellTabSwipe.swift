import OpenClawKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - Recognizer

/// Pan recognizer that makes its decision early and exclusively.
///
/// While the recognizer is still `.possible`, the first few points of movement decide:
/// - clearly horizontal (angle to the horizontal below ~40°): the pan goes on and begins normally;
/// - anything else (vertical, diagonal): the recognizer fails at once. Failing cancels nothing,
///   so the scroll view, the list or the slider under the finger keeps the touch untouched.
final class AppShellHorizontalPanRecognizer: UIPanGestureRecognizer {
    /// tan(40°): a movement is horizontal only when |dy| <= tangent * |dx|.
    static let maxTangent: CGFloat = 0.84
    /// Distance (points, in window coordinates) after which the direction is judged.
    static let decisionDistance: CGFloat = 10
    /// Distance after which a clearly horizontal movement begins the pan without waiting for the
    /// system slop, so it wins the race against the vertical scroll view of a list.
    static let earlyBeginDistance: CGFloat = 4
    /// tan(30°): the early begin needs an almost purely horizontal movement.
    static let earlyBeginTangent: CGFloat = 0.8

    private var origin: CGPoint = CGPoint.zero
    private var decided: Bool = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let first = touches.first {
            self.origin = first.location(in: nil)
        }
        self.decided = false
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if self.state == .possible, !self.decided, let first = touches.first {
            let point: CGPoint = first.location(in: nil)
            let dx: CGFloat = abs(point.x - self.origin.x)
            let dy: CGFloat = abs(point.y - self.origin.y)
            if hypot(dx, dy) >= Self.decisionDistance {
                if dy > Self.maxTangent * dx {
                    self.state = .failed
                    return
                }
                self.decided = true
            }
        }
        super.touchesMoved(touches, with: event)
        if self.state == .possible, let first = touches.first {
            let point: CGPoint = first.location(in: nil)
            let dx: CGFloat = abs(point.x - self.origin.x)
            let dy: CGFloat = abs(point.y - self.origin.y)
            if dx >= Self.earlyBeginDistance, dy <= Self.earlyBeginTangent * dx {
                self.decided = true
                self.state = .began
            }
        }
    }

    override func reset() {
        super.reset()
        self.decided = false
        self.origin = CGPoint.zero
    }
}

// MARK: - Installer

/// Invisible anchor that installs one horizontal pan recognizer on the window, so a horizontal
/// drag is recognized anywhere on a tab page. The recognizer reports the live translation to the
/// pager (`AppShellPagerState.dragX`), so the pages follow the finger.
///
/// - The decision is early and exclusive (`AppShellHorizontalPanRecognizer`): a movement that is
///   not clearly horizontal makes it fail at once, without cancelling anything, so vertical
///   scrolling is never taken over and never delayed.
/// - `cancelsTouchesInView` cancels the touches under the finger once it begins: no button fires,
///   no text gets selected. Competing pans of the ancestors (scroll views, row swipe actions) are
///   required to wait for this recognizer (`shouldBeRequiredToFailBy`) and are switched off for
///   the rest of the touch once it begins.
/// - It never runs alongside another recognizer, and never starts from a horizontal scroller,
///   a slider, a switch, a segmented control, a row with a swipe action, the left screen edge
///   (back gesture), a presentation or a pushed page (`gestureRecognizer(_:shouldReceive:)`).
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
        /// Velocity direction tolerance (|vy| <= k * |vx|). A bit looser than the translation
        /// angle because the first velocity sample is noisy.
        private static let velocityTangent: CGFloat = 1.0
        /// Distance over which the translation consumed by the recognizer's slop is given back to
        /// the finger, so the pages do not jump when the pan begins.
        private static let catchUpDistance: CGFloat = 48

        private var installer: AppShellTabSwipeInstaller
        private let recognizer: AppShellHorizontalPanRecognizer = AppShellHorizontalPanRecognizer()
        private weak var window: UIWindow?
        private weak var touchView: UIView?
        private var touchStartedInHorizontalScroller: Bool = false
        /// Translation at the moment the pan was recognized (the slop already travelled).
        private var startX: CGFloat = 0

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
            self.touchView = nil
        }

        @objc private func handle(_ gesture: UIGestureRecognizer) {
            guard let pan = gesture as? UIPanGestureRecognizer else { return }
            let translation: CGPoint = pan.translation(in: pan.view)
            let velocity: CGPoint = pan.velocity(in: pan.view)
            switch pan.state {
            case .began:
                self.startX = translation.x
                self.cancelCompetingPans()
                self.installer.onBegan()
                self.installer.onChanged(self.compensated(translation.x))
            case .changed:
                self.installer.onChanged(self.compensated(translation.x))
            case .ended:
                let adjusted: CGFloat = self.compensated(translation.x)
                self.startX = 0
                self.touchView = nil
                self.installer.onEnded(adjusted, velocity.x)
            case .cancelled, .failed:
                self.startX = 0
                self.touchView = nil
                self.installer.onCancelled()
            default:
                break
            }
        }

        /// Starts at 0 when the pan begins and gives the slop back to the finger progressively.
        private func compensated(_ x: CGFloat) -> CGFloat {
            let travelled: CGFloat = abs(x - self.startX)
            let remaining: CGFloat = 1 - min(travelled / Self.catchUpDistance, 1)
            return x - self.startX * remaining
        }

        /// Once the swipe is recognized, forces every competing pan above the touched view
        /// (scroll views, row swipe actions, drag recognizers) to give up: switching a recognizer
        /// off and on again cancels the gesture it is running and it stays idle until the next touch.
        private func cancelCompetingPans() {
            var current: UIView? = self.touchView
            while let candidate = current {
                if let recognizers = candidate.gestureRecognizers {
                    for other in recognizers where other !== self.recognizer {
                        if Self.isCompetingPan(other), other.isEnabled {
                            other.isEnabled = false
                            other.isEnabled = true
                        }
                    }
                }
                current = candidate.superview
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
            self.touchView = touch.view
            self.touchStartedInHorizontalScroller = Self.isInsideHorizontalScroller(touch.view)
            return true
        }

        /// Last check when the pan is about to begin: the first movement and the first velocity
        /// must both be clearly horizontal, and the touch must not come from a horizontal scroller.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            if self.touchStartedInHorizontalScroller { return false }
            let translation: CGPoint = pan.translation(in: pan.view)
            let velocity: CGPoint = pan.velocity(in: pan.view)
            let absX: CGFloat = abs(translation.x)
            let absY: CGFloat = abs(translation.y)
            // An early begin can happen before the pan has accumulated any translation or velocity
            // of its own: the recognizer already checked the angle, so only reject a measured
            // movement that is clearly not horizontal.
            if absX > 0, absY > AppShellHorizontalPanRecognizer.maxTangent * absX { return false }
            if abs(velocity.x) + abs(velocity.y) < 50 { return true }
            return abs(velocity.y) <= Self.velocityTangent * abs(velocity.x)
        }

        /// Whoever begins first wins: a row swipe action or a slider that already recognized
        /// keeps its gesture, and we never run alongside them.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
        {
            false
        }

        /// Pans of the views above the touch (vertical scroll views, drag recognizers) wait until
        /// this recognizer has decided. The wait is short: a vertical or diagonal movement makes
        /// this recognizer fail after a few points, before the scroll view's own slop is reached.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool
        {
            if otherGestureRecognizer === self.recognizer { return false }
            if !Self.isCompetingPan(otherGestureRecognizer) { return false }
            guard let owner = otherGestureRecognizer.view, let touched = self.touchView else { return false }
            return touched.isDescendant(of: owner)
        }

        // MARK: UIKit checks

        /// True for recognizers that move content with a drag: pans (except the screen edge pan,
        /// which belongs to the back gesture) and recognizers named after a pan, drag or swipe.
        private static func isCompetingPan(_ candidate: UIGestureRecognizer) -> Bool {
            if candidate is UIScreenEdgePanGestureRecognizer { return false }
            if candidate is UIPanGestureRecognizer { return true }
            let name: String = NSStringFromClass(type(of: candidate))
            return name.contains("Pan") || name.contains("Drag") || name.contains("SwipeAction")
        }

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
                if candidate is UIPickerView || candidate is UIDatePicker { return false }
                if Self.ownsSwipeAction(candidate) { return false }
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

        /// True when the view carries an enabled row swipe-action recognizer (list rows with
        /// swipe actions). Matched by class name only, no private API is called.
        private static func ownsSwipeAction(_ view: UIView) -> Bool {
            guard let recognizers = view.gestureRecognizers else { return false }
            for candidate in recognizers where candidate.isEnabled {
                let name: String = NSStringFromClass(type(of: candidate))
                if name.contains("SwipeAction") { return true }
            }
            return false
        }

        /// True when an ancestor scroll view can scroll horizontally (carousels, paged content).
        private static func isInsideHorizontalScroller(_ view: UIView?) -> Bool {
            var current: UIView? = view
            while let candidate = current {
                if let scroll = candidate as? UIScrollView, scroll.isScrollEnabled {
                    let overflows: Bool = scroll.contentSize.width > scroll.bounds.width + 1
                    if overflows || scroll.alwaysBounceHorizontal { return true }
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

    /// A drag that starts while a settle animation still runs follows the finger through a
    /// spring (`tracksWithSpring`), so the pages continue from where they are on screen.
    @MainActor
    private static func begin(_ pager: AppShellPagerState) {
        pager.tracksWithSpring = pager.isSettling()
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
        let target: CGFloat = AppShellPagerMath.clamp(
            dragX: translation,
            index: index,
            count: AppShellTab.barTabs.count,
            width: pager.pageWidth)
        if pager.tracksWithSpring && pager.isSettling() {
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
                pager.dragX = target
            }
        } else {
            var transaction: Transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pager.dragX = target
            }
        }
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
        pager.noteSettle()
        pager.tracksWithSpring = false
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
        pager.noteSettle()
        pager.tracksWithSpring = false
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
