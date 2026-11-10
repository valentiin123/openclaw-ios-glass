import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Tap on the transcript dismisses the keyboard without ever competing with scrolling.
///
/// The previous SwiftUI `simultaneousGesture(TapGesture())` sat on the whole scroll container and
/// took part in SwiftUI's gesture arbitration for every touch. This UIKit recognizer never cancels or
/// delays touches (`cancelsTouchesInView = false`, `delaysTouchesBegan = false`) and recognizes
/// simultaneously with every other recognizer, so the scroll view starts on the first drag.
extension View {
    @ViewBuilder
    func chatTapToDismissKeyboard(_ onTap: @escaping () -> Void) -> some View {
        #if os(iOS)
        self.gesture(ChatPassiveTapGesture(onTap: onTap))
        #else
        self
        #endif
    }
}

/// Geometry the swipe-down dismissal needs, kept in a reference box so the keyboard frame and the per-frame
/// composer position never invalidate the chat view body. Written by the view, read by the gesture.
@MainActor
final class ChatKeyboardDismissMetrics {
    /// Height of the keyboard frame at the last `keyboardWillShow`; 0 while the keyboard is hidden.
    var keyboardHeight: CGFloat = 0
    /// Top edge of the composer in global coordinates. Infinity until measured, so an unmeasured composer
    /// can never satisfy "finger below the composer".
    var composerMinY: CGFloat = .infinity
}

#if os(iOS)
struct ChatPassiveTapGesture: UIGestureRecognizerRepresentable {
    let onTap: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        self.onTap()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool
        {
            true
        }
    }
}
#endif

/// Lowers the keyboard only when the user clearly means it, like iMessage: a long downward swipe that
/// travels at least half the keyboard height and whose finger has gone below the top of the composer.
/// A short flick, a normal scroll of the transcript, a text selection or a tap never fires it.
/// The transcript keeps its own native `.scrollDismissesKeyboard(.interactively)`.
/// The recognizer is passive (never cancels or delays touches, recognizes alongside every other recognizer).
extension View {
    @ViewBuilder
    func chatSwipeDownDismissesKeyboard(
        metrics: ChatKeyboardDismissMetrics,
        onSwipe: @escaping () -> Void) -> some View
    {
        #if os(iOS)
        self.gesture(ChatSwipeDownGesture(metrics: metrics, onSwipe: onSwipe))
        #else
        self
        #endif
    }
}

#if os(iOS)
struct ChatSwipeDownGesture: UIGestureRecognizerRepresentable {
    /// Fraction of the keyboard height the finger must travel downward before the keyboard lowers.
    static let dismissFraction: CGFloat = 0.5
    /// Floor for that travel, so an unusually short keyboard frame (hardware keyboard bar) never makes the
    /// swipe trivial. The rule is "at least half the keyboard height"; this only raises it for tiny frames.
    static let minimumTravel: CGFloat = 80
    /// Vertical travel must exceed horizontal travel by this factor over the whole swipe.
    static let dominance: CGFloat = 1.5

    let metrics: ChatKeyboardDismissMetrics
    let onSwipe: () -> Void

    /// Pure decision, kept free of UIKit so the rule can be unit tested.
    /// `translation` is the cumulative finger travel since touch-down; `fingerY` and `composerMinY` share
    /// the same (window/global) coordinate space.
    static func shouldDismiss(
        translation: CGPoint,
        fingerY: CGFloat,
        keyboardHeight: CGFloat,
        composerMinY: CGFloat) -> Bool
    {
        guard keyboardHeight > 0, composerMinY.isFinite else { return false }
        let requiredTravel: CGFloat = max(Self.minimumTravel, keyboardHeight * Self.dismissFraction)
        guard translation.y >= requiredTravel else { return false }
        guard translation.y >= abs(translation.x) * Self.dominance else { return false }
        return fingerY > composerMinY
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(metrics: self.metrics)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let coordinator: Coordinator = context.coordinator
        switch recognizer.state {
        case .changed:
            guard !coordinator.hasFired else { return }
            // Window coordinates (nil view), matching SwiftUI's global space and the keyboard frame.
            let finger: CGPoint = recognizer.location(in: nil)
            let translation = CGPoint(
                x: finger.x - coordinator.startLocation.x,
                y: finger.y - coordinator.startLocation.y)
            guard Self.shouldDismiss(
                translation: translation,
                fingerY: finger.y,
                keyboardHeight: self.metrics.keyboardHeight,
                composerMinY: self.metrics.composerMinY)
            else { return }
            coordinator.hasFired = true
            self.onSwipe()
        case .ended, .cancelled, .failed:
            coordinator.hasFired = false
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let metrics: ChatKeyboardDismissMetrics
        /// The keyboard lowers at most once per swipe.
        var hasFired = false
        /// Finger position at touch-down, in window coordinates. The pan's own translation starts after the
        /// touch slop, so the cumulative travel is measured from this instead.
        var startLocation: CGPoint = .zero

        init(metrics: ChatKeyboardDismissMetrics) {
            self.metrics = metrics
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer.state == .possible {
                self.startLocation = touch.location(in: nil)
                self.hasFired = false
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool
        {
            true
        }
    }
}
#endif
