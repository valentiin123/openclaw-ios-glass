import SwiftUI

#if os(iOS)

/// A plain button that opens a `chatPopover` grown out of its own label.
/// State lives here, so callers do not need stored `@State` on the composer.
struct ChatPopoverButton<Label: View, Content: View>: View {
    @State private var isPresented: Bool = false
    private let width: CGFloat
    private let blursBackground: Bool
    private let scrollsContent: Bool
    private let content: () -> Content
    private let label: () -> Label

    init(
        width: CGFloat = ChatPopoverMetrics.width,
        blursBackground: Bool = false,
        scrollsContent: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: @escaping () -> Label)
    {
        self.width = width
        self.blursBackground = blursBackground
        self.scrollsContent = scrollsContent
        self.content = content
        self.label = label
    }

    var body: some View {
        Button {
            ChatPopoverTransaction.present(self.$isPresented)
        } label: {
            self.label()
        }
        .buttonStyle(.plain)
        .chatPopover(
            isPresented: self.$isPresented,
            width: self.width,
            blursBackground: self.blursBackground,
            scrollsContent: self.scrollsContent,
            content: self.content)
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
                .transition(.opacity)
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
            Image(systemName: self.isExpanded ? "chevron.down" : "chevron.right")
                .font(OpenClawChatTypography.captionSemiBold)
                .foregroundStyle(OpenClawChatTheme.inkMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, ChatPopoverMetrics.rowInset)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: ChatPopoverMetrics.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#endif
