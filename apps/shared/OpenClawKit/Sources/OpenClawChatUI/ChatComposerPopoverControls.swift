import Observation
import SwiftUI

#if os(iOS)

/// Look of a composer popover: a small opaque card, or a bar floating across the screen width
/// (used by the thinking slider, which sits directly on a progressive blur with no card behind it).
enum ChatPopoverStyle {
    case card
    case floatingBar
}

/// Owns the composer popover currently shown by the chat. The popover is an overlay of the chat view,
/// not a modal cover, so the text view keeps first responder and the keyboard stays open.
@MainActor
@Observable
final class ChatPopoverCenter {
    struct Presentation: Identifiable {
        let id: UUID = UUID()
        let anchor: CGRect
        let width: CGFloat
        let blursBackground: Bool
        let scrollsContent: Bool
        let style: ChatPopoverStyle
        let content: () -> AnyView
    }

    private(set) var current: Presentation?

    func present(_ presentation: Presentation) {
        guard self.current == nil else { return }
        self.current = presentation
    }

    func dismiss() {
        self.current = nil
    }
}

private struct ChatPopoverCenterKey: EnvironmentKey {
    static let defaultValue: ChatPopoverCenter? = nil
}

extension EnvironmentValues {
    var chatPopoverCenter: ChatPopoverCenter? {
        get { self[ChatPopoverCenterKey.self] }
        set { self[ChatPopoverCenterKey.self] = newValue }
    }
}

/// Draws the popover of the center above the whole chat. Taps outside close it; the keyboard is untouched.
struct ChatPopoverOverlay: View {
    let center: ChatPopoverCenter

    var body: some View {
        if let presentation = self.center.current {
            let center: ChatPopoverCenter = self.center
            ChatPopoverHost(
                anchorFrame: presentation.anchor,
                width: presentation.width,
                blursBackground: presentation.blursBackground,
                scrollsContent: presentation.scrollsContent,
                style: presentation.style,
                popoverContent: presentation.content,
                onClosed: { center.dismiss() })
                .id(presentation.id)
        }
    }
}

/// A plain button that opens a popover grown out of its own label.
/// Inside `OpenClawChatView` the popover is an overlay (keyboard stays up); elsewhere it falls back
/// to a transparent cover.
struct ChatPopoverButton<Label: View, Content: View>: View {
    @Environment(\.chatPopoverCenter) private var center
    @State private var isPresented: Bool = false
    @State private var anchorFrame: CGRect = .zero
    private let width: CGFloat
    private let blursBackground: Bool
    private let scrollsContent: Bool
    private let style: ChatPopoverStyle
    private let content: () -> Content
    private let label: () -> Label

    init(
        width: CGFloat = ChatPopoverMetrics.width,
        blursBackground: Bool = false,
        scrollsContent: Bool = true,
        style: ChatPopoverStyle = .card,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label)
    {
        self.width = width
        self.blursBackground = blursBackground
        self.scrollsContent = scrollsContent
        self.style = style
        self.content = content
        self.label = label
    }

    var body: some View {
        Button {
            self.open()
        } label: {
            self.label()
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { frame in
            self.anchorFrame = frame
        })
        .chatPopover(
            isPresented: self.$isPresented,
            width: self.width,
            blursBackground: self.blursBackground,
            scrollsContent: self.scrollsContent,
            style: self.style,
            content: self.content)
    }

    private func open() {
        guard let center = self.center else {
            ChatPopoverTransaction.present(self.$isPresented)
            return
        }
        let content: () -> Content = self.content
        let presentation: ChatPopoverCenter.Presentation = ChatPopoverCenter.Presentation(
            anchor: self.anchorFrame,
            width: self.width,
            blursBackground: self.blursBackground,
            scrollsContent: self.scrollsContent,
            style: self.style,
            content: { AnyView(content()) })
        center.present(presentation)
    }
}

/// Expandable group inside a popover (replaces nested system menus).
struct ChatPopoverDisclosure<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool
    private let title: String
    private let systemImage: String
    private let content: Content

    init(
        title: String,
        systemImage: String,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: () -> Content)
    {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = State(initialValue: initiallyExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
                    self.isExpanded.toggle()
                }
            } label: {
                self.header
            }
            .buttonStyle(.plain)
            .accessibilityLabel(self.title)
            .accessibilityValue(self.isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
            .accessibilityAddTraits(.isButton)
            if self.isExpanded {
                VStack(spacing: 0) {
                    self.content
                }
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: self.systemImage)
                .font(OpenClawChatTypography.body)
                .foregroundStyle(OpenClawChatTheme.brandAccent)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)
            Text(verbatim: self.title)
                .font(OpenClawChatTypography.body)
                .foregroundStyle(OpenClawChatTheme.inkStrong)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(OpenClawChatTypography.captionSemiBold)
                .foregroundStyle(OpenClawChatTheme.inkMuted)
                .rotationEffect(.degrees(self.isExpanded ? 90 : 0))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, ChatPopoverMetrics.rowInset)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: ChatPopoverMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#endif
