import SwiftUI

/// What the minimal subagent header needs: a name and one status.
struct ChatSubagentHeaderModel: Equatable {
    enum Status: Equatable {
        case running
        case waiting
        case done
        case failed
        case idle

        var label: String {
            switch self {
            case .running: String(localized: "Working")
            case .waiting: String(localized: "Waiting on helpers")
            case .done: String(localized: "Done")
            case .failed: String(localized: "Failed")
            case .idle: String(localized: "Idle")
            }
        }
    }

    let name: String
    let status: Status

    static func resolve(sessionKey: String, session: OpenClawChatSessionEntry?) -> ChatSubagentHeaderModel? {
        guard sessionKey.contains(":subagent:") else { return nil }
        guard let session else {
            return ChatSubagentHeaderModel(name: String(localized: "Subagent"), status: .idle)
        }
        let name = ChatSessionSidebarModel.displayName(for: session)
        return ChatSubagentHeaderModel(name: name, status: Self.status(of: session))
    }

    private static func status(of session: OpenClawChatSessionEntry) -> Status {
        if let raw = session.status {
            switch raw {
            case "queued", "running":
                return .running
            case "failed", "error", "timeout", "killed":
                return .failed
            case "done", "completed", "succeeded":
                return session.hasActiveSubagentRun == true ? .waiting : .done
            default:
                break
            }
        }
        if session.hasActiveRun == true { return .running }
        if session.hasActiveSubagentRun == true { return .waiting }
        if session.lastRunError != nil { return .failed }
        if session.endedAt != nil { return .done }
        return .idle
    }
}

/// Name and a single status line on a flat strip: no glass, no icon row, no extra controls.
struct ChatSubagentHeader: View {
    let model: ChatSubagentHeaderModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(self.dotColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(self.model.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OpenClawChatTheme.assistantText)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(self.model.status.label)
                .font(OpenClawChatTypography.caption)
                .foregroundStyle(OpenClawChatTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OpenClawChatTheme.divider)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(self.model.name), \(self.model.status.label)"))
        .openClawChatAnimation(value: self.model.status)
    }

    private var dotColor: Color {
        switch self.model.status {
        case .running: OpenClawChatTheme.muted
        case .waiting: OpenClawChatTheme.muted.opacity(0.6)
        case .done: Color.green
        case .failed: OpenClawChatTheme.danger
        case .idle: OpenClawChatTheme.muted.opacity(0.4)
        }
    }
}
