import SwiftUI

struct ChatReplyPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let target: OpenClawChatReplyTarget
    let onCancel: () -> Void
    @State private var isPresented: Bool = false

    var body: some View {
        let preview: (text: String, isTruncated: Bool) = ChatReplyQuote.previewText(self.target.text)
        let shape: RoundedRectangle = RoundedRectangle(
            cornerRadius: CleanChatComposerMetrics.squircleCornerRadius,
            style: .continuous)
        HStack(alignment: .center, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(OpenClawChatTheme.accent)
                .frame(width: 3)
                .padding(.vertical, 12)
                .padding(.leading, 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "Replying to %@"), self.target.senderLabel))
                    .font(OpenClawChatTypography.captionSemiBold)
                    .foregroundStyle(OpenClawChatTheme.accent)
                    .lineLimit(1)
                Text(preview.text + (preview.isTruncated ? "..." : ""))
                    .font(OpenClawChatTypography.caption)
                    .foregroundStyle(OpenClawChatTheme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.leading, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: self.onCancel) {
                Image(systemName: "xmark")
                    .font(OpenClawChatTypography.captionSemiBold)
                    .foregroundStyle(OpenClawChatTheme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Cancel reply"))
            .help(String(localized: "Cancel reply"))
        }
        .frame(minHeight: 44)
        .background(shape.fill(OpenClawChatTheme.composerBarSurface))
        .overlay(shape.strokeBorder(OpenClawChatTheme.composerBarBorder, lineWidth: 1))
        .clipShape(shape)
        .opacity(self.isPresented ? 1 : 0)
        .offset(y: self.isPresented || self.reduceMotion ? 0 : 8)
        .onAppear {
            OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
                self.isPresented = true
            }
        }
    }
}
