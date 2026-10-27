import SwiftUI
#if os(iOS)
import UIKit
#endif

/// One prose or heading block that can join a contiguous, natively selectable run.
struct ChatSelectableProseBlock {
    let attributed: AttributedString
    /// nil for body prose, 1...6 for headings that join a run (the level 1 and 2 rules are not drawn in a run).
    let headingLevel: Int?
    /// 0 for prose and headings; 1... for a list item paragraph (nesting depth, 1 = top level).
    var listDepth: Int = 0
    /// Marker text (bullet, number, checkbox) drawn before the first paragraph of a list item; nil otherwise.
    var listMarker: String? = nil
}

/// Layout of a markdown snapshot: untouched blocks, or a run of contiguous prose merged into one text view.
enum ChatMarkdownLayoutItem {
    case single(index: Int, block: ChatMarkdownRenderedBlock)
    case run(blocks: [ChatSelectableProseBlock])
}

/// Groups contiguous prose/heading blocks so one long press can select across paragraphs.
///
/// SwiftUI `.textSelection(.enabled)` on iOS selects inside a single `Text` only, so contiguous prose
/// is merged into one read-only `UITextView` (`ChatSelectableProseView`).
///
/// Limits (by design):
/// - Prose, headings 1...6 and bullet/numbered/checkbox lists (nested ones too) join a run. List markers and
///   indentation are drawn with paragraph styles and tab stops, so selection also works inside lists.
/// - Code blocks, tables, math blocks, Mermaid/rich blocks, disclosures and lists holding a code block or
///   inline math break a run. A new run starts after them; selection cannot cross them. The message action
///   bar offers "Select Text" (`ChatSelectableTextSheet`) to select the whole message instead.
/// - Prose with inline math (images) keeps the SwiftUI `Text` path. Level 1 and 2 headings lose their rule.
/// - The streaming reveal path (`reveal != nil`) and non-response typography keep the SwiftUI path.
enum ChatMarkdownLayout {
    @MainActor
    static func items(for blocks: [ChatMarkdownRenderedBlock], groupsProse: Bool) -> [ChatMarkdownLayoutItem] {
        #if os(iOS)
        guard groupsProse else { return self.singles(blocks) }
        var items: [ChatMarkdownLayoutItem] = []
        var pending: [ChatSelectableProseBlock] = []
        for (index, block) in blocks.enumerated() {
            if let candidates = self.candidates(for: block) {
                pending.append(contentsOf: candidates)
                continue
            }
            if !pending.isEmpty {
                items.append(.run(blocks: pending))
                pending = []
            }
            items.append(.single(index: index, block: block))
        }
        if !pending.isEmpty {
            items.append(.run(blocks: pending))
        }
        return items
        #else
        return self.singles(blocks)
        #endif
    }

    private static func singles(_ blocks: [ChatMarkdownRenderedBlock]) -> [ChatMarkdownLayoutItem] {
        blocks.enumerated().map { entry in
            ChatMarkdownLayoutItem.single(index: entry.offset, block: entry.element)
        }
    }

    /// Blocks a rendered block contributes to a run, or nil when it cannot join one.
    @MainActor
    private static func candidates(for block: ChatMarkdownRenderedBlock) -> [ChatSelectableProseBlock]? {
        switch block {
        case let .prose(prose):
            guard prose.inlineContent == nil, !prose.attributed.characters.isEmpty else { return nil }
            return [ChatSelectableProseBlock(attributed: prose.attributed, headingLevel: nil)]
        case let .heading(level, prose):
            guard prose.inlineContent == nil, !prose.attributed.characters.isEmpty else { return nil }
            return [ChatSelectableProseBlock(attributed: prose.attributed, headingLevel: level)]
        case let .list(list):
            return self.listBlocks(list, depth: 1)
        default:
            return nil
        }
    }

