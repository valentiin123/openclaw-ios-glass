import Foundation
import OpenClawKit
import SwiftUI

struct ChatToolActivityItem: Identifiable, Equatable {
    enum State: Equatable {
        case running
        case finished
        case failed
        case blocked
        case skipped
        case unavailable

        var title: LocalizedStringResource {
            switch self {
            case .running: "Working"
            case .finished: "Finished"
            case .failed: "Failed"
            case .blocked: "Blocked"
            case .skipped: "Skipped"
            case .unavailable: "No result"
            }
        }
    }

    let id: String
    let name: String?
    let arguments: AnyCodable?
    let details: AnyCodable?
    let resultText: String?
    let state: State
    let liveDiffStat: ChatToolDiffStat?
    var activity: OpenClawAgentActivityItem?
    var activityPrepared = false

    var isVisible: Bool {
        self.activity?.isVisible ?? !self.activityPrepared
    }

    var displayState: State {
        guard let activity = self.activity else { return self.state }
        switch activity.status {
        case "running": return .running
        case "completed": return .finished
        case "failed": return .failed
        case "blocked": return .blocked
        case "skipped": return .skipped
        default: return .unavailable
        }
    }

    var isError: Bool {
        self.displayState == .failed
    }

    var isPending: Bool {
        self.displayState == .running
    }
}

extension ChatToolActivityItem {
    init(live call: OpenClawChatPendingToolCall) {
        self.init(
            id: call.id,
            name: call.name,
            arguments: call.args,
            details: nil,
            resultText: nil,
            state: call.activity == nil && !call.isComplete || call.activity?.status == "running" ? .running :
                call.activity?.status == "completed" ? .finished :
                call.activity?.status == "failed" || call.activity?.status == "blocked" ? .failed : .unavailable,
            liveDiffStat: call.diffStat,
            activity: call.activity)
    }
}

