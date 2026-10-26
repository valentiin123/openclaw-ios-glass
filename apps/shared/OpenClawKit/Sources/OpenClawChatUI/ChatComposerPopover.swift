import SwiftUI

#if os(iOS)
import UIKit

// Composer popovers (+, permissions, context, model, thinking).
// Cards are Liquid Glass (iOS 26) or thin material tinted with the chat palette, with generous corners
// and a soft accent rim. They grow out of the control that presented them with a real spring
// (scale + fade + light blur), their rows appear one after the other, and they close with a quicker,
// tighter spring. The thinking bar has no card at all: only the bar floats over a progressive blur.
// Reduce Motion replaces every movement with a short fade. Taps outside close the popover through a
// transparent scrim; nothing here ever resigns the first responder, so the keyboard stays open.

enum ChatPopoverMetrics {
    static let cornerRadius: CGFloat = 20
    static let width: CGFloat = 264
    static let wideWidth: CGFloat = 304
    static let rowHeight: CGFloat = 50
    static let rowInset: CGFloat = 16
    static let rowGutter: CGFloat = 8
    static let rowCornerRadius: CGFloat = 14
    static let screenMargin: CGFloat = 14
    static let anchorGap: CGFloat = 10
    static let barGap: CGFloat = 20
    static let barInset: CGFloat = 16
    static let hiddenScale: CGFloat = 0.4
    static let closeDelayMilliseconds: Int = 230
    static let afterCloseDelayMilliseconds: Int = 120
    static let openingMilliseconds: Int = 700
    static let blurStartRadius: CGFloat = 90
    static let blurEndRadius: CGFloat = 520
    static let minimumPanelHeight: CGFloat = 120
}

/// Springs of the popover vocabulary. Reduce Motion always falls back to the shared short fade.
enum ChatPopoverMotion {
    static let openSpring: Animation = .spring(response: 0.46, dampingFraction: 0.74)
    static let closeSpring: Animation = .spring(response: 0.30, dampingFraction: 0.94)
    static let selectSpring: Animation = .spring(response: 0.34, dampingFraction: 0.80)
    static let revealSpring: Animation = .spring(response: 0.42, dampingFraction: 0.82)
    static let pressSpring: Animation = .spring(response: 0.24, dampingFraction: 0.68)
    static let thumbSpring: Animation = .spring(response: 0.38, dampingFraction: 0.68)

    static func opening(reduceMotion: Bool) -> Animation {
        reduceMotion ? OpenClawChatMotion.reducedFade : self.openSpring
    }

    static func closing(reduceMotion: Bool) -> Animation {
        reduceMotion ? OpenClawChatMotion.reducedFade : self.closeSpring
    }

    static func selecting(reduceMotion: Bool) -> Animation {
        reduceMotion ? OpenClawChatMotion.reducedFade : self.selectSpring
    }

    static func revealing(reduceMotion: Bool) -> Animation {
        reduceMotion ? OpenClawChatMotion.reducedFade : self.revealSpring
    }

    static func thumb(reduceMotion: Bool) -> Animation {
        reduceMotion ? OpenClawChatMotion.reducedFade : self.thumbSpring
    }
}

/// Light haptics for the popovers. Feedback generators never touch the responder chain.
@MainActor
enum ChatPopoverHaptics {
    static func opened() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selected() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

enum ChatPopoverTransaction {
    /// The system cover slide is replaced by our own scale + fade, so presenting and dismissing skip it.
    static var instant: Transaction {
        var transaction: Transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return transaction
    }

    @MainActor
    static func present(_ isPresented: Binding<Bool>) {
        withTransaction(Self.instant) {
            isPresented.wrappedValue = true
        }
    }
}

struct ChatPopoverDismissAction {
    let handler: @MainActor (_ afterClose: (@MainActor () -> Void)?) -> Void

    @MainActor
    func callAsFunction(then afterClose: (@MainActor () -> Void)? = nil) {
        self.handler(afterClose)
    }
}

private struct ChatPopoverDismissKey: EnvironmentKey {
    static var defaultValue: ChatPopoverDismissAction {
        ChatPopoverDismissAction(handler: { _ in })
    }
}

/// Hands out the entrance delay of each row while the popover is opening, so rows appear one by one.
@MainActor
final class ChatPopoverReveal {
    private var nextIndex: Int = 0
    var isOpening: Bool = true

