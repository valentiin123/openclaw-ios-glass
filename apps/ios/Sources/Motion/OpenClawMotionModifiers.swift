import SwiftUI

// MARK: - Simple animations
//
// Everything here goes through `OpenClawMotion` (the single spring, or a short fade under
// Reduce Motion). The only exceptions are the two looping indicators (`shimmer`, `pulse`):
// a loop cannot be a spring, so they use one slow ease-in-out and are fully disabled
// under Reduce Motion.

extension OpenClawMotion {
    /// Duration of one cycle of the looping indicators (shimmer, pulse).
    static let loopDuration: Double = 1.4

    /// Animation used by looping indicators. Never used when Reduce Motion is on.
    static var loop: Animation {
        Animation.easeInOut(duration: OpenClawMotion.loopDuration).repeatForever(autoreverses: false)
    }

    static var pulseLoop: Animation {
        Animation.easeInOut(duration: OpenClawMotion.loopDuration).repeatForever(autoreverses: true)
    }
}

// MARK: - Shimmer

private struct OpenClawShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1
    let isActive: Bool

    private var isRunning: Bool {
        self.isActive && !self.reduceMotion
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if self.isRunning {
            content
                .overlay { self.sweepLayer(for: content) }
                .onAppear { self.start() }
        } else {
            content
        }
    }

    private func sweepLayer(for content: Content) -> some View {
        self.sweep
            .mask { content }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var sweep: some View {
        GeometryReader { proxy in
            self.band(width: proxy.size.width)
        }
    }

    private func band(width: CGFloat) -> some View {
        let colors: [Color] = [.clear, Color.white.opacity(0.4), .clear]
        let gradient = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
        let bandWidth = width * 0.6
        let travel = self.phase * width
        return gradient
            .frame(width: bandWidth)
            .offset(x: travel)
    }

    private func start() {
        self.phase = -1
        withAnimation(OpenClawMotion.loop) {
            self.phase = 1.4
        }
    }
}

// MARK: - Pulse

private struct OpenClawPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    let isActive: Bool

    private var isRunning: Bool {
        self.isActive && !self.reduceMotion
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if self.isRunning {
            content
                .opacity(self.dimmed ? 0.45 : 1)
                .onAppear { self.start() }
        } else {
            content
        }
    }

    private func start() {
        self.dimmed = false
        withAnimation(OpenClawMotion.pulseLoop) {
            self.dimmed = true
        }
    }
}

// MARK: - Appear transition

private struct OpenClawAppearTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let edge: Edge?

    func body(content: Content) -> some View {
        content.transition(self.transition)
    }

    private var transition: AnyTransition {
        if let edge = self.edge {
            return OpenClawMotion.edge(edge, reduceMotion: self.reduceMotion)
        }
        return OpenClawMotion.appear(reduceMotion: self.reduceMotion)
    }
}

// MARK: - Matched geometry

private struct OpenClawMatchedGeometryModifier<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: ID
    let namespace: Namespace.ID
    let isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if self.reduceMotion {
            // No travelling geometry under Reduce Motion: the change cross-fades in place.
            content
        } else {
            content.matchedGeometryEffect(id: self.id, in: self.namespace, isSource: self.isSource)
        }
    }
}

// MARK: - Glass morph

private struct OpenClawGlassMorphModifier<ID: Hashable & Sendable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if self.reduceMotion {
            content
        } else {
            content.glassEffectID(self.id, in: self.namespace)
        }
    }
}

// MARK: - Public API

extension View {
    /// Light sweep for loading placeholders. Static under Reduce Motion.
    func openClawShimmer(isActive: Bool = true) -> some View {
        modifier(OpenClawShimmerModifier(isActive: isActive))
    }

    /// Slow opacity pulse for "live" indicators. Static under Reduce Motion.
    func openClawPulse(isActive: Bool = true) -> some View {
        modifier(OpenClawPulseModifier(isActive: isActive))
    }

    /// Insert/remove transition: fade + small scale, or fade only under Reduce Motion.
    /// Pass an edge for banners and toasts that slide in from a screen edge.
    func openClawAppearTransition(from edge: Edge? = nil) -> some View {
        modifier(OpenClawAppearTransitionModifier(edge: edge))
    }

    /// Matched geometry transition between two views sharing `id` in `namespace`.
    /// Drive the change with `OpenClawMotion.perform` so the shared spring is used.
    /// Disabled under Reduce Motion.
    func openClawMatchedGeometry(
        id: some Hashable,
        in namespace: Namespace.ID,
        isSource: Bool = true) -> some View
    {
        modifier(OpenClawMatchedGeometryModifier(id: id, namespace: namespace, isSource: isSource))
    }

    /// Morph between glass shapes of one `GlassEffectContainer` (iOS 26). Disabled under Reduce Motion.
    func openClawGlassMorph(
        id: some Hashable & Sendable,
        in namespace: Namespace.ID) -> some View
    {
        modifier(OpenClawGlassMorphModifier(id: id, namespace: namespace))
    }
}
