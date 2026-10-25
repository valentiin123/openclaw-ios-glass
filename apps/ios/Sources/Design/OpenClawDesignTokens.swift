import SwiftUI

// MARK: - Design tokens (additive)
//
// Complements OpenClawSpace / OpenClawMotion / OpenClawHitTarget (OpenClawGlassSystem.swift)
// and OpenClawRadius / OpenClawProMetric (OpenClawProComponents.swift). Nothing here renames
// or replaces an existing token. Rule of thumb for the whole app:
//   - glass: navigation and controls only (bars, floating buttons, chips, pickers);
//   - content: opaque, discreet surfaces (`proPanelSurface`, `openClawCraftSurface`).

extension OpenClawRadius {
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    /// Opaque content card (matches `OpenClawProMetric.cardRadius`).
    static let card: CGFloat = OpenClawProMetric.cardRadius
    /// Large grouped panel, e.g. onboarding panels.
    static let panel: CGFloat = 20
    /// Sheet corner radius.
    static let sheet: CGFloat = 28
}

/// Semantic colors. Thin aliases over `OpenClawBrand` so call sites read by role, not by hue.
enum OpenClawColor {
    static let accent = OpenClawBrand.accent
    static let accentFill = OpenClawBrand.accentFill
    static let canvas = OpenClawBrand.void
    static let surface = OpenClawBrand.surfaceCard
    static let surfaceRaised = OpenClawBrand.surfaceElevated
    static let surfaceInset = OpenClawBrand.surfacePanel
    static let border = OpenClawBrand.hairlineBorder
    static let borderStrong = OpenClawBrand.hairlineBorderStrong
    static let textPrimary = OpenClawBrand.textPrimary
    static let textStrong = OpenClawBrand.textStrong
    static let textMuted = OpenClawBrand.textSecondary
    static let success = OpenClawBrand.ok
    static let warning = OpenClawBrand.warn
    static let danger = OpenClawBrand.danger
    static let info = OpenClawBrand.info
}

// MARK: - Haptics

/// Haptic vocabulary. One place decides which feedback goes with which kind of event.
enum OpenClawHaptic: Sendable {
    case selection
    case light
    case medium
    case success
    case warning
    case error

    var feedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .light: .impact(weight: .light)
        case .medium: .impact(weight: .medium)
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }
}

extension View {
    /// Plays `haptic` whenever `trigger` changes.
    func openClawHaptic(_ haptic: OpenClawHaptic, trigger: some Equatable) -> some View {
        self.sensoryFeedback(haptic.feedback, trigger: trigger)
    }
}

// MARK: - Sheets

extension View {
    /// Shared sheet presentation: visible grab handle, large corner radius, opaque content
    /// background (glass stays on the navigation chrome and controls, not behind content).
    func openClawSheetPresentation(
        detents: Set<PresentationDetent> = [.medium, .large],
        interactiveDismissDisabled: Bool = false) -> some View
    {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(OpenClawRadius.sheet)
            .presentationBackground(OpenClawColor.canvas)
            .interactiveDismissDisabled(interactiveDismissDisabled)
    }
}

// MARK: - Bottom action bar

/// Floating glass bar pinned to the bottom safe area (primary actions, composer-like controls).
/// Content scrolls underneath, the bar itself is the only glass surface.
private struct OpenClawBottomBarModifier<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            GlassEffectContainer(spacing: OpenClawGlassMetric.containerSpacing) {
                self.bar
                    .padding(.horizontal, OpenClawSpace.lg)
                    .padding(.vertical, OpenClawSpace.sm)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular, in: RoundedRectangle(
                        cornerRadius: OpenClawRadius.panel,
                        style: .continuous))
            }
            .padding(.horizontal, OpenClawSpace.lg)
            .padding(.bottom, OpenClawSpace.sm)
        }
    }
}

extension View {
    func openClawBottomBar(@ViewBuilder _ bar: () -> some View) -> some View {
        modifier(OpenClawBottomBarModifier(bar: bar()))
    }
}

// MARK: - Badges

/// Compact opaque count badge (unread, pending approvals). Not glass: it sits on content.
struct OpenClawCountBadge: View {
    let count: Int
    var tint: Color = OpenClawColor.accentFill
    var maximum: Int = 99

    var body: some View {
        Text(verbatim: self.display)
            .font(OpenClawType.caption2SemiBold)
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, OpenClawSpace.sm - 1)
            .padding(.vertical, OpenClawSpace.xs - 1)
            .frame(minWidth: 20)
            .background(self.tint, in: Capsule())
            .accessibilityLabel(Text(verbatim: String(self.count)))
            .contentTransition(.numericText())
            .openClawAnimation(value: self.count)
    }

    private var display: String {
        self.count > self.maximum ? "\(self.maximum)+" : String(self.count)
    }
}

// MARK: - Section header

/// Quiet section title for content screens. Marked as a header for VoiceOver rotor navigation.
struct OpenClawSectionHeader<Trailing: View>: View {
    let title: OpenClawTextValue
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            self.title.text
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: OpenClawSpace.sm)
            self.trailing
        }
    }
}

extension OpenClawSectionHeader where Trailing == EmptyView {
    init(_ title: OpenClawTextValue) {
        self.init(title: title) {
            EmptyView()
        }
    }
}

// MARK: - Pull to dismiss

private enum OpenClawPullDismissMetric {
    static let grabZone: CGFloat = 140
    static let minimumDistance: CGFloat = 12
    static let commitDistance: CGFloat = 110
    static let resistance: CGFloat = 0.55
    static let dominance: CGFloat = 1.5
}

private struct OpenClawPullToDismissModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pull: CGFloat = 0
    @State private var committed = 0

    let isEnabled: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .offset(y: self.reduceMotion ? 0 : self.pull)
            .simultaneousGesture(self.drag, including: self.isEnabled ? .all : .subviews)
            .sensoryFeedback(.impact(weight: .light), trigger: self.committed)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: OpenClawPullDismissMetric.minimumDistance)
            .onChanged { value in
                guard self.isValid(value) else { return }
                self.pull = max(0, value.translation.height) * OpenClawPullDismissMetric.resistance
            }
            .onEnded { value in
                let shouldCommit = self.isValid(value)
                    && value.translation.height >= OpenClawPullDismissMetric.commitDistance
                if shouldCommit {
                    self.committed += 1
                    self.onDismiss()
                }
                OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
                    self.pull = 0
                }
            }
    }

    private func isValid(_ value: DragGesture.Value) -> Bool {
        guard value.startLocation.y <= OpenClawPullDismissMetric.grabZone else { return false }
        let dy = value.translation.height
        let dx = abs(value.translation.width)
        return dy > 0 && dy > dx * OpenClawPullDismissMetric.dominance
    }
}

extension View {
    /// Downward drag from the top zone dismisses the host. A visible close button must remain
    /// the primary path; this gesture is only a shortcut.
    func openClawPullToDismiss(isEnabled: Bool = true, onDismiss: @escaping () -> Void) -> some View {
        modifier(OpenClawPullToDismissModifier(isEnabled: isEnabled, onDismiss: onDismiss))
    }
}