    /// Seconds to wait before this row appears. Zero once the opening phase is over.
    func claimDelay() -> Double {
        guard self.isOpening else { return 0 }
        let index: Int = self.nextIndex
        self.nextIndex += 1
        return 0.07 + min(Double(index) * 0.035, 0.32)
    }
}

private struct ChatPopoverRevealKey: EnvironmentKey {
    static let defaultValue: ChatPopoverReveal? = nil
}

private struct ChatPopoverSelectionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var chatPopoverDismiss: ChatPopoverDismissAction {
        get { self[ChatPopoverDismissKey.self] }
        set { self[ChatPopoverDismissKey.self] = newValue }
    }

    var chatPopoverReveal: ChatPopoverReveal? {
        get { self[ChatPopoverRevealKey.self] }
        set { self[ChatPopoverRevealKey.self] = newValue }
    }

    var chatPopoverSelectionNamespace: Namespace.ID? {
        get { self[ChatPopoverSelectionNamespaceKey.self] }
        set { self[ChatPopoverSelectionNamespaceKey.self] = newValue }
    }
}

/// Staggered entrance for a row: fades and rises a few points after the popover started opening.
struct ChatPopoverStagger: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chatPopoverReveal) private var reveal
    @State private var revealed: Bool = false

    func body(content: Content) -> some View {
        let isOpening: Bool = self.reveal?.isOpening ?? false
        let hidden: Bool = !self.revealed && !self.reduceMotion && isOpening
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden ? 12 : 0)
            .scaleEffect(hidden ? 0.96 : 1, anchor: .leading)
            .onAppear {
                guard !self.revealed else { return }
                guard let reveal = self.reveal, !self.reduceMotion else {
                    self.revealed = true
                    return
                }
                let delay: Double = reveal.claimDelay()
                if delay <= 0 {
                    self.revealed = true
                } else {
                    withAnimation(ChatPopoverMotion.revealSpring.delay(delay)) {
                        self.revealed = true
                    }
                }
            }
    }
}

// MARK: - Chrome

/// Card surface: opaque palette fill (same family as the composer bar), hairline rim with a faint
/// accent glow at the top, soft shadow. Liquid Glass is kept for the small controls inside, not the card.
struct ChatPopoverSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ChatPopoverMetrics.cornerRadius,
            style: .continuous)
        let rim: LinearGradient = LinearGradient(
            colors: [
                OpenClawChatTheme.brandAccent.opacity(0.30),
                OpenClawChatTheme.hairline,
                OpenClawChatTheme.hairline.opacity(0.6),
            ],
            startPoint: .top,
            endPoint: .bottom)
        return content
            .background { shape.fill(OpenClawChatTheme.surfaceRaised) }
            .clipShape(shape)
            .overlay(shape.strokeBorder(rim, lineWidth: 1).allowsHitTesting(false))
            .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 10)
    }
}

/// Card: glass surface. Floating bar: no surface at all, the controls float on the progressive blur.
struct ChatPopoverChrome: ViewModifier {
    let style: ChatPopoverStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch self.style {
        case .card:
            content.modifier(ChatPopoverSurface())
        case .floatingBar:
            content
        }
    }
}

// MARK: - Layout

private struct ChatPopoverLayout {
    let width: CGFloat
    let originX: CGFloat
    let opensUpward: Bool
    let edgeOffset: CGFloat
    let maxHeight: CGFloat
    let scaleAnchor: UnitPoint
    let blurCenter: UnitPoint

