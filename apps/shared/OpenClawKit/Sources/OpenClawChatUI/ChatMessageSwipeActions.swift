import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Simple message gestures for iOS: drag right to reply, drag left to copy.
/// The long-press menu stays the single place for everything else.
///
/// - Only a horizontal-dominant drag is handled, so vertical scrolling is untouched.
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

    private var progress: Double {
        min(1, Double(abs(self.offset) / Self.activationDistance))
    }

    func body(content: Content) -> some View {
        content
            .offset(x: self.reduceMotion ? 0 : self.offset)
            .background(alignment: self.offset >= 0 ? .leading : .trailing) {
                self.hint
            }
            .simultaneousGesture(self.drag)
    }

    @ViewBuilder
    private var hint: some View {
        if self.offset != 0 {
            Image(systemName: self.offset > 0 ? "arrowshape.turn.up.left" : "doc.on.doc")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(self.progress)
                .scaleEffect(self.armed ? 1.1 : 0.9)
                .padding(.horizontal, 12)
                .accessibilityHidden(true)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Leave vertical drags to the scroll view.
                guard abs(dx) > abs(dy) * 1.5 else {
                    if self.offset != 0 { self.reset() }
                    return
                }
                guard let direction = self.allowedDirection(for: dx) else { return }
                let travel = min(Self.maximumTravel, abs(dx) * 0.6)
                let newOffset = direction * travel
                let isArmed = travel >= Self.activationDistance * 0.6 + 1
                if isArmed != self.armed {
                    self.armed = isArmed
                    if isArmed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                }
                OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
                    self.offset = newOffset
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let fire = self.armed && abs(dx) > abs(dy) * 1.5
                let action = fire ? self.action(for: dx) : nil
                self.reset()
                action?()
            }
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
#endif
