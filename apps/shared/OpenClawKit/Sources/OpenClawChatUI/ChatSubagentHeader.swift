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

// Explicit key: some SwiftPM toolchains lack the SwiftUI macro plugins that `@Entry` needs.
// swiftformat:disable environmentEntry
private struct OpenClawChatSubagentHeaderHiddenKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// A host that draws its own subagent header (name, sprite, state, Stop) sets this to `true`
    /// so the built-in strip does not render twice. Defaults to `false`.
    public var openClawChatSubagentHeaderHidden: Bool {
        get { self[OpenClawChatSubagentHeaderHiddenKey.self] }
        set { self[OpenClawChatSubagentHeaderHiddenKey.self] = newValue }
    }
}
// swiftformat:enable environmentEntry

/// Name and a single status line on a flat strip: no glass, no icon row, no extra controls.
struct ChatSubagentHeader: View {
    @Environment(\.openClawChatSubagentHeaderHidden) private var isHidden
    @Environment(\.colorScheme) private var colorScheme

    let model: ChatSubagentHeaderModel

    @ViewBuilder
    var body: some View {
        if !self.isHidden {
            self.strip
        }
    }

    private var strip: some View {
        let tint: Color = ChatSubagentHeaderTint.color(for: self.model.name, scheme: self.colorScheme)
        return HStack(spacing: 8) {
            ChatAgentAvatar(text: nil, name: self.model.name, tint: tint, size: 24)
                .accessibilityHidden(true)
            Text(self.model.name)
                .font(OpenClawChatTypography.footnoteSemiBold)
                .foregroundStyle(OpenClawChatTheme.inkStrong)
                .lineLimit(1)
                .truncationMode(.tail)
            self.statusPill
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenClawChatTheme.surfaceAlt)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint)
                .frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OpenClawChatTheme.hairline)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(self.model.name), \(self.model.status.label)"))
        .openClawChatAnimation(value: self.model.status)
    }

    private var statusPill: some View {
        let color: Color = self.statusColor
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(self.model.status.label)
                .font(OpenClawChatTypography.captionSemiBold)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch self.model.status {
        case .running: return OpenClawChatTheme.info
        case .waiting: return OpenClawChatTheme.warning
        case .done: return OpenClawChatTheme.success
        case .failed: return OpenClawChatTheme.danger
        case .idle: return OpenClawChatTheme.inkMuted
        }
    }
}

/// A stable hue per agent name, taken from the session palette, so each helper keeps its own color.
enum ChatSubagentHeaderTint {
    static func color(for name: String, scheme: ColorScheme) -> Color {
        let all: [OpenClawSessionColor] = OpenClawSessionColor.allCases
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let index: Int = Int(hash % UInt64(all.count))
        return all[index].tint(in: scheme)
    }
}