    static func resolve(
        anchor: CGRect,
        container: CGSize,
        safeInsets: EdgeInsets,
        width: CGFloat,
        style: ChatPopoverStyle) -> ChatPopoverLayout
    {
        let margin: CGFloat = ChatPopoverMetrics.screenMargin
        let isBar: Bool = style == .floatingBar
        let gap: CGFloat = isBar ? ChatPopoverMetrics.barGap : ChatPopoverMetrics.anchorGap
        let panelWidth: CGFloat
        let originX: CGFloat
        if isBar {
            panelWidth = max(container.width - ChatPopoverMetrics.barInset * 2, 160)
            originX = max((container.width - panelWidth) / 2, 0)
        } else {
            panelWidth = min(width, max(container.width - margin * 2, 160))
            let maxOriginX: CGFloat = max(margin, container.width - panelWidth - margin)
            originX = min(max(anchor.midX - panelWidth / 2, margin), maxOriginX)
        }
        let opensUpward: Bool = anchor.midY > container.height / 2
        let topLimit: CGFloat = safeInsets.top + margin
        let bottomLimit: CGFloat = container.height - safeInsets.bottom - margin
        let edgeOffset: CGFloat
        let available: CGFloat
        if opensUpward {
            edgeOffset = max(container.height - anchor.minY + gap, margin)
            available = anchor.minY - gap - topLimit
        } else {
            edgeOffset = max(anchor.maxY + gap, margin)
            available = bottomLimit - (anchor.maxY + gap)
        }
        let anchorX: CGFloat = panelWidth > 0 ? min(max((anchor.midX - originX) / panelWidth, 0), 1) : 0.5
        let anchorY: CGFloat = opensUpward ? 1 : 0
        let centerX: CGFloat = container.width > 0 ? anchor.midX / container.width : 0.5
        let centerY: CGFloat = container.height > 0 ? anchor.midY / container.height : 0.5
        return ChatPopoverLayout(
            width: panelWidth,
            originX: originX,
            opensUpward: opensUpward,
            edgeOffset: edgeOffset,
            maxHeight: max(available, ChatPopoverMetrics.minimumPanelHeight),
            scaleAnchor: UnitPoint(x: anchorX, y: anchorY),
            blurCenter: UnitPoint(x: centerX, y: centerY))
    }
}

// MARK: - Host

