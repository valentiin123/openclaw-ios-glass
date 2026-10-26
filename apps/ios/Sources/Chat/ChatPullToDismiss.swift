import SwiftUI
import UIKit

// Pull-to-dismiss for full-screen chat hosts (subagent cover).
// Only a downward drag that starts in the top grab zone (header area) is handled. It runs on a passive
// UIKit pan recognizer (never cancels or delays touches, recognizes alongside every other recognizer) that
// refuses to begin outside the grab zone, so the transcript scroll view and the interactive keyboard
// dismissal never compete with it. While the keyboard is visible the recognizer is disabled: a downward
// drag then means "lower the keyboard", not "leave the chat".
// The drag moves the content with resistance and commits past a threshold. Under Reduce Motion nothing
// moves; the gesture only commits.
// The close / back button stays the primary path: a gesture is never the only way out.

private enum ChatPullToDismissMetric {
    /// Drag must start within this distance below the top safe area.
    static let grabZone: CGFloat = 140
    static let commitDistance: CGFloat = 110
    /// Content follows the finger at this fraction.
    static let resistance: CGFloat = 0.55
    /// Vertical travel must dominate horizontal travel (keeps edge swipe-back working).
    static let dominance: CGFloat = 1.5
    static let maxDim: Double = 0.3
    static let dimDistance: CGFloat = 400
}

/// Passive vertical pan. `gestureRecognizerShouldBegin` rejects everything that is not a downward,
/// vertical-dominant drag starting in the top grab zone. Translation is read in window space so the
/// offset applied to the content cannot feed back into the measurement.
private struct ChatPullPanGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void
    let onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.isEnabled = self.isEnabled
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        if recognizer.isEnabled != self.isEnabled {
            recognizer.isEnabled = self.isEnabled
        }
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dy: CGFloat = recognizer.translation(in: nil).y
        switch recognizer.state {
        case .began, .changed:
            self.onChanged(dy)
        case .ended:
            self.onEnded(dy)
        case .cancelled, .failed:
            self.onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity: CGPoint = pan.velocity(in: nil)
            guard velocity.y > 0 else { return false }
            guard velocity.y > abs(velocity.x) * ChatPullToDismissMetric.dominance else { return false }
            // Window-space start of the touch: current location minus what has been travelled.
            let translation: CGPoint = pan.translation(in: nil)
            let location: CGPoint = pan.location(in: nil)
            let safeTop: CGFloat = pan.view?.window?.safeAreaInsets.top ?? 0
            let startY: CGFloat = location.y - translation.y - safeTop
            return startY <= ChatPullToDismissMetric.grabZone
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool
        {
            true
        }
    }
}

private struct ChatPullToDismissModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pull: CGFloat = 0
    @State private var isKeyboardVisible = false

    let isEnabled: Bool
    let onDismiss: () -> Void

    private var offsetY: CGFloat {
        self.reduceMotion ? 0 : self.pull
    }

    private var opacityValue: Double {
        if self.reduceMotion { return 1 }
        let ratio: Double = Double(self.pull / ChatPullToDismissMetric.dimDistance)
        return 1 - min(ChatPullToDismissMetric.maxDim, max(0, ratio))
    }

    private var reachedThreshold: Bool {
        self.pull >= ChatPullToDismissMetric.commitDistance
    }

    private var gestureActive: Bool {
        self.isEnabled && !self.isKeyboardVisible
    }

    func body(content: Content) -> some View {
        content
            .offset(y: self.offsetY)
            .opacity(self.opacityValue)
            .gesture(ChatPullPanGesture(
                isEnabled: self.gestureActive,
                onChanged: { dy in self.handleChange(dy) },
                onEnded: { dy in self.handleEnd(dy) },
                onCancelled: { self.reset() }))
            .sensoryFeedback(.impact(weight: .light), trigger: self.reachedThreshold)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                self.isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                self.isKeyboardVisible = false
            }
    }

    private func handleChange(_ translationY: CGFloat) {
        guard self.gestureActive, translationY > 0 else {
            if self.pull != 0 { self.reset() }
            return
        }
        self.pull = translationY * ChatPullToDismissMetric.resistance
    }

    private func handleEnd(_ translationY: CGFloat) {
        guard self.gestureActive, translationY > 0 else {
            self.reset()
            return
        }
        let travelled: CGFloat = translationY * ChatPullToDismissMetric.resistance
        if travelled >= ChatPullToDismissMetric.commitDistance {
            self.onDismiss()
        } else {
            self.reset()
        }
    }

    private func reset() {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.pull = 0
        }
    }
}

extension View {
    /// Downward pull from the top zone dismisses the screen (`onDismiss`). Scrolling is untouched.
    /// Keep a visible close / back button: this gesture is a shortcut, not the only path.
    func chatPullToDismiss(isEnabled: Bool = true, onDismiss: @escaping () -> Void) -> some View {
        modifier(ChatPullToDismissModifier(isEnabled: isEnabled, onDismiss: onDismiss))
    }
}
