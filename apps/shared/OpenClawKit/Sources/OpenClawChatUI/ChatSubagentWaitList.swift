import SwiftUI

/// Host hook: open the chat of a subagent. The app target supplies it; OpenClawChatUI cannot
/// import the app. `nil` falls back to switching the current chat session in place.
public typealias OpenClawChatOpenSubagent = @MainActor @Sendable (_ sessionKey: String) -> Void

// Explicit key: some SwiftPM toolchains lack the SwiftUI macro plugins that `@Entry` needs.
// swiftformat:disable environmentEntry
private struct OpenClawChatOpenSubagentKey: EnvironmentKey {
    static let defaultValue: OpenClawChatOpenSubagent? = nil
}

extension EnvironmentValues {
    public var openClawChatOpenSubagent: OpenClawChatOpenSubagent? {
        get { self[OpenClawChatOpenSubagentKey.self] }
        set { self[OpenClawChatOpenSubagentKey.self] = newValue }
    }
}
// swiftformat:enable environmentEntry

/// "Waiting on N subagents" with one tappable row per helper, on an opaque surface.
/// The list can be tucked away into a small button (with the helper count) and brought back;
/// the choice is remembered for the chat session in `OpenClawChatSubagentListState`.
struct ChatSubagentWaitList: View {
    @Environment(\.openClawChatOpenSubagent) private var openSubagent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let wait: ChatSubagentWait
    let fallbackOpen: @MainActor (String) -> Void
    /// Chat session the list belongs to. `nil` shares one remembered state across chats.
    let sessionKey: String?

    @State private var collapsed: Bool

    private static let sharedStateKey: String = "subagent-wait"
    private static let minimumTarget: CGFloat = 44

    init(
        wait: ChatSubagentWait,
        fallbackOpen: @escaping @MainActor (String) -> Void,
        sessionKey: String? = nil)
    {
        self.wait = wait
        self.fallbackOpen = fallbackOpen
        self.sessionKey = sessionKey
        let key: String = Self.stateKey(for: sessionKey)
        let initial: Bool = OpenClawChatSubagentListState.shared.isCollapsed(key)
        self._collapsed = State(initialValue: initial)
    }

    private static func stateKey(for sessionKey: String?) -> String {
        guard let sessionKey, !sessionKey.isEmpty else { return Self.sharedStateKey }
        return "\(Self.sharedStateKey):\(sessionKey)"
    }

    /// Tucking away only makes sense when there is something to tuck.
    private var isTucked: Bool {
        self.collapsed && !self.wait.children.isEmpty
    }

    private var transition: AnyTransition {
        if self.reduceMotion { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if self.isTucked {
                self.tuckedButton
                    .transition(self.transition)
            } else {
                self.expandedContent
                    .transition(self.transition)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .openClawChatAnimation(value: self.wait.children)
        .openClawChatAnimation(value: self.collapsed)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-subagent-wait")
    }

    // MARK: Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.headerRow
            if !self.wait.children.isEmpty {
                self.childList
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 7) {
            self.header
            Spacer(minLength: 0)
            self.tuckButton
        }
    }

    private var childList: some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(self.wait.children) { child in
                self.row(child)
                if child.id != self.wait.children.last?.id {
                    Divider().overlay(OpenClawChatTheme.hairline)
                }
            }
        }
        .background(OpenClawChatTheme.surfaceCard, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(OpenClawChatTheme.hairline, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 7) {
            ChatWorkingClawView(seed: "subagent-wait", parked: true)
            Text(self.headerText)
                .font(OpenClawChatTypography.captionSemiBold)
                .foregroundStyle(OpenClawChatTheme.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    /// Tucks the list away. Only offered once the roster is known.
    @ViewBuilder
    private var tuckButton: some View {
        if !self.wait.children.isEmpty {
            Button {
                self.setCollapsed(true)
            } label: {
                Image(systemName: "chevron.up")
                    .font(OpenClawChatTypography.body(size: 12, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(OpenClawChatTheme.inkMuted)
                    .frame(width: Self.minimumTarget, height: Self.minimumTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Hide subagents"))
            .accessibilityIdentifier("chat-subagent-wait-hide")
        }
    }

    // MARK: Tucked

    /// Small opaque button with the helper count; content surface, so no Liquid Glass.
    private var tuckedButton: some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let count: Int = self.wait.children.count
        let countText: String = "\(count)"
        let format: String = String(localized: "%lld subagents")
        let value: String = String(format: format, Int64(count))
        return Button {
            self.setCollapsed(false)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.2")
                    .font(OpenClawChatTypography.body(size: 14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(OpenClawChatTheme.inkStrong)
                Text(verbatim: countText)
                    .font(OpenClawChatTypography.captionSemiBold)
                    .foregroundStyle(OpenClawChatTheme.inkMuted)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(minWidth: Self.minimumTarget, minHeight: Self.minimumTarget)
            .background(OpenClawChatTheme.surfaceCard, in: shape)
            .overlay(shape.strokeBorder(OpenClawChatTheme.hairline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show subagents"))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityIdentifier("chat-subagent-wait-show")
    }

    private func setCollapsed(_ value: Bool) {
        let key: String = Self.stateKey(for: self.sessionKey)
        OpenClawChatSubagentListState.shared.setCollapsed(value, for: key)
        OpenClawChatMotion.perform(reduceMotion: self.reduceMotion) {
            self.collapsed = value
        }
    }

    // MARK: Rows

    private func statusColor(_ status: OpenClawChatSwarmDotStatus) -> Color {
        switch status {
        case .running: return OpenClawChatTheme.info
        case .queued: return OpenClawChatTheme.inkMuted
        case .done: return OpenClawChatTheme.success
        case .failed: return OpenClawChatTheme.danger
        }
    }

    private var headerText: String {
        let count: Int = self.wait.children.count
        if count == 0 {
            return String(localized: "Waiting on subagents")
        }
        if count == 1 {
            return String(localized: "Waiting on 1 subagent")
        }
        let format: String = String(localized: "Waiting on %lld subagents")
        return String(format: format, Int64(count))
    }

    private func row(_ child: ChatSubagentWait.Child) -> some View {
        Button {
            self.open(child.key)
        } label: {
            HStack(spacing: 10) {
                self.indicator(for: child.status)
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: child.name)
                        .font(OpenClawChatTypography.footnoteSemiBold)
                        .foregroundStyle(OpenClawChatTheme.inkStrong)
                        .lineLimit(1)
                    Text(child.status.label)
                        .font(OpenClawChatTypography.caption2)
                        .foregroundStyle(self.statusColor(child.status))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat-subagent-wait-child")
        .accessibilityHint(Text("Opens the subagent chat"))
    }

    @ViewBuilder
    private func indicator(for status: OpenClawChatSwarmDotStatus) -> some View {
        switch status {
        case .running:
            if self.reduceMotion {
                Circle()
                    .fill(OpenClawChatTheme.info)
                    .frame(width: 9, height: 9)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(OpenClawChatTheme.info)
            }
        case .queued:
            Circle()
                .strokeBorder(OpenClawChatTheme.inkMuted, lineWidth: 1.5)
                .frame(width: 9, height: 9)
        case .done:
            Circle()
                .fill(OpenClawChatTheme.success)
                .frame(width: 9, height: 9)
        case .failed:
            Circle()
                .fill(OpenClawChatTheme.danger)
                .frame(width: 9, height: 9)
        }
    }

    private func open(_ key: String) {
        if let openSubagent = self.openSubagent {
            openSubagent(key)
        } else {
            self.fallbackOpen(key)
        }
    }
}