struct ChatPopoverHost<PopoverContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    let anchorFrame: CGRect
    let width: CGFloat
    let blursBackground: Bool
    let scrollsContent: Bool
    let style: ChatPopoverStyle
    let popoverContent: () -> PopoverContent
    let onClosed: @MainActor () -> Void

    @State private var isShown: Bool = false
    @State private var isClosing: Bool = false
    @State private var contentHeight: CGFloat = 0
    @State private var reveal: ChatPopoverReveal = ChatPopoverReveal()

    var body: some View {
        GeometryReader { proxy in
            let layout: ChatPopoverLayout = ChatPopoverLayout.resolve(
                anchor: self.anchorFrame,
                container: proxy.size,
                safeInsets: proxy.safeAreaInsets,
                width: self.width,
                style: self.style)
            ZStack(alignment: .topLeading) {
                self.backdrop(layout: layout)
                self.positionedPanel(layout: layout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .environment(\.chatPopoverDismiss, ChatPopoverDismissAction(handler: { afterClose in
            self.close(then: afterClose)
        }))
        .environment(\.chatPopoverReveal, self.reveal)
        .environment(\.chatPopoverSelectionNamespace, self.selectionNamespace)
        .onAppear {
            self.open()
        }
        .accessibilityAction(.escape) {
            self.close(then: nil)
        }
    }

    // MARK: Backdrop

    private func backdrop(layout: ChatPopoverLayout) -> some View {
        ZStack {
            if self.blursBackground {
                self.progressiveBlur(layout: layout)
            } else if self.style == .card {
                Color.black
                    .opacity(self.isShown ? 0.10 : 0)
                    .allowsHitTesting(false)
            }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    self.close(then: nil)
                }
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Close menu"))
                .accessibilityAddTraits(.isButton)
        }
        .ignoresSafeArea()
    }

    /// Progressive blur: three material layers masked by ellipses of decreasing reach, so the blur is
    /// strongest around the control and fades smoothly toward the rest of the screen.
    private func progressiveBlur(layout: ChatPopoverLayout) -> some View {
        let center: UnitPoint = self.style == .floatingBar
            ? UnitPoint(x: 0.5, y: layout.blurCenter.y)
            : layout.blurCenter
        return ZStack {
            self.softLayer(fill: Material.ultraThinMaterial, center: center, reach: 1.0)
            self.softLayer(fill: Material.thinMaterial, center: center, reach: 0.62)
            self.softLayer(fill: Material.regularMaterial, center: center, reach: 0.34)
            self.softLayer(fill: Color.black.opacity(0.14), center: center, reach: 0.7)
        }
        .opacity(self.isShown ? 1 : 0)
        .allowsHitTesting(false)
    }

    private func softLayer<Fill: ShapeStyle>(fill: Fill, center: UnitPoint, reach: CGFloat) -> some View {
        Rectangle()
            .fill(fill)
            .mask(
                EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color.black, location: 0),
                        Gradient.Stop(color: Color.black.opacity(0.65), location: 0.4),
                        Gradient.Stop(color: Color.black.opacity(0), location: 1),
                    ],
                    center: center,
                    startRadiusFraction: 0,
                    endRadiusFraction: reach))
    }

    // MARK: Panel

    private func positionedPanel(layout: ChatPopoverLayout) -> some View {
        let topPadding: CGFloat = layout.opensUpward ? 0 : layout.edgeOffset
        let bottomPadding: CGFloat = layout.opensUpward ? layout.edgeOffset : 0
        let alignment: Alignment = layout.opensUpward ? .bottomLeading : .topLeading
        return self.panel(layout: layout)
            .frame(width: layout.width, alignment: .leading)
            .padding(.leading, layout.originX)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var hiddenScale: CGSize {
        if self.reduceMotion { return CGSize(width: 1, height: 1) }
        switch self.style {
        case .card:
            return CGSize(width: ChatPopoverMetrics.hiddenScale, height: ChatPopoverMetrics.hiddenScale)
        case .floatingBar:
            return CGSize(width: 0.14, height: 0.4)
        }
    }

    @ViewBuilder
    private func panel(layout: ChatPopoverLayout) -> some View {
        let hidden: CGSize = self.hiddenScale
        let shown: Bool = self.isShown
        let blurRadius: CGFloat = (shown || self.reduceMotion) ? 0 : 10
        let heightAnimation: Animation? = shown
            ? ChatPopoverMotion.selecting(reduceMotion: self.reduceMotion)
            : nil
        Group {
            if self.scrollsContent {
                ScrollView(.vertical, showsIndicators: false) {
                    ChatComposerSection { self.popoverContent() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { height in
                            self.contentHeight = height
                        })
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: self.fittedHeight(maxHeight: layout.maxHeight))
                .animation(heightAnimation, value: self.contentHeight)
            } else {
                ChatComposerSection { self.popoverContent() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .modifier(ChatPopoverChrome(style: self.style))
        .scaleEffect(
            x: shown ? 1 : hidden.width,
            y: shown ? 1 : hidden.height,
            anchor: layout.scaleAnchor)
        .blur(radius: blurRadius)
        .opacity(shown ? 1 : 0)
        .accessibilityAddTraits(.isModal)
    }

    private func fittedHeight(maxHeight: CGFloat) -> CGFloat {
        guard self.contentHeight > 0 else { return maxHeight }
        return min(self.contentHeight, maxHeight)
    }

    // MARK: Lifecycle

    @MainActor
    private func open() {
        ChatPopoverHaptics.opened()
        withAnimation(ChatPopoverMotion.opening(reduceMotion: self.reduceMotion)) {
            self.isShown = true
        }
        let reveal: ChatPopoverReveal = self.reveal
        let openingDelay: Int = ChatPopoverMetrics.openingMilliseconds
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(openingDelay))
            reveal.isOpening = false
        }
    }

    @MainActor
    private func close(then afterClose: (@MainActor () -> Void)?) {
        guard !self.isClosing else { return }
        self.isClosing = true
        withAnimation(ChatPopoverMotion.closing(reduceMotion: self.reduceMotion)) {
            self.isShown = false
        }
        let closeDelay: Int = ChatPopoverMetrics.closeDelayMilliseconds
        let afterDelay: Int = ChatPopoverMetrics.afterCloseDelayMilliseconds
        let onClosed: @MainActor () -> Void = self.onClosed
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(closeDelay))
            onClosed()
            guard let afterClose else { return }
            // The cover is removed without animation, but UIKit still needs a beat before it can
            // present a sheet or picker from the same view.
            try? await Task.sleep(for: .milliseconds(afterDelay))
            afterClose()
        }
    }
}

