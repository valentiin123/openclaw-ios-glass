import SwiftUI

/// AgentsHub reuses the app-wide motion vocabulary (`OpenClawMotion`): one spring, cross-fade under Reduce Motion.
enum AgentsHubMotion {
    static func animation(reduceMotion: Bool) -> Animation {
        OpenClawMotion.animation(reduceMotion: reduceMotion)
    }
}

private struct AgentsHubAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(AgentsHubMotion.animation(reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Applies the shared spring unless Reduce Motion is enabled.
    func agentsHubAnimation<V: Equatable>(value: V) -> some View {
        modifier(AgentsHubAnimation(value: value))
    }
}

extension AgentsHubRunStatus {
    /// Semantic colors: red = failed, orange = attention/waiting, green = done/healthy, accent = running.
    var tint: Color {
        switch self {
        case .running: .accentColor
        case .waitingOnChildren: .orange
        case .failed: .red
        case .done: .green
        case .idle: .secondary
        }
    }
}

/// Status glyph + text (never color alone).
struct AgentsHubStatusBadge: View {
    let status: AgentsHubRunStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(OpenClawType.captionSemiBold)
            .foregroundStyle(status.tint)
            .labelStyle(.titleAndIcon)
    }
}

/// Shown while the tree is being followed (active runs). Glyph + text, no animation of its own.
struct AgentsHubLiveBadge: View {
    var body: some View {
        Label("Live", systemImage: "dot.radiowaves.left.and.right")
            .font(OpenClawType.caption2SemiBold)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel(Text("Live updates"))
    }
}

/// Inline error with an optional retry button (44 pt target).
struct AgentsHubErrorRow: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(OpenClawType.subhead)
                .foregroundStyle(.red)
            if let retry {
                Button("Retry", action: retry)
                    .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

enum AgentsHubFormat {
    static func duration(ms: Double?) -> String? {
        guard let ms, ms > 0 else { return nil }
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f.string(from: ms / 1000)
    }

    /// `ms` is an epoch timestamp in milliseconds.
    static func date(ms: Double?) -> String? {
        guard let ms, ms > 0 else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func tokens(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return count.formatted()
    }
}
