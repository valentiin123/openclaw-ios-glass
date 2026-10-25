import Observation
import OpenClawChatUI
import SwiftUI
import UIKit

// Tile -> full screen "zoom" for the subagent chat (Agents tab).
//
// The tapped tile's rectangle (measured in global coordinates) grows to the full screen: its four
// corners travel to the four screen corners at the same time, corner radius going to 0. Plain
// ease-out, no spring, no bounce. Closing plays exactly the same interpolation backwards, also
// ease-out. The chat content fades in from 60 % of the animation (and out symmetrically).
// Reduce Motion (or no measured tile): short cross-fade only.
//
// Host: a full-screen cover with a clear background, presented WITHOUT the system animation
// (`Transaction.disablesAnimations`). The cover hides the tab bar, so the composer keeps sitting on
// the keyboard. The frame animation is driven by an `Animatable` modifier, so every frame is computed
// from the eased progress; the chat itself is always laid out at full screen size (never re-laid out
// during the animation), only masked.
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Tile frames

/// Latest global frame of every visible tile. Reference type, deliberately not observable:
/// updating it while scrolling must not re-render the board. Only touched from the main thread
/// (geometry callbacks and tap handlers), hence not actor-isolated (keeps the callbacks simple).
final class AgentTileFrameStore: @unchecked Sendable {
    private var frames: [String: CGRect] = [:]

    func set(_ frame: CGRect, for key: String) {
        self.frames[key] = frame
    }

    func frame(for key: String) -> CGRect? {
        self.frames[key]
    }
}

// MARK: - Motion

enum SubagentChatZoomMotion {
    /// Zoom duration (open and close).
    static let duration: TimeInterval = 0.35
    /// Cross-fade when no tile frame is known.
    static let fadeDuration: TimeInterval = 0.2
    /// Cross-fade under Reduce Motion.
    static let reducedDuration: TimeInterval = 0.12
    /// Chat content is invisible until this fraction of the animation.
    static let contentStart: CGFloat = 0.6
    /// The growing surface reaches full opacity at this fraction (hides the pop of the tile content).
    static let surfaceRamp: CGFloat = 0.2
    /// Corner radius of the tile (`AgentTileView.radius`).
    static let sourceRadius: CGFloat = OpenClawRadius.md

    static func animation(duration: TimeInterval) -> Animation {
        Animation.easeOut(duration: duration)
    }
}

// MARK: - Geometry

enum SubagentZoomGeometry {
    static func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }

    static func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    /// Each corner moves linearly from the tile corner to the matching screen corner.
    static func rect(progress: CGFloat, from source: CGRect, to target: CGRect) -> CGRect {
        let t: CGFloat = self.clamp(progress)
        let minX: CGFloat = self.lerp(source.minX, target.minX, t)
        let minY: CGFloat = self.lerp(source.minY, target.minY, t)
        let maxX: CGFloat = self.lerp(source.maxX, target.maxX, t)
        let maxY: CGFloat = self.lerp(source.maxY, target.maxY, t)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    static func radius(progress: CGFloat) -> CGFloat {
        let t: CGFloat = self.clamp(progress)
        return self.lerp(SubagentChatZoomMotion.sourceRadius, 0, t)
    }

    static func contentOpacity(progress: CGFloat) -> Double {
        let t: CGFloat = self.clamp(progress)
        let start: CGFloat = SubagentChatZoomMotion.contentStart
        if t <= start { return 0 }
        return Double((t - start) / (1 - start))
    }

    static func surfaceOpacity(progress: CGFloat) -> Double {
        let t: CGFloat = self.clamp(progress)
        let ramp: CGFloat = SubagentChatZoomMotion.surfaceRamp
        return Double(min(1, t / ramp))
    }
}

// MARK: - Mode

enum SubagentZoomMode: Equatable {
    case fade
    case zoom(CGRect)
}

// MARK: - Layer

/// A rounded rectangle at the interpolated frame, drawn in screen space. Used both as the mask of
/// the chat and as the growing tile-colored surface behind it. The layer reads its own global
/// origin, so it does not depend on safe areas.
private struct SubagentZoomRectLayer: View {
    let progress: CGFloat
    let source: CGRect
    let fill: Color

    var body: some View {
        GeometryReader { proxy in
            self.shape(in: proxy.frame(in: .global))
        }
        .ignoresSafeArea()
    }