private struct ChatPopoverPresenter<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let width: CGFloat
    let blursBackground: Bool
    let scrollsContent: Bool
    let style: ChatPopoverStyle
    let popoverContent: () -> PopoverContent

    @State private var anchorFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { frame in
                self.anchorFrame = frame
            })
            .fullScreenCover(isPresented: self.$isPresented) {
                ChatPopoverHost(
                    anchorFrame: self.anchorFrame,
                    width: self.width,
                    blursBackground: self.blursBackground,
                    scrollsContent: self.scrollsContent,
                    style: self.style,
                    popoverContent: self.popoverContent,
                    onClosed: {
                        withTransaction(ChatPopoverTransaction.instant) {
                            self.isPresented = false
                        }
                    })
                    .presentationBackground(.clear)
            }
    }
}

extension View {
    /// Presents `content` as a popover that grows out of this view.
    /// Open it with `ChatPopoverTransaction.present($isPresented)` so the system cover slide is skipped.
    func chatPopover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        width: CGFloat = ChatPopoverMetrics.width,
        blursBackground: Bool = false,
        scrollsContent: Bool = true,
        style: ChatPopoverStyle = .card,
        @ViewBuilder content: @escaping () -> PopoverContent) -> some View
    {
        self.modifier(ChatPopoverPresenter(
            isPresented: isPresented,
            width: width,
            blursBackground: blursBackground,
            scrollsContent: scrollsContent,
            style: style,
            popoverContent: content))
    }
}

// MARK: - Rows

/// Small switch drawn with the palette, used by rows that toggle a setting.
struct ChatPopoverMiniSwitch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isOn: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(self.isOn ? OpenClawChatTheme.brandAccent : OpenClawChatTheme.inkMuted.opacity(0.28))
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
                .offset(x: self.isOn ? 9 : -9)
        }
        .frame(width: 40, height: 22)
        .animation(ChatPopoverMotion.selecting(reduceMotion: self.reduceMotion), value: self.isOn)
        .accessibilityHidden(true)
    }
}

/// Tinted icon badge shared by the popover rows and disclosure headers.
struct ChatPopoverGlyph: View {
    let name: String
    let tint: Color

