import SwiftUI

#if os(iOS)
import UIKit

// Small opaque popovers for the composer (+, permissions, context, model, thinking).
// No Liquid Glass: palette surface, hairline border, small corner radius. They open from the control
// that presented them (scale + fade with the shared chat spring, plain fade under Reduce Motion) and
// close on any tap outside, through a transparent scrim that swallows the tap so nothing behind fires.

enum ChatPopoverMetrics {
    static let cornerRadius: CGFloat = 12
    static let width: CGFloat = 232
    static let wideWidth: CGFloat = 288
    static let rowHeight: CGFloat = 44
    static let rowInset: CGFloat = 12
    static let screenMargin: CGFloat = 12
    static let anchorGap: CGFloat = 6
    static let hiddenScale: CGFloat = 0.86
    static let closeDelayMilliseconds: Int = 160
    static let afterCloseDelayMilliseconds: Int = 120
    static let blurStartRadius: CGFloat = 90
    static let blurEndRadius: CGFloat = 520
    static let minimumPanelHeight: CGFloat = 120
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

extension EnvironmentValues {
    var chatPopoverDismiss: ChatPopoverDismissAction {
        get { self[ChatPopoverDismissKey.self] }
        set { self[ChatPopoverDismissKey.self] = newValue }
    }
}

struct ChatPopoverSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: ChatPopoverMetrics.cornerRadius,
            style: .continuous)
        content
            .background(OpenClawChatTheme.surfaceCard, in: shape)
            .overlay(shape.strokeBorder(OpenClawChatTheme.hairline, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 6)
    }
}

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
        width: CGFloat) -> ChatPopoverLayout
    {
        let margin: CGFloat = ChatPopoverMetrics.screenMargin
        let gap: CGFloat = ChatPopoverMetrics.anchorGap
        let panelWidth: CGFloat = min(width, max(container.width - margin * 2, 160))
        let maxOriginX: CGFloat = max(margin, container.width - panelWidth - margin)
        let originX: CGFloat = min(max(anchor.midX - panelWidth / 2, margin), maxOriginX)
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
        let anchorX: CGFloat = min(max((anchor.midX - originX) / panelWidth, 0), 1)
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

private struct ChatPopoverHost<PopoverContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let anchorFrame: CGRect
    let width: CGFloat
    let blursBackground: Bool
    let scrollsContent: Bool
    let popoverContent: () -> PopoverContent
    let onClosed: @MainActor () -> Void

    @State private var isShown: Bool = false
    @State private var isClosing: Bool = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let layout: ChatPopoverLayout = ChatPopoverLayout.resolve(
                anchor: self.anchorFrame,
                container: proxy.size,
                safeInsets: proxy.safeAreaInsets,
                width: self.width)
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
        .onAppear {
            OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
                self.isShown = true
            }
        }
        .accessibilityAction(.escape) {
            self.close(then: nil)
        }
    }

    private func backdrop(layout: ChatPopoverLayout) -> some View {
        ZStack {
            if self.blursBackground {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        RadialGradient(
                            colors: [Color.black, Color.black.opacity(0)],
                            center: layout.blurCenter,
                            startRadius: ChatPopoverMetrics.blurStartRadius,
                            endRadius: ChatPopoverMetrics.blurEndRadius))
                    .opacity(self.isShown ? 1 : 0)
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

    @ViewBuilder
    private func panel(layout: ChatPopoverLayout) -> some View {
        let hiddenScale: CGFloat = self.reduceMotion ? 1 : ChatPopoverMetrics.hiddenScale
        let scale: CGFloat = self.isShown ? 1 : hiddenScale
        let opacity: Double = self.isShown ? 1 : 0
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
            } else {
                ChatComposerSection { self.popoverContent() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .modifier(ChatPopoverSurface())
        .scaleEffect(scale, anchor: layout.scaleAnchor)
        .opacity(opacity)
        .accessibilityAddTraits(.isModal)
    }

    private func fittedHeight(maxHeight: CGFloat) -> CGFloat {
        guard self.contentHeight > 0 else { return maxHeight }
        return min(self.contentHeight, maxHeight)
    }

    @MainActor
    private func close(then afterClose: (@MainActor () -> Void)?) {
        guard !self.isClosing else { return }
        self.isClosing = true
        OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
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
    /// Presents `content` as a small opaque popover that grows out of this view.
    /// Open it with `ChatPopoverTransaction.present($isPresented)` so the system cover slide is skipped.
    func chatPopover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        width: CGFloat = ChatPopoverMetrics.width,
        blursBackground: Bool = false,
        scrollsContent: Bool = true,
        @ViewBuilder content: @escaping () -> PopoverContent) -> some View
    {
        self.modifier(ChatPopoverPresenter(
            isPresented: isPresented,
            width: width,
            blursBackground: blursBackground,
            scrollsContent: scrollsContent,
            popoverContent: content))
    }
}

// MARK: - Rows

struct ChatPopoverRow: View {
    @Environment(\.chatPopoverDismiss) private var dismiss
    let title: String
    var systemImage: String?
    var detail: String?
    var isSelected: Bool = false
    var isEnabled: Bool = true
    var closesPopover: Bool = true
    /// Sheets and pickers must present after the popover cover is gone.
    var closesBeforeAction: Bool = false
    var hint: String = ""
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            self.perform()
        } label: {
            self.label
        }
        .buttonStyle(ChatPopoverRowButtonStyle())
        .disabled(!self.isEnabled)
        .accessibilityLabel(self.title)
        .accessibilityValue(self.isSelected ? String(localized: "Selected") : "")
        .accessibilityHint(self.hint)
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
    }

    private var label: some View {
        let contentOpacity: Double = self.isEnabled ? 1 : 0.45
        return HStack(spacing: 10) {
            if let systemImage = self.systemImage {
                Image(systemName: systemImage)
                    .font(OpenClawChatTypography.body)
                    .foregroundStyle(OpenClawChatTheme.brandAccent)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
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
                }
            }
            Spacer(minLength: 8)
            if self.isSelected {
                Image(systemName: "checkmark")
                    .font(OpenClawChatTypography.captionSemiBold)
                    .foregroundStyle(OpenClawChatTheme.brandAccent)
                    .accessibilityHidden(true)
            }
        }
        .opacity(contentOpacity)
        .padding(.horizontal, ChatPopoverMetrics.rowInset)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: ChatPopoverMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func perform() {
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

private struct ChatPopoverRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed: Color = OpenClawChatTheme.surfaceHover
        configuration.label
            .background(configuration.isPressed ? pressed : Color.clear)
    }
}

struct ChatPopoverSectionHeader: View {
    let title: String

    var body: some View {
        Text(verbatim: self.title)
            .font(OpenClawChatTypography.captionSemiBold)
            .foregroundStyle(OpenClawChatTheme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ChatPopoverMetrics.rowInset)
            .padding(.top, 10)
            .padding(.bottom, 2)
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
            .padding(.horizontal, ChatPopoverMetrics.rowInset)
            .padding(.vertical, 8)
    }
}

struct ChatPopoverDivider: View {
    var body: some View {
        Rectangle()
            .fill(OpenClawChatTheme.hairline)
            .frame(height: 1)
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