enum ChatToolActivity {
    static func resultIsError(_ flag: Bool?, text: String?) -> Bool {
        if let flag { return flag }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        if ["tool not found", "tool not found."].contains(text.lowercased()) { return true }
        guard text.utf16.count <= 20000,
              text.hasPrefix("{"), text.hasSuffix("}"),
              let data = text.data(using: .utf8),
              let result = try? JSONDecoder().decode(AnyCodable.self, from: data).dictionaryValue
        else { return false }
        if let flag = result["isError"]?.boolValue ?? result["is_error"]?.boolValue { return flag }
        if let error = result["error"] {
            if let text = error.stringValue,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if error.boolValue == true || error.dictionaryValue != nil || error.arrayValue != nil { return true }
        }
        return ["error", "failed", "timeout"].contains(
            result["status"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
    }

    static func items(
        calls: [OpenClawChatMessageContent],
        results: [OpenClawChatMessageContent],
        activity: [OpenClawAgentActivityItem]? = nil,
        liveTools: [OpenClawChatPendingToolCall] = []) -> [ChatToolActivityItem]
    {
        var remainingResults = Array(results.enumerated())
        var items = calls.enumerated().map { index, call in
            let id = call.id ?? "call-\(index)"
            let resultIndex = call.id.flatMap { callID in
                remainingResults.firstIndex { _, result in result.id == callID }
            }
            let result = resultIndex.map { remainingResults.remove(at: $0).element }
            // History owns recorded inputs; live activity supplies status until
            // the result arrives, never replacing already-recorded arguments.
            let live = result == nil
                ? liveTools.first(where: { $0.id == call.id }).map(ChatToolActivityItem.init(live:)) : nil

            return ChatToolActivityItem(
                id: id,
                name: call.name ?? live?.name,
                arguments: call.arguments ?? live?.arguments,
                details: result?.details,
                resultText: result?.text,
                state: result
                    .map { Self.resultIsError($0.isError, text: $0.text) ? .failed : .finished } ??
                    live?.state ?? .unavailable,
                liveDiffStat: live?.liveDiffStat,
                activity: live?.activity ?? activity?.first { $0.toolCallId == id },
                activityPrepared: live == nil && activity != nil)
        }

        items.append(contentsOf: remainingResults.map { index, result in
            let id = result.id ?? "result-\(index)"
            return ChatToolActivityItem(
                id: id,
                name: result.name,
                arguments: nil,
                details: result.details,
                resultText: result.text,
                state: Self.resultIsError(result.isError, text: result.text) ? .failed : .finished,
                liveDiffStat: nil,
                activity: activity?.first { $0.toolCallId == id },
                activityPrepared: activity != nil)
        })
        return items
    }
}

struct ChatToolActivityRow: View, Equatable {
    let item: ChatToolActivityItem

    var body: some View {
        // Compare the item before constructing the content: its initializer prepares
        // the diff, which unchanged siblings must not repeat on every tool update.
        ChatToolActivityRowContent(item: self.item)
    }
}

private struct ChatToolActivityRowContent: View {
    @Environment(\.openClawChatDesktopLayout) private var isDesktopLayout
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ChatToolActivityItem
    private let displayCall: (name: String?, args: AnyCodable?)
    private let resolvedDiff: (lines: [ChatToolDiffLine], stat: ChatToolDiffStat?)?
    private let argumentsText: String
    @State private var expanded = false
    @State private var showsFullResult = false

    private static let disclosureWidth: CGFloat = 12
    private static let expandedLineLimit = 40
    private static let argumentsCharLimit: Int = 4000

    private var display: ToolDisplaySummary {
        ToolDisplayRegistry.resolve(name: self.displayCall.name, args: self.displayCall.args)
    }

    private var detailLine: String? {
        guard let detail = self.display.detailLine, !detail.isEmpty else { return nil }
        return detail
    }

    private var formattedResult: String {
        guard let resultText = self.item.resultText else { return "" }
        return ToolResultTextFormatter.format(text: resultText, toolName: self.displayCall.name)
    }

    private var expandable: Bool {
        self.resolvedDiff != nil || !self.formattedResult.isEmpty || self.showsArguments
    }

    /// Arguments are the first thing the detail shows, except for edits where the diff already says it.
    private var showsArguments: Bool {
        self.resolvedDiff == nil && !self.argumentsText.isEmpty
    }

    private var accessibilityValue: String {
        let status = String(localized: self.item.displayState.title)
        return self.detailLine.map { "\(status), \($0)" } ?? status
    }

    private var expandedLineCount: Int {
        self.resolvedDiff?.lines.count ?? self.formattedResult.components(separatedBy: .newlines).count
    }

    private var isResultTruncated: Bool {
        self.expandedLineCount > Self.expandedLineLimit
    }

    private var expandedResult: String {
        guard self.isResultTruncated, !self.showsFullResult else { return self.formattedResult }
        let lines = self.formattedResult.components(separatedBy: .newlines)
        return lines.prefix(Self.expandedLineLimit - 1).joined(separator: "\n") + "\n…"
    }

    private var expandedDiffLines: [ChatToolDiffLine] {
        guard let lines = self.resolvedDiff?.lines else { return [] }
        guard self.isResultTruncated, !self.showsFullResult else { return lines }
        return Array(lines.prefix(Self.expandedLineLimit - 1)) + [
            ChatToolDiffLine(kind: .skip, text: ""),
        ]
    }

    private var displayedDiffStat: ChatToolDiffStat? {
        self.item.isPending ? self.item.liveDiffStat ?? self.resolvedDiff?.stat : self.resolvedDiff?.stat
    }

    init(item: ChatToolActivityItem) {
        self.item = item
        let displayCall = ToolDisplayRegistry.displayCall(name: item.name, args: item.arguments)
        self.displayCall = displayCall
        self.argumentsText = Self.formatArguments(displayCall.args)
        self.resolvedDiff = ChatToolDiff.resolveDiff(
            name: displayCall.name,
            arguments: displayCall.args,
            details: item.details,
            isError: item.isError)
    }

    /// Touch layout: a flat, sober row (no card, no accent bar). Desktop keeps its card.
    @ViewBuilder
    var body: some View {
        if self.isDesktopLayout {
            self.column.modifier(ChatWorkCardStyle(tint: self.cardTint))
        } else {
            self.column
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 4) {
            if self.expandable {
                Button {
                    OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
                        self.expanded.toggle()
                    }
                } label: {
                    self.collapsedRow
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(self.display.title)
                .accessibilityValue(self.accessibilityValue)
                .accessibilityHint(self.expanded ? "Collapse tool result" : "Expand tool result")
                .accessibilityIdentifier("chat-tool-activity-\(self.item.id)")
            } else {
                self.collapsedRow
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(self.display.title)
                    .accessibilityValue(self.accessibilityValue)
            }

            if self.expanded, self.expandable {
                self.detailPanel
            }
        }
    }

    /// What the old "tool details" showed: arguments, then the result (or the diff).
    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if self.showsArguments {
                self.sectionLabel(String(localized: "Arguments"))
                Text(self.argumentsText)
                    .font(OpenClawChatTypography.mono(size: 12, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if self.resolvedDiff != nil {
                self.diffRows
                // The result text carries the outcome (success summary or the
                // error diagnostic); hiding it would misrepresent failed edits
                // as applied changes. Bounded so foreign harness output cannot
                // dwarf the diff.
                if !self.formattedResult.isEmpty {
                    Text(self.formattedResult)
                        .font(OpenClawChatTypography.mono(size: 12, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(Self.expandedLineLimit)
                }
            } else if !self.formattedResult.isEmpty {
                if self.showsArguments {
                    self.sectionLabel(String(localized: "Result"))
                }
                Text(self.expandedResult)
                    .font(OpenClawChatTypography.mono(size: 12, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if self.isResultTruncated {
                Button {
                    self.showsFullResult.toggle()
                } label: {
                    Text(
                        self.showsFullResult
                            ? String(localized: "Show less")
                            : String(
                                format: String(localized: "Show all %lld lines"),
                                Int64(self.expandedLineCount)))
                        .font(OpenClawChatTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !self.isDesktopLayout {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(OpenClawChatTheme.surfaceAlt)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(OpenClawChatTheme.hairline, lineWidth: 1))
            }
        }
        .padding(.leading, self.isDesktopLayout ? 0 : 19)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(OpenClawChatTypography.captionSemiBold)
            .foregroundStyle(OpenClawChatTheme.inkMuted)
    }

    /// Pretty JSON of the call arguments, bounded so a huge payload cannot flood the transcript.
    private static func formatArguments(_ args: AnyCodable?) -> String {
        guard let args else { return "" }
        if let dictionary = args.dictionaryValue, dictionary.isEmpty { return "" }
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(args),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "null" || trimmed == "{}" { return "" }
        return String(trimmed.unicodeScalars.prefix(Self.argumentsCharLimit))
    }

    /// The icon always carries the tool category color; the state lives in a small pill.
    private var kindTint: Color {
        ChatToolKindTint.color(for: self.display.name)
    }

    /// The card's accent bar follows the state first (running, failed, blocked), then the tool type.
    private var cardTint: Color {
        switch self.item.displayState {
        case .failed: return OpenClawChatTheme.danger
        case .blocked: return OpenClawChatTheme.warning
        case .running: return OpenClawChatTheme.info
        case .finished, .skipped, .unavailable: return self.kindTint
        }
    }

    private var stateTint: Color {
        switch self.item.displayState {
        case .running: return OpenClawChatTheme.info
        case .finished: return OpenClawChatTheme.success
        case .failed: return OpenClawChatTheme.danger
        case .blocked: return OpenClawChatTheme.warning
        case .skipped, .unavailable: return OpenClawChatTheme.inkMuted
        }
    }

    private var stateSymbol: String? {
        switch self.item.displayState {
        case .running: return nil
        case .finished: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .blocked: return "hand.raised.fill"
        case .skipped: return "forward.circle"
        case .unavailable: return "questionmark.circle"
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        if self.isDesktopLayout {
            if let symbol = self.stateSymbol {
                Image(systemName: symbol)
                    .font(OpenClawChatTypography.caption)
                    .foregroundStyle(self.stateTint)
                    .accessibilityHidden(true)
            }
        } else if self.item.displayState != .finished {
            self.statePill
        }
    }

    /// Discrete state cue (working, failed, blocked...), never a large colored frame.
    private var statePill: some View {
        let color: Color = self.stateTint
        return HStack(spacing: 3) {
            if let symbol = self.stateSymbol {
                Image(systemName: symbol)
                    .font(OpenClawChatTypography.body(size: 9, weight: .semibold, relativeTo: .caption2))
            }
            Text(self.item.displayState.title)
                .font(OpenClawChatTypography.captionSemiBold)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(color.opacity(0.12), in: Capsule())
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var collapsedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Group {
                if self.item.isPending {
                    ProgressView()
                        .controlSize(.mini)
                } else if self.expandable {
                    Image(systemName: "chevron.right")
                        .font(OpenClawChatTypography.body(size: 9, weight: .semibold, relativeTo: .caption2))
                        .foregroundStyle(OpenClawChatTheme.inkMuted)
                        .opacity(0.7)
                        .rotationEffect(.degrees(self.expanded ? 90 : 0))
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.disclosureWidth, height: 12)

            Image(systemName: ChatToolIcon.symbol(for: self.display.name, icon: self.display.icon))
                .font(OpenClawChatTypography.body(size: 12, weight: .medium, relativeTo: .footnote))
                .foregroundStyle(self.kindTint)

            if self.isDesktopLayout {
                VStack(alignment: .leading, spacing: 3) {
                    self.toolTitle
                    self.toolDetail
                }
            } else {
                self.toolTitle
                self.toolDetail
            }

            if let stat = self.displayedDiffStat {
                ChatDiffStatChips(stat: stat)
            }

            Spacer(minLength: 0)

            self.stateBadge

            // Desktop spells the state out; touch uses the pill above.
            if self.isDesktopLayout {
                Text(self.item.displayState.title)
                    .font(OpenClawChatTypography.caption)
                    .foregroundStyle(self.stateTint)
                    .fixedSize()
            }
        }
        .padding(.vertical, self.isDesktopLayout ? 3 : 5)
    }

    private var toolTitle: some View {
        Text(self.item.activity?.preparedTitle ?? self.display.title)
            .font(OpenClawChatTypography.footnoteSemiBold)
            .foregroundStyle(self.textColor)
            .lineLimit(1)
    }

    @ViewBuilder
    private var toolDetail: some View {
        if let detailLine = self.detailLine {
            Text(detailLine)
                .font(OpenClawChatTypography.mono(size: 12, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var textColor: Color {
        self.isDesktopLayout
            ? OpenClawChatTheme.desktopText(in: self.colorScheme, contrast: self.colorSchemeContrast)
            : OpenClawChatTheme.inkStrong
    }

    private var diffRows: some View {
        // The orthogonal nested scroll keeps long diff lines reachable without
        // competing with the transcript's vertical gesture.
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(self.expandedDiffLines.indices, id: \.self) { index in
                    self.diffRow(self.expandedDiffLines[index])
                }
            }
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func diffRow(_ line: ChatToolDiffLine) -> some View {
        if line.kind == .file {
            Text(verbatim: String(line.text.unicodeScalars.prefix(2000)))
                .font(OpenClawChatTypography.mono(size: 11, relativeTo: .caption))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 6)
        } else if line.kind == .skip {
            Text("⋯")
                .font(OpenClawChatTypography.mono(size: 12, relativeTo: .footnote))
                .foregroundStyle(.secondary.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
                // Reuses the existing localized "Collapsed" key so omitted
                // preview rows stay announced to assistive tech.
                .accessibilityLabel(Text("Collapsed"))
        } else {
            HStack(spacing: 6) {
                if let lineNo = line.lineNo {
                    Text(verbatim: "\(lineNo)")
                        .font(OpenClawChatTypography.mono(size: 10, relativeTo: .caption2))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .frame(minWidth: 34, alignment: .trailing)
                }
                // Bound per-line render work; generated/minified payloads can put
                // megabytes on a single line.
                Text(verbatim: String(line.text.unicodeScalars.prefix(2000)))
                    .font(OpenClawChatTypography.mono(size: 12, relativeTo: .footnote))
                    .foregroundStyle(self.diffTextColor(line.kind))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .background(self.diffBackground(line.kind))
            // Color alone must not carry add/del semantics for assistive tech.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Self.accessibilityText(for: line)))
        }
    }

    private static func accessibilityText(for line: ChatToolDiffLine) -> String {
        let lineNo = line.lineNo.map { "\($0) " } ?? ""
        return lineNo + self.accessibilityMarker(line.kind) + String(line.text.unicodeScalars.prefix(2000))
    }

    private static func accessibilityMarker(_ kind: ChatToolDiffLineKind) -> String {
        switch kind {
        case .add:
            "+ "
        case .del:
            "\u{2212} "
        case .ctx, .file, .skip:
            ""
        }
    }

    private func diffTextColor(_ kind: ChatToolDiffLineKind) -> Color {
        switch kind {
        case .add:
            OpenClawChatTheme.assistantText
        case .del, .ctx, .file, .skip:
            .secondary
        }
    }

    private func diffBackground(_ kind: ChatToolDiffLineKind) -> Color {
        switch kind {
        case .add:
            OpenClawChatTheme.success.opacity(0.14)
        case .del:
            OpenClawChatTheme.danger.opacity(0.12)
        case .ctx, .file, .skip:
            .clear
        }
    }
}

/// Category color per tool type: shell, reading, editing, searching, web, agents.
enum ChatToolKindTint {
    private static let shell: Set<String> = ["bash", "exec", "shell", "run_command", "run_terminal_cmd", "process"]
    private static let reading: Set<String> = ["read", "read_file", "readfile", "notebookread", "notebook_read"]
    private static let writing: Set<String> = [
        "edit", "edit_file", "multiedit", "multi_edit", "notebookedit", "notebook_edit",
        "apply_patch", "applypatch", "patch", "write", "write_file", "create_file",
    ]
    private static let searching: Set<String> = ["grep", "find", "glob", "ls", "list", "codebase_search"]
    private static let web: Set<String> = ["web_fetch", "webfetch", "fetch", "web_search", "browser"]

    static func color(for name: String) -> Color {
        let key: String = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if self.shell.contains(key) { return OpenClawChatTheme.brandAccent }
        if self.reading.contains(key) { return OpenClawChatTheme.info }
        if self.writing.contains(key) { return OpenClawChatTheme.warning }
        if self.searching.contains(key) { return OpenClawChatTheme.brandSecondary }
        if self.web.contains(key) { return OpenClawChatTheme.info }
        if key.contains("agent") || key.contains("session") || key.contains("spawn") {
            return OpenClawChatTheme.brandSecondary
        }
        return OpenClawChatTheme.inkMuted
    }
}

struct ChatWorkCardStyle: ViewModifier {
    @Environment(\.openClawChatDesktopLayout) private var isDesktopLayout
    @Environment(\.colorScheme) private var colorScheme

    var tint: Color = OpenClawChatTheme.inkMuted

    func body(content: Content) -> some View {
        if self.isDesktopLayout {
            self.desktopCard(content)
        } else {
            self.touchCard(content)
        }
    }

    private func desktopCard(_ content: Content) -> some View {
        content
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(self.colorScheme == .dark ? 0.035 : 0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
            }
    }

    /// Opaque card with a state/type accent bar on the leading edge. Never glass: this is content.
    private func touchCard(_ content: Content) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let bar: Color = self.tint
        return content
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OpenClawChatTheme.surfaceCard, in: shape)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(bar)
                    .frame(width: 3)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(OpenClawChatTheme.hairline, lineWidth: 1))
    }
}

struct ChatDiffStatChips: View {
    let stat: ChatToolDiffStat

    var body: some View {
        Group {
            Text(verbatim: "+\(self.stat.added)")
                .foregroundStyle(OpenClawChatTheme.success.opacity(0.9))
            Text(verbatim: "−\(self.stat.removed)")
                .foregroundStyle(OpenClawChatTheme.danger.opacity(0.9))
        }
        .font(OpenClawChatTypography.mono(size: 12, relativeTo: .footnote))
        .lineLimit(1)
    }
}

struct ChatToolActivityList: View {
    @Environment(\.openClawChatDesktopLayout) private var isDesktopLayout
    let items: [ChatToolActivityItem]

    /// Visible calls first, then the quiet ones; every call shows its name directly.
    private var orderedIndices: [Int] {
        let visible: [Int] = self.items.indices.filter { self.items[$0].isVisible }
        let quiet: [Int] = self.items.indices.filter { !self.items[$0].isVisible }
        return visible + quiet
    }

    private var rowSpacing: CGFloat {
        self.isDesktopLayout ? 6 : 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: self.rowSpacing) {
            ForEach(self.orderedIndices, id: \.self) { index in
                self.row(at: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(at index: Int) -> some View {
        let item: ChatToolActivityItem = self.items[index]
        let opacity: Double = item.isVisible ? 1 : 0.8
        return ChatToolActivityRow(item: item)
            .equatable()
            .opacity(opacity)
    }
}
