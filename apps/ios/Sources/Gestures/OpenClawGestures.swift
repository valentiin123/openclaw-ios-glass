import SwiftUI

// MARK: - Gesture modifiers
//
// Reusable gestures built on the shared `OpenClawMotion` spring. Every gesture has a
// non-gesture equivalent for VoiceOver / Switch Control (custom accessibility actions),
// and no gesture is the only way to reach a function.

// MARK: - Horizontal swipe

/// Direction of a committed horizontal swipe.
enum OpenClawSwipeDirection: Sendable {
    case leading
    case trailing
}

private enum OpenClawSwipeMetric {
    static let minimumDistance: CGFloat = 24
    static let commitDistance: CGFloat = 64
    /// Horizontal travel must dominate vertical travel so scrolling keeps priority.
    static let dominance: CGFloat = 2
}

private struct OpenClawSwipeModifier: ViewModifier {
    let onLeading: (() -> Void)?
    let onTrailing: (() -> Void)?

    func body(content: Content) -> some View {
        content.simultaneousGesture(self.swipeGesture)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: OpenClawSwipeMetric.minimumDistance)
            .onEnded { value in
                self.handle(translation: value.translation)
            }
    }

    private func handle(translation: CGSize) {
        guard let direction = Self.direction(for: translation) else { return }
        switch direction {
        case .leading:
            self.onLeading?()
        case .trailing:
            self.onTrailing?()
        }
    }

    static func direction(for translation: CGSize) -> OpenClawSwipeDirection? {
        let width = translation.width
        let height = translation.height
        guard abs(width) >= OpenClawSwipeMetric.commitDistance else { return nil }
        guard abs(width) > OpenClawSwipeMetric.dominance * abs(height) else { return nil }
        return width > 0 ? .leading : .trailing
    }
}

// MARK: - Long press

private struct OpenClawLongPressModifier: ViewModifier {
    @State private var fired = 0
    let minimumDuration: Double
    let accessibilityTitle: OpenClawTextValue?
    let perform: () -> Void

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: self.minimumDuration) {
                self.fire()
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: self.fired)
            .modifier(OpenClawLongPressAccessibility(
                title: self.accessibilityTitle,
                perform: self.perform))
    }

    private func fire() {
        self.fired += 1
        self.perform()
    }
}

private struct OpenClawLongPressAccessibility: ViewModifier {
    let title: OpenClawTextValue?
    let perform: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if let title = self.title {
            content.accessibilityAction(named: title.text) {
                self.perform()
            }
        } else {
            content
        }
    }
}

// MARK: - Pull to refresh

private struct OpenClawRefreshModifier: ViewModifier {
    @State private var completed = 0
    let action: @Sendable () async -> Void

    func body(content: Content) -> some View {
        content
            .refreshable {
                await self.runRefresh()
            }
            .sensoryFeedback(.success, trigger: self.completed)
    }

    @MainActor
    private func runRefresh() async {
        await self.action()
        self.completed += 1
    }
}

// MARK: - Press-and-hold scale feedback

private struct OpenClawPressFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(self.scale)
            .animation(OpenClawMotion.animation(reduceMotion: self.reduceMotion), value: self.isPressed)
            .simultaneousGesture(self.pressGesture)
    }

    private var scale: CGFloat {
        guard self.isPressed, !self.reduceMotion else { return 1 }
        return OpenClawMotion.pressedScale
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating(self.$isPressed) { _, state, _ in
                state = true
            }
    }
}

// MARK: - Public API

extension View {
    /// Horizontal swipe with a commit threshold. Vertical scrolling keeps priority.
    /// `onLeading` fires for a rightward swipe, `onTrailing` for a leftward one.
    /// Mirror each handler as an accessibility action: a swipe must never be the only path.
    func openClawSwipe(
        onLeading: (() -> Void)? = nil,
        onTrailing: (() -> Void)? = nil) -> some View
    {
        modifier(OpenClawSwipeModifier(onLeading: onLeading, onTrailing: onTrailing))
    }

    /// Long press with medium haptic. Pass `accessibilityTitle` to expose it as a VoiceOver action.
    func openClawLongPress(
        minimumDuration: Double = 0.45,
        accessibilityTitle: OpenClawTextValue? = nil,
        perform: @escaping () -> Void) -> some View
    {
        modifier(OpenClawLongPressModifier(
            minimumDuration: minimumDuration,
            accessibilityTitle: accessibilityTitle,
            perform: perform))
    }

    /// Native pull to refresh with a success haptic once the async work finishes.
    /// Apply to a `ScrollView` or `List`.
    func openClawRefreshable(action: @escaping @Sendable () async -> Void) -> some View {
        modifier(OpenClawRefreshModifier(action: action))
    }

    /// Subtle scale-down while a finger is on the content. Static under Reduce Motion.
    /// For content that is not a `Button`; buttons should use `.openClawPress`.
    func openClawPressFeedback() -> some View {
        modifier(OpenClawPressFeedbackModifier())
    }
}