    var body: some View {
        Image(systemName: self.name)
            .font(.system(size: OpenClawChatTypography.scaled(14), weight: .semibold))
            .foregroundStyle(self.tint)
            .frame(width: 32, height: 32, alignment: .center)
            .background(
                self.tint.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ChatPopoverRow: View {
    /// What the row shows when `isSelected`: a check with a highlight, a highlight that slides from the
    /// previously selected row (single choice lists), or a switch (independent toggles).
    enum Indicator {
        case checkmark
        case exclusive
        case toggle
    }

    @Environment(\.chatPopoverDismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chatPopoverSelectionNamespace) private var selectionNamespace
    let title: String
    var systemImage: String?
    var tint: Color?
    var detail: String?
    var isSelected: Bool
    var indicator: Indicator
    var isEnabled: Bool
    var closesPopover: Bool
    /// Sheets and pickers must present after the popover cover is gone.
    var closesBeforeAction: Bool
    var hint: String
    let action: @MainActor () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        tint: Color? = nil,
        detail: String? = nil,
        isSelected: Bool = false,
        indicator: Indicator = .checkmark,
        isEnabled: Bool = true,
        closesPopover: Bool = true,
        closesBeforeAction: Bool = false,
        hint: String = "",
        action: @escaping @MainActor () -> Void)
    {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.detail = detail
        self.isSelected = isSelected
        self.indicator = indicator
        self.isEnabled = isEnabled
        self.closesPopover = closesPopover
        self.closesBeforeAction = closesBeforeAction
        self.hint = hint
        self.action = action
    }

    var body: some View {
        Button {
            self.perform()
        } label: {
            self.label
        }
        .buttonStyle(ChatPopoverRowButtonStyle(reduceMotion: self.reduceMotion))
        .padding(.horizontal, ChatPopoverMetrics.rowGutter)
        .modifier(ChatPopoverStagger())
        .disabled(!self.isEnabled)
        .accessibilityLabel(self.title)
        .accessibilityValue(self.isSelected ? String(localized: "Selected") : "")
        .accessibilityHint(self.hint)
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
    }

    private var accent: Color {
        self.tint ?? OpenClawChatTheme.brandAccent
    }

    private var label: some View {
        let animation: Animation = ChatPopoverMotion.selecting(reduceMotion: self.reduceMotion)
        return HStack(spacing: 12) {
            if let systemImage = self.systemImage {
                self.glyph(systemImage)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.title)
                    .font(OpenClawChatTypography.body)
                    .foregroundStyle(OpenClawChatTheme.inkStrong)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let detail = self.detail {
                    Text(verbatim: detail)
                        .font(OpenClawChatTypography.caption)
                        .foregroundStyle(OpenClawChatTheme.inkMuted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            self.accessory
        }
        .opacity(self.isEnabled ? 1 : 0.45)
        .padding(.horizontal, ChatPopoverMetrics.rowInset - ChatPopoverMetrics.rowGutter)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: ChatPopoverMetrics.rowHeight, alignment: .leading)
        .background { self.selectionBackground }
        .contentShape(RoundedRectangle(cornerRadius: ChatPopoverMetrics.rowCornerRadius, style: .continuous))
        .animation(animation, value: self.isSelected)
    }

    private func glyph(_ name: String) -> some View {
        ChatPopoverGlyph(name: name, tint: self.accent)
    }

    @ViewBuilder
    private var accessory: some View {
        switch self.indicator {
        case .toggle:
            ChatPopoverMiniSwitch(isOn: self.isSelected)
        case .checkmark, .exclusive:
            if self.isSelected {
                Image(systemName: "checkmark")
                    .font(OpenClawChatTypography.captionSemiBold)
                    .foregroundStyle(OpenClawChatTheme.brandAccent)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if self.isSelected, self.indicator != .toggle {
            if self.indicator == .exclusive, let namespace = self.selectionNamespace {
                self.highlightShape
                    .matchedGeometryEffect(id: "chat-popover-selection", in: namespace)
            } else {
                self.highlightShape
            }
        }
    }

    private var highlightShape: some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ChatPopoverMetrics.rowCornerRadius,
            style: .continuous)
        return shape
            .fill(OpenClawChatTheme.brandAccent.opacity(0.12))
            .overlay(shape.strokeBorder(OpenClawChatTheme.brandAccent.opacity(0.22), lineWidth: 0.8))
    }

    private func perform() {
        ChatPopoverHaptics.selected()
        guard self.closesPopover else {
            self.action()
            return
        }
        if self.closesBeforeAction {
            self.dismiss(then: self.action)
        } else {
            self.action()
            self.dismiss()
        }
    }
}

struct ChatPopoverRowButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed: Bool = configuration.isPressed
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ChatPopoverMetrics.rowCornerRadius,
            style: .continuous)
        let scale: CGFloat = (pressed && !self.reduceMotion) ? 0.97 : 1
        let animation: Animation = self.reduceMotion
            ? OpenClawChatMotion.reducedFade
            : ChatPopoverMotion.pressSpring
        configuration.label
            .background { shape.fill(OpenClawChatTheme.inkStrong.opacity(pressed ? 0.09 : 0)) }
            .scaleEffect(scale)
            .animation(animation, value: pressed)
    }
}

struct ChatPopoverSectionHeader: View {
    let title: String

    var body: some View {
        Text(verbatim: self.title)
            .font(OpenClawChatTypography.captionSemiBold)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(OpenClawChatTheme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ChatPopoverMetrics.rowInset + ChatPopoverMetrics.rowGutter)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ChatPopoverNote: View {
    let text: String

    var body: some View {
        Text(verbatim: self.text)
            .font(OpenClawChatTypography.caption)
            .foregroundStyle(OpenClawChatTheme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ChatPopoverMetrics.rowInset + ChatPopoverMetrics.rowGutter)
            .padding(.vertical, 8)
    }
}

struct ChatPopoverDivider: View {
    var body: some View {
        Rectangle()
            .fill(OpenClawChatTheme.hairline.opacity(0.9))
            .frame(height: 1)
            .padding(.horizontal, ChatPopoverMetrics.rowInset + ChatPopoverMetrics.rowGutter)
            .padding(.vertical, 5)
            .accessibilityHidden(true)
    }
}

#else

extension View {
    /// Popovers are an iOS composer feature. macOS keeps its native menus.
    func chatPopover(
        isPresented _: Binding<Bool>,
        width _: CGFloat = 232,
        blursBackground _: Bool = false,
        scrollsContent _: Bool = true,
        @ViewBuilder content _: @escaping () -> some View) -> some View
    {
        self
    }
}

#endif
