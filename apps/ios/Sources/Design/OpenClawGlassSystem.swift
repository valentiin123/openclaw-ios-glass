import SwiftUI

// MARK: - Motion tokens

/// Single motion vocabulary for the app. Every animation in design components goes
/// through `spring` (or `reducedFade` when Reduce Motion is on) so the app feels uniform.
enum OpenClawMotion {
    /// The one shared spring. Short, critically-damped feel, no visible overshoot.
    static let spring: Animation = .spring(response: 0.32, dampingFraction: 0.86)
    /// Replacement for `spring` when Reduce Motion is enabled: a brief cross-fade.
    static let reducedFade: Animation = .easeOut(duration: 0.12)

    /// Stagger step used by entrance choreography.
    static let staggerStep: Double = 0.04
    /// Vertical travel of an entrance, in points.
    static let entranceOffset: CGFloat = 8
    /// Scale used by press feedback and appear transitions.
    static let pressedScale: CGFloat = 0.97
    static let appearScale: CGFloat = 0.96

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? self.reducedFade : self.spring
    }

    /// Insert/remove transition. Opacity only under Reduce Motion.
    static func appear(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: self.appearScale))
    }

    /// Slide-from-edge transition for banners and toasts.
    static func edge(_ edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: edge))
    }

    /// `withAnimation` using the shared spring, honoring Reduce Motion.
    @MainActor
    static func perform(reduceMotion: Bool, _ body: () -> Void) {
        withAnimation(self.animation(reduceMotion: reduceMotion)) {
            body()
        }
    }
}

private struct OpenClawAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(OpenClawMotion.animation(reduceMotion: self.reduceMotion), value: self.value)
    }
}

