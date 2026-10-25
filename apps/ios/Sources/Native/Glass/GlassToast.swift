import Observation
import SwiftUI

// Transient confirmation ("Copied") shown as ONE glass capsule floating above the bottom edge.
// Glass is appropriate here: the toast is chrome, not reading content. It uses the shared spring
// (cross-fade under Reduce Motion), posts a VoiceOver announcement and a success haptic.

/// Holds the message currently shown. Create one per page and inject it with `.environment(_:)`.
@MainActor
@Observable
final class GlassToastModel {
    private(set) var message: String?
    /// Increments on every `show`, so the haptic fires even when the same text is shown twice.
    private(set) var token: Int = 0
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    static let visibleDuration: Duration = .milliseconds(1600)

    func show(_ message: String) {
        self.message = message
        self.token &+= 1
        self.dismissTask?.cancel()
        let duration: Duration = Self.visibleDuration
        self.dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
        AccessibilityNotification.Announcement(message).post()
    }

    func dismiss() {
        self.dismissTask?.cancel()
        self.dismissTask = nil
        self.message = nil
    }
}

private struct GlassToastHost: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: GlassToastModel

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                self.toast
            }
            .openClawAnimation(value: self.model.message)
            .sensoryFeedback(.success, trigger: self.model.token)
    }

    @ViewBuilder
    private var toast: some View {
        if let message = self.model.message {
            Label {
                Text(verbatim: message)
                    .font(OpenClawType.subheadSemiBold)
            } icon: {
                Image(systemName: "checkmark")
                    .font(OpenClawType.subheadSemiBold)
            }
            .padding(.horizontal, OpenClawSpace.lg)
            .padding(.vertical, OpenClawSpace.md)
            .openClawGlassCapsule()
            .padding(.bottom, OpenClawSpace.xl)
            .transition(OpenClawMotion.edge(.bottom, reduceMotion: self.reduceMotion))
            .allowsHitTesting(false)
            // The announcement posted by the model already reaches VoiceOver.
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Overlays the toast for `model` at the bottom of the view.
    func glassToastHost(_ model: GlassToastModel) -> some View {
        modifier(GlassToastHost(model: model))
    }
}