    /// Flattens a list (nested ones too) into one block per item paragraph. Returns nil when an item holds
    /// a code block or inline math, so the whole list keeps its own rendering.
    @MainActor
    private static func listBlocks(_ list: ChatMarkdownList, depth: Int) -> [ChatSelectableProseBlock]? {
        var result: [ChatSelectableProseBlock] = []
        for (index, item) in list.items.enumerated() {
            let marker: String = self.markerText(for: list, item: item, at: index)
            var needsMarker: Bool = true
            for content in item.content {
                switch content {
                case let .markdown(markdown):
                    let prose = ChatMarkdownProse(markdown: markdown, isComplete: true, preparesReveal: false)
                    guard prose.inlineContent == nil else { return nil }
                    result.append(ChatSelectableProseBlock(
                        attributed: prose.attributed,
                        headingLevel: nil,
                        listDepth: depth,
                        listMarker: needsMarker ? marker : nil))
                    needsMarker = false
                case .code:
                    return nil
                case let .list(nested):
                    if needsMarker {
                        result.append(ChatSelectableProseBlock(
                            attributed: AttributedString(),
                            headingLevel: nil,
                            listDepth: depth,
                            listMarker: marker))
                        needsMarker = false
                    }
                    guard let nestedBlocks = self.listBlocks(nested, depth: depth + 1) else { return nil }
                    result.append(contentsOf: nestedBlocks)
                }
            }
            if needsMarker {
                result.append(ChatSelectableProseBlock(
                    attributed: AttributedString(),
                    headingLevel: nil,
                    listDepth: depth,
                    listMarker: marker))
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func markerText(for list: ChatMarkdownList, item: ChatMarkdownListItem, at index: Int) -> String {
        let marker: ChatMarkdownListMarker = list.marker(for: item, at: index)
        var parts: [String] = []
        if let text = marker.text { parts.append(text) }
        if let checkbox = marker.checkbox {
            parts.append(checkbox == .checked ? "\u{2611}" : "\u{2610}")
        }
        return parts.joined(separator: " ")
    }
}

#if os(iOS)
/// Run of selectable prose. Rebuilds when the color scheme or Dynamic Type size changes.
@MainActor
struct ChatSelectableProseRun: View {
    let blocks: [ChatSelectableProseBlock]
    let textColor: Color
    let linkColor: Color
    let lineSpacing: CGFloat
    let blockSpacing: CGFloat
    let compact: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let traits = UITraitCollection(userInterfaceStyle: self.colorScheme == .dark ? .dark : .light)
        let content: NSAttributedString = ChatSelectableProseBuilder.make(
            blocks: self.blocks,
            textColor: self.textColor,
            traits: traits,
            lineSpacing: self.lineSpacing,
            blockSpacing: self.blockSpacing,
            compact: self.compact)
        ChatSelectableProseView(
            content: content,
            linkColor: UIColor(self.linkColor).resolvedColor(with: traits))
            .id(self.dynamicTypeSize)
            .accessibilityIdentifier("chat-selectable-prose")
    }
}

@MainActor
enum ChatSelectableProseBuilder {
    private static let codeFontName: String = "JetBrainsMono-Regular"
    private static let codeFontScale: CGFloat = 0.9
    private static let separator: String = "\n"

    static func make(
        blocks: [ChatSelectableProseBlock],
        textColor: Color,
        traits: UITraitCollection,
        lineSpacing: CGFloat,
        blockSpacing: CGFloat,
        compact: Bool) -> NSAttributedString
    {
        let result = NSMutableAttributedString()
        let baseStyle = NSMutableParagraphStyle()
        baseStyle.lineSpacing = lineSpacing
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(
                    string: self.separator,
                    attributes: [.font: OpenClawChatTypography.bodyUIFont]))
            }
            let blockStyle: NSMutableParagraphStyle = self.paragraphStyle(for: block, base: baseStyle)
            let piece: NSAttributedString = self.piece(
                for: block,
                textColor: textColor,
                traits: traits,
                style: blockStyle)
            let start: Int = result.length
            result.append(piece)
            guard index > 0, piece.length > 0 else { continue }
            // A paragraph takes the style of its first character, so only that character carries the gap.
            let spaced: NSMutableParagraphStyle = (blockStyle.mutableCopy() as? NSMutableParagraphStyle) ?? blockStyle
            let previousIsList: Bool = blocks[index - 1].listDepth > 0
            if block.listDepth > 0, previousIsList {
                spaced.paragraphSpacingBefore = compact ? 3 : 5
            } else {
                spaced.paragraphSpacingBefore = blockSpacing + self.extraTopSpacing(for: block, compact: compact)
            }
            result.addAttribute(.paragraphStyle, value: spaced, range: NSRange(location: start, length: 1))
        }
        return result
    }

    private static func extraTopSpacing(for block: ChatSelectableProseBlock, compact: Bool) -> CGFloat {
        guard let level = block.headingLevel else { return 0 }
        if level <= 2 { return compact ? 4 : 6 }
        if level == 3 { return compact ? 4 : 6 }
        return 2
    }

    /// Indentation for list paragraphs: the marker sits at the depth indent, text and wrapped lines at the
    /// text indent, reached with a tab stop.
    private static func paragraphStyle(
        for block: ChatSelectableProseBlock,
        base: NSParagraphStyle) -> NSMutableParagraphStyle
    {
        let style: NSMutableParagraphStyle = (base.mutableCopy() as? NSMutableParagraphStyle)
            ?? NSMutableParagraphStyle()
        guard block.listDepth > 0 else { return style }
        let step: CGFloat = OpenClawChatTypography.scaled(20)
        let markerIndent: CGFloat = step * CGFloat(block.listDepth - 1)
        let textIndent: CGFloat = markerIndent + step
        style.headIndent = textIndent
        style.firstLineHeadIndent = block.listMarker == nil ? textIndent : markerIndent
        style.tabStops = [NSTextTab(textAlignment: .left, location: textIndent, options: [:])]
        style.defaultTabInterval = step
        return style
    }

    private static func piece(
        for block: ChatSelectableProseBlock,
        textColor: Color,
        traits: UITraitCollection,
        style: NSParagraphStyle) -> NSAttributedString
    {
        let baseFont: UIFont = self.baseFont(for: block)
        let baseColor: UIColor = self.baseColor(for: block, textColor: textColor, traits: traits)
        let piece = NSMutableAttributedString()
        if let marker = block.listMarker {
            let markerColor: UIColor = UIColor(OpenClawChatTheme.brandAccent).resolvedColor(with: traits)
            piece.append(NSAttributedString(
                string: marker + "\t",
                attributes: [.font: baseFont, .foregroundColor: markerColor]))
        }
        for run in block.attributed.runs {
            let text: String = String(block.attributed[run.range].characters)
            let intent: InlinePresentationIntent = run.inlinePresentationIntent ?? []
            var attributes: [NSAttributedString.Key: Any] = [:]
            attributes[.font] = self.font(for: intent, base: baseFont)
            attributes[.foregroundColor] = self.runColor(run.foregroundColor, fallback: baseColor, traits: traits)
            if let link = run.link {
                attributes[.link] = link
            }
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            piece.append(NSAttributedString(string: text, attributes: attributes))
        }
        piece.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: piece.length))
        return piece
    }

    private static func runColor(_ color: Color?, fallback: UIColor, traits: UITraitCollection) -> UIColor {
        guard let color else { return fallback }
        return UIColor(color).resolvedColor(with: traits)
    }

    private static func baseColor(
        for block: ChatSelectableProseBlock,
        textColor: Color,
        traits: UITraitCollection) -> UIColor
    {
        if let level = block.headingLevel, level <= 3 {
            return UIColor(OpenClawChatTheme.inkStrong).resolvedColor(with: traits)
        }
        return UIColor(textColor).resolvedColor(with: traits)
    }

    private static func baseFont(for block: ChatSelectableProseBlock) -> UIFont {
        guard let level = block.headingLevel else { return OpenClawChatTypography.bodyUIFont }
        return self.headingFont(level: level)
    }

    private static func headingDesignSize(level: Int) -> CGFloat {
        switch level {
        case 1: 24
        case 2: 21
        case 3: 19
        case 4: 17
        case 5: 16
        default: 15
        }
    }

    /// Approximates `OpenClawChatTypography.heading(level:)` with the body face in bold (the display face is
    /// not exposed as a `UIFont` by the typography enum). Scales with Dynamic Type like the SwiftUI path.
    private static func headingFont(level: Int) -> UIFont {
        let size: CGFloat = OpenClawChatTypography.scaled(self.headingDesignSize(level: level))
        let sized: UIFont = OpenClawChatTypography.bodyUIFont.withSize(size)
        let scaled: UIFont = UIFontMetrics(forTextStyle: .headline).scaledFont(for: sized)
        let traits: UIFontDescriptor.SymbolicTraits = scaled.fontDescriptor.symbolicTraits.union(.traitBold)
        guard let descriptor = scaled.fontDescriptor.withSymbolicTraits(traits) else { return scaled }
        return UIFont(descriptor: descriptor, size: 0)
    }

    private static func font(for intent: InlinePresentationIntent, base: UIFont) -> UIFont {
        if intent.contains(.code) {
            return self.codeFont(size: base.pointSize * self.codeFontScale)
        }
        var traits: UIFontDescriptor.SymbolicTraits = base.fontDescriptor.symbolicTraits
        if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
        if intent.contains(.emphasized) { traits.insert(.traitItalic) }
        guard traits != base.fontDescriptor.symbolicTraits,
              let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    private static func codeFont(size: CGFloat) -> UIFont {
        UIFont(name: self.codeFontName, size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// Read-only, non-scrolling `UITextView`: long press selects words and ranges across all merged paragraphs.
struct ChatSelectableProseView: UIViewRepresentable {
    let content: NSAttributedString
    let linkColor: UIColor

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.attributedText = self.content
        textView.linkTextAttributes = [.foregroundColor: self.linkColor]
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Only replace the text when it changed: assigning it would drop the user's current selection.
        if !textView.attributedText.isEqual(to: self.content) {
            textView.attributedText = self.content
        }
        textView.linkTextAttributes = [.foregroundColor: self.linkColor]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let unbounded = CGFloat.greatestFiniteMagnitude
        guard let proposed = proposal.width, proposed.isFinite else {
            let fitted: CGSize = uiView.sizeThatFits(CGSize(width: unbounded, height: unbounded))
            return CGSize(width: ceil(fitted.width), height: ceil(fitted.height))
        }
        let fitted: CGSize = uiView.sizeThatFits(CGSize(width: proposed, height: unbounded))
        return CGSize(width: proposed, height: ceil(fitted.height))
    }
}
#endif