private struct OpenClawEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    let index: Int
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if self.enabled {
            content
                .opacity(self.shown ? 1 : 0)
                .offset(y: (self.shown || self.reduceMotion) ? 0 : OpenClawMotion.entranceOffset)
                .onAppear {
                    guard !self.shown else { return }
                    let base = OpenClawMotion.animation(reduceMotion: self.reduceMotion)
                    let animation = self.reduceMotion
                        ? base
                        : base.delay(Double(self.index) * OpenClawMotion.staggerStep)
                    withAnimation(animation) {
                        self.shown = true
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Glass helpers

enum OpenClawGlassStyle {
    @available(iOS 26.0, *)
    static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

extension View {
    /// Shared animation driven by the single spring; cross-fades under Reduce Motion.
    func openClawAnimation(value: some Equatable) -> some View {
        modifier(OpenClawAnimationModifier(value: value))
    }

    /// Short staggered entrance (fade + 8pt rise). Pass the row position as `index`.
    func openClawEntrance(index: Int = 0, enabled: Bool = true) -> some View {
        modifier(OpenClawEntranceModifier(index: index, enabled: enabled))
    }

    /// Liquid Glass for navigation chrome and controls only (bars, floating controls, pickers).
    /// Falls back to a thin material on earlier systems. Never use behind reading content.
    @ViewBuilder
    func openClawGlass(
        in shape: some Shape,
        tint: Color? = nil,
        interactive: Bool = false) -> some View
    {
        if #available(iOS 26.0, *) {
            self.glassEffect(OpenClawGlassStyle.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Capsule-shaped glass chrome, the default for floating controls.
    func openClawGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        self.openClawGlass(in: Capsule(), tint: tint, interactive: interactive)
    }
}

// MARK: - Press feedback

/// Plain button style with a short press scale. For custom (non-glass) tappable content.
struct OpenClawPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: ButtonStyleConfiguration

        var body: some View {
            self.configuration.label
                .scaleEffect(self.configuration.isPressed && !self.reduceMotion ? OpenClawMotion.pressedScale : 1)
                .opacity(self.configuration.isPressed ? 0.85 : 1)
                .animation(
                    OpenClawMotion.animation(reduceMotion: self.reduceMotion),
                    value: self.configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == OpenClawPressButtonStyle {
    static var openClawPress: OpenClawPressButtonStyle {
        OpenClawPressButtonStyle()
    }
}

// MARK: - Glass card (quiet content surface)

/// Sober content grouping that sits next to Liquid Glass chrome. It is an opaque
/// surface by design (see DESIGN-GLASS.md): glass is reserved for navigation and controls.
struct OpenClawGlassCard<Content: View>: View {
    var tint: Color?
    var padding: CGFloat = 16
    var radius: CGFloat = OpenClawProMetric.cardRadius
    var entranceIndex: Int?
    @ViewBuilder var content: Content

    var body: some View {
        self.content
            .padding(self.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .proPanelSurface(tint: self.tint, radius: self.radius, isProminent: false)
            .openClawEntrance(index: self.entranceIndex ?? 0, enabled: self.entranceIndex != nil)
    }
}

// MARK: - Segmented control

/// Glass segmented control. The selected segment is a glass capsule that morphs
/// between options through `glassEffectID` on the shared spring.
struct OpenClawGlassSegmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: OpenClawTextValue
        var systemImage: String?

        var id: Value {
            self.value
        }

        init(_ value: Value, title: OpenClawTextValue, systemImage: String? = nil) {
            self.value = value
            self.title = title
            self.systemImage = systemImage
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @Binding var selection: Value
    let options: [Option]

    var body: some View {
        OpenClawGlassControlGroup {
            HStack(spacing: 4) {
                ForEach(self.options) { option in
                    self.segment(option)
                }
            }
            .padding(4)
            .background {
                Capsule().fill(Color(uiColor: .tertiarySystemFill))
            }
        }
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == self.selection
        return Button {
            guard !isSelected else { return }
            OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
                self.selection = option.value
            }
        } label: {
            HStack(spacing: 6) {
                if let systemImage = option.systemImage {
                    Image(systemName: systemImage)
                        .font(OpenClawType.captionSemiBold)
                }
                option.title.text
                    .font(OpenClawType.subheadSemiBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Capsule())
            .background {
                if isSelected {
                    OpenClawGlassSelectionBackground(namespace: self.selectionNamespace)
                }
            }
        }
        .font(OpenClawType.subheadSemiBold)
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OpenClawGlassSelectionBackground: View {
    let namespace: Namespace.ID

    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    OpenClawGlassStyle.glass(tint: OpenClawBrand.accent.opacity(0.16), interactive: true),
                    in: Capsule())
                .glassEffectID("openclaw.segmented.selection", in: self.namespace)
        } else {
            Capsule().fill(.thinMaterial)
        }
    }
}

// MARK: - Empty state

/// Animated empty state: icon, title, message and optional actions rise in with a short stagger.
struct OpenClawEmptyState<Actions: View>: View {
    let systemImage: String
    let title: OpenClawTextValue
    var message: OpenClawTextValue?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: self.systemImage)
                .font(OpenClawType.title2SemiBold)
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background {
                    Circle().fill(Color(uiColor: .tertiarySystemFill))
                }
                .accessibilityHidden(true)
                .openClawEntrance(index: 0)

            self.title.text
                .font(OpenClawType.headline)
                .multilineTextAlignment(.center)
                .openClawEntrance(index: 1)

            if let message {
                message.text
                    .font(OpenClawType.subhead)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .openClawEntrance(index: 2)
            }

            self.actions
                .openClawEntrance(index: 3)
        }
        .padding(OpenClawProMetric.pagePadding)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension OpenClawEmptyState where Actions == EmptyView {
    init(systemImage: String, title: OpenClawTextValue, message: OpenClawTextValue? = nil) {
        self.init(systemImage: systemImage, title: title, message: message) {
            EmptyView()
        }
    }
}

// MARK: - Status pill

/// Quiet capsule status indicator. No glow and no glass; color carries the semantics.
struct OpenClawStatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: OpenClawTextValue
    let tone: OpenClawStatusTone
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(OpenClawType.caption2SemiBold)
            } else {
                Circle()
                    .fill(self.tone.color)
                    .frame(width: 7, height: 7)
            }
            self.label.text
                .font(OpenClawType.caption2SemiBold)
        }
        .foregroundStyle(self.tone.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(self.tone.color.opacity(self.colorScheme == .dark ? 0.16 : 0.10))
        }
        .accessibilityElement(children: .combine)
        .openClawAnimation(value: self.tone)
    }
}
