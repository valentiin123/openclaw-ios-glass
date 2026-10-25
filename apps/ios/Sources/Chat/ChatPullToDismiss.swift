import SwiftUI

// Pull-to-dismiss for full-screen chat hosts (subagent cover).
// Only a downward drag that starts in the top grab zone (header area) is handled, so the
// transcript scroll view keeps priority. The drag moves the content with resistance and
// commits past a threshold. Under Reduce Motion nothing moves; the gesture only commits.
// The close / back button stays the primary path: a gesture is never the only way out.

private enum ChatPullToDismissMetric {
    /// Drag must start within this distance from the top edge.
    static let grabZone: CGFloat = 140
    static let minimumDistance: CGFloat = 12
    static let commitDistance: CGFloat = 110
    /// Content follows the finger at this fraction.
    static let resistance: CGFloat = 0.55
    /// Vertical travel must dominate horizontal travel (keeps edge swipe-back working).
    static let dominance: CGFloat = 1.5
    static let maxDim: Double = 0.3
    static let dimDistance: CGFloat = 400
}

private struct ChatPullToDismissModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pull: CGFloat = 0

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

    private var mask: GestureMask {
        self.isEnabled ? .all : .subviews
    }

    func body(content: Content) -> some View {
        content
            .offset(y: self.offsetY)
            .opacity(self.opacityValue)
            .simultaneousGesture(self.dragGesture, including: self.mask)
            .sensoryFeedback(.impact(weight: .light), trigger: self.reachedThreshold)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: ChatPullToDismissMetric.minimumDistance)
            .onChanged { value in
                self.handleChange(value)
            }
            .onEnded { value in
                self.handleEnd(value)
            }
    }

    private func isPull(_ value: DragGesture.Value) -> Bool {
        guard value.startLocation.y <= ChatPullToDismissMetric.grabZone else { return false }
        let down: CGFloat = value.translation.height
        let side: CGFloat = abs(value.translation.width)
        guard down > 0 else { return false }
        return down > ChatPullToDismissMetric.dominance * side
    }

    private func handleChange(_ value: DragGesture.Value) {
        guard self.isEnabled, self.isPull(value) else {
            if self.pull != 0 { self.reset() }
            return
        }
        self.pull = value.translation.height * ChatPullToDismissMetric.resistance
    }

    private func handleEnd(_ value: DragGesture.Value) {
        guard self.isEnabled, self.isPull(value) else {
            self.reset()
            return
        }
        let travelled: CGFloat = value.translation.height * ChatPullToDismissMetric.resistance
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