    private func shape(in screen: CGRect) -> some View {
        let rect: CGRect = SubagentZoomGeometry.rect(progress: self.progress, from: self.source, to: screen)
        let radius: CGFloat = SubagentZoomGeometry.radius(progress: self.progress)
        let dx: CGFloat = rect.minX - screen.minX
        let dy: CGFloat = rect.minY - screen.minY
        return RoundedRectangle(cornerRadius: radius, style: .circular)
            .fill(self.fill)
            .frame(width: rect.width, height: rect.height)
            .offset(x: dx, y: dy)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Modifier

/// `progress` is animatable: SwiftUI calls `body` with the eased value on every frame.
private struct SubagentZoomModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let mode: SubagentZoomMode

    var animatableData: CGFloat {
        get { self.progress }
        set { self.progress = newValue }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch self.mode {
        case .fade:
            content.opacity(Double(self.progress))
        case let .zoom(source):
            self.zoomed(content, source: source)
        }
    }

    private func zoomed(_ content: Content, source: CGRect) -> some View {
        let opacity: Double = SubagentZoomGeometry.contentOpacity(progress: self.progress)
        let surfaceOpacity: Double = SubagentZoomGeometry.surfaceOpacity(progress: self.progress)
        let surfaceColor: Color = Color(uiColor: .secondarySystemGroupedBackground)
        let mask: SubagentZoomRectLayer = SubagentZoomRectLayer(
            progress: self.progress,
            source: source,
            fill: Color.black)
        let surface: SubagentZoomRectLayer = SubagentZoomRectLayer(
            progress: self.progress,
            source: source,
            fill: surfaceColor)
        return content
            .opacity(opacity)
            .mask(mask)
            .background(surface.opacity(surfaceOpacity))
    }
}

// MARK: - Model

@MainActor
@Observable
final class SubagentZoomModel {
    enum Phase: Equatable {
        case opening
        case open
        case closing
    }

    var progress: CGFloat = 0
    var phase: Phase = .opening

    func open(animation: Animation) {
        guard self.phase == .opening, self.progress == 0 else { return }
        withAnimation(
            animation,
            completionCriteria: .logicallyComplete,
            { self.progress = 1 },
            completion: { Task { @MainActor in self.markOpen() } })
    }

    func close(animation: Animation, onClosed: @escaping @MainActor () -> Void) {
        guard self.phase != .closing else { return }
        self.phase = .closing
        Self.endEditing()
        withAnimation(
            animation,
            completionCriteria: .logicallyComplete,
            { self.progress = 0 },
            completion: { Task { @MainActor in onClosed() } })
    }

    private func markOpen() {
        if self.phase == .opening { self.phase = .open }
    }

    private static func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil)
    }
}

// MARK: - Cover

/// Content of the full-screen cover: the existing `SubagentChatCover`, wrapped in the zoom effect.
/// The root screen's Close / pull-to-dismiss go through `closeRoot` (reverse animation) instead of
/// the system dismissal; pushed children keep the NavigationStack pop and edge swipe-back.
struct SubagentChatZoomCover: View {
    let request: SubagentChatRequest
    let onFinished: @MainActor () -> Void

    @State private var model: SubagentZoomModel = SubagentZoomModel()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mode: SubagentZoomMode {
        if self.reduceMotion { return .fade }
        guard let rect = self.request.sourceRect else { return .fade }
        if rect.width < 1 || rect.height < 1 { return .fade }
        return .zoom(rect)
    }

    private var duration: TimeInterval {
        if self.reduceMotion { return SubagentChatZoomMotion.reducedDuration }
        switch self.mode {
        case .fade: return SubagentChatZoomMotion.fadeDuration
        case .zoom: return SubagentChatZoomMotion.duration
        }
    }

    private var animation: Animation {
        SubagentChatZoomMotion.animation(duration: self.duration)
    }

    private var closeHandler: @MainActor () -> Void {
        let model: SubagentZoomModel = self.model
        let animation: Animation = self.animation
        let finished: @MainActor () -> Void = self.onFinished
        let handler: @MainActor () -> Void = {
            model.close(animation: animation, onClosed: finished)
        }
        return handler
    }

    var body: some View {
        let effect: SubagentZoomModifier = SubagentZoomModifier(progress: self.model.progress, mode: self.mode)
        let interactive: Bool = self.model.phase == .open
        return SubagentChatCover(rootKey: self.request.key, onCloseRoot: self.closeHandler)
            .modifier(effect)
            .allowsHitTesting(interactive)
            .presentationBackground(.clear)
            .onAppear(perform: self.start)
    }

    private func start() {
        self.model.open(animation: self.animation)
    }
}

// MARK: - Presentation

private struct SubagentChatZoomPresentation: ViewModifier {
    @Bindable var presenter: SubagentChatPresenter

    func body(content: Content) -> some View {
        let presenter: SubagentChatPresenter = self.presenter
        let finish: @MainActor () -> Void = { presenter.finishClose() }
        return content
            .environment(\.openClawChatOpenSubagent, presenter.zoomHook)
            .fullScreenCover(item: self.$presenter.request) { request in
                SubagentChatZoomCover(request: request, onFinished: finish)
            }
    }
}

extension View {
    /// Same wiring as `subagentChatPresentation(presenter:)`, but the chat zooms out of the tapped
    /// tile (open with `presenter.open(_:from:)`) and zooms back into it on close.
    func subagentChatZoomPresentation(presenter: SubagentChatPresenter) -> some View {
        modifier(SubagentChatZoomPresentation(presenter: presenter))
    }
}
