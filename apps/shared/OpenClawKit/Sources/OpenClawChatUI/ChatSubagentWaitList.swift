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
struct ChatSubagentWaitList: View {
    @Environment(\.openClawChatOpenSubagent) private var openSubagent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let wait: ChatSubagentWait
    let fallbackOpen: @MainActor (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.header
            if !self.wait.children.isEmpty {
                VStack(spacing: 0) {
                    ForEach(self.wait.children) { child in
                        self.row(child)
                        if child.id != self.wait.children.last?.id {
                            Divider().overlay(OpenClawChatTheme.divider)
                        }
                    }
                }
                .background(
                    OpenClawChatTheme.subtleCard,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(OpenClawChatTheme.divider, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .openClawChatAnimation(value: self.wait.children)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-subagent-wait")
    }

    private var header: some View {
        HStack(spacing: 7) {
            ChatWorkingClawView(seed: "subagent-wait", parked: true)
            Text(self.headerText)
                .font(OpenClawChatTypography.caption)
                .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: child.name)
                        .font(OpenClawChatTypography.footnote)
                        .foregroundStyle(OpenClawChatTheme.assistantText)
                        .lineLimit(1)
                    Text(child.status.label)
                        .font(OpenClawChatTypography.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                self.indicator(for: child.status)
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
        .accessibilityIdentifier("chat-subagent-wait-child")
        .accessibilityHint(Text("Opens the subagent chat"))
    }

    @ViewBuilder
    private func indicator(for status: OpenClawChatSwarmDotStatus) -> some View {
        switch status {
        case .running:
            if self.reduceMotion {
                Circle()
                    .fill(OpenClawChatTheme.accent)
                    .frame(width: 7, height: 7)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        case .queued:
            Circle()
                .stroke(OpenClawChatTheme.muted, lineWidth: 1)
                .frame(width: 7, height: 7)
        case .done:
            Circle()
                .fill(OpenClawChatTheme.success)
                .frame(width: 7, height: 7)
        case .failed:
            Circle()
                .fill(OpenClawChatTheme.danger)
                .frame(width: 7, height: 7)
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
