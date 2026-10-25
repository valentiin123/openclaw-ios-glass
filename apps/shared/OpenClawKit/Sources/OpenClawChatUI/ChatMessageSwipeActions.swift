import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Simple message gestures for iOS: drag right to reply, drag left to copy.
/// The action bar under replies and the long-press menu stay the other entry points.
///
/// - Backed by a UIKit pan recognizer whose delegate refuses to begin unless the first movement
///   is horizontal-dominant. A vertical touch therefore never reaches this gesture, so the
///   enclosing scroll view starts scrolling on the very first drag. (The previous SwiftUI
///   `simultaneousGesture(DragGesture)` observed every touch on every row and could make the
///   scroll view ignore the first vertical drag.)
/// - A rightward drag that starts near the screen's leading edge belongs to the system
///   interactive back gesture, so the recognizer does not begin for it.
/// - Nested horizontal scrollers (code blocks, tables) keep priority: the recognizer is not
///   allowed to run simultaneously with other recognizers.
/// - Uses the shared chat spring (`OpenClawChatMotion`); under Reduce Motion the row does not
///   move and the hint simply fades in.
/// - Inert (and compiled out) on macOS, which keeps hover actions.
extension View {
    @ViewBuilder
    func chatMessageSwipeActions(onReply: (() -> Void)?, onCopy: (() -> Void)?) -> some View {
        #if os(iOS)
        if onReply == nil, onCopy == nil {
            self
        } else {
            modifier(ChatMessageSwipeActions(onReply: onReply, onCopy: onCopy))
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct ChatMessageSwipeActions: ViewModifier {
    let onReply: (() -> Void)?
    let onCopy: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var armed = false

    private static let activationDistance: CGFloat = 56
    private static let maximumTravel: CGFloat = 64
    private static let travelRatio: CGFloat = 0.6
    private static let armedTravel: CGFloat = activationDistance * 0.6 + 1
    /// Rightward drags that start this close to the screen's leading edge belong to the system
    /// interactive back gesture, so the reply swipe ignores them.
    private static let systemBackEdgeWidth: CGFloat = 28
    private static let hintSize: CGFloat = 16

    private var progress: Double {
        min(1, Double(abs(self.offset) / Self.activationDistance))
    }

    func body(content: Content) -> some View {
        content
            .offset(x: self.reduceMotion ? 0 : self.offset)
            .background(alignment: self.offset >= 0 ? .leading : .trailing) {
                self.hint
            }
            .gesture(self.pan)
    }

    private var pan: ChatHorizontalPanGesture {
        ChatHorizontalPanGesture(
            leadingExclusion: Self.systemBackEdgeWidth,
            onChanged: { dx in self.handleChanged(dx) },
            onEnded: { dx in self.handleEnded(dx) },
            onCancelled: { self.reset() })
    }

    @ViewBuilder
    private var hint: some View {
        if self.offset != 0 {
            Image(systemName: self.offset > 0 ? "arrowshape.turn.up.left" : "doc.on.doc")
                .font(OpenClawChatTypography.body(size: Self.hintSize, weight: .semibold, relativeTo: .body))
                .foregroundStyle(.secondary)
                .opacity(self.progress)
                .scaleEffect(self.armed ? 1.1 : 0.9)
                .padding(.horizontal, 12)
                .accessibilityHidden(true)
        }
    }

    private func handleChanged(_ dx: CGFloat) {
        guard let direction = self.allowedDirection(for: dx) else {
            if self.offset != 0 { self.reset() }
            return
        }
        let travel: CGFloat = min(Self.maximumTravel, abs(dx) * Self.travelRatio)
        let newOffset: CGFloat = direction * travel
        let isArmed: Bool = travel >= Self.armedTravel
        if isArmed != self.armed {
            self.armed = isArmed
            if isArmed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
            self.offset = newOffset
        }
    }

    private func handleEnded(_ dx: CGFloat) {
        let action: (() -> Void)? = self.armed ? self.action(for: dx) : nil
        self.reset()
        action?()
    }

    private func allowedDirection(for dx: CGFloat) -> CGFloat? {
        if dx > 0, self.onReply != nil { return 1 }
        if dx < 0, self.onCopy != nil { return -1 }
        return nil
    }

    private func action(for dx: CGFloat) -> (() -> Void)? {
        dx > 0 ? self.onReply : self.onCopy
    }

    private func reset() {
        self.armed = false
        OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
            self.offset = 0
        }
    }
}

/// Horizontal-only pan. `gestureRecognizerShouldBegin` rejects vertical-dominant starts, so the
/// recognizer never competes with the transcript scroll view for a vertical drag.
struct ChatHorizontalPanGesture: UIGestureRecognizerRepresentable {
    /// Horizontal dominance required at the start of the pan.
    static let dominance: CGFloat = 1.5

    let leadingExclusion: CGFloat
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void
    let onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(leadingExclusion: self.leadingExclusion)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx: CGFloat = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            self.onChanged(dx)
        case .ended:
            self.onEnded(dx)
        case .cancelled, .failed:
            self.onCancelled()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let leadingExclusion: CGFloat

        init(leadingExclusion: CGFloat) {
            self.leadingExclusion = leadingExclusion
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity: CGPoint = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) * ChatHorizontalPanGesture.dominance else { return false }
            guard velocity.x > 0 else { return true }
            // Window-space start of the touch: current location minus what has been travelled.
            let translation: CGPoint = pan.translation(in: pan.view)
            let location: CGPoint = pan.location(in: pan.view?.window)
            return (location.x - translation.x) >= self.leadingExclusion
        }
    }
}
#endif
