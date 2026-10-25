import SwiftUI

/// Single motion vocabulary for the chat UI. Mirrors the app's `OpenClawMotion`
/// (same spring values) because this package cannot import the app target.
/// Every chat animation goes through `spring`, or `reducedFade` under Reduce Motion.
enum OpenClawChatMotion {
    static let spring: Animation = .spring(response: 0.32, dampingFraction: 0.86)
    static let reducedFade: Animation = .easeOut(duration: 0.12)

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? self.reducedFade : self.spring
    }

    /// `withAnimation` using the shared spring, honoring Reduce Motion.
    @MainActor
    static func perform(reduceMotion: Bool, _ body: () -> Void) {
        withAnimation(self.animation(reduceMotion: reduceMotion)) {
            body()
        }
    }
}

/// Tinted Liquid Glass shape for the primary composer action (send/stop), drawn as a background.
/// Solid tint fill before iOS 26 and on macOS. Chrome only, never behind reading content.
struct OpenClawChatGlassFill: View {
    let tint: Color
    let size: CGFloat
    let cornerRadius: CGFloat

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Color.clear
                .frame(width: self.size, height: self.size)
                .glassEffect(Glass.regular.tint(self.tint), in: .rect(cornerRadius: self.cornerRadius))
        } else {
            self.solid
        }
        #else
        self.solid
        #endif
    }

    private var solid: some View {
        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
            .fill(self.tint)
            .frame(width: self.size, height: self.size)
    }
}

private struct OpenClawChatAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(OpenClawChatMotion.animation(reduceMotion: self.reduceMotion), value: self.value)
    }
}

extension View {
    /// Shared chat animation (single spring, cross-fade under Reduce Motion).
    func openClawChatAnimation(value: some Equatable) -> some View {
        modifier(OpenClawChatAnimationModifier(value: value))
    }

    /// Liquid Glass for chat chrome and controls only (header, composer, buttons).
    /// Thin material before iOS 26 and on macOS. Never use behind reading content.
    @ViewBuilder
    func openClawChatGlass(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(
                interactive ? Glass.regular.interactive() : Glass.regular,
                in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }
}
