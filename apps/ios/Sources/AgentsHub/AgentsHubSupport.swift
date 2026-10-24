import SwiftUI

/// Single spring used by every AgentsHub transition. Disabled when Reduce Motion is on.
enum AgentsHubMotion {
    static let spring = Animation.spring(duration: 0.35, bounce: 0.15)
}

private struct AgentsHubAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : AgentsHubMotion.spring, value: value)
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .labelStyle(.titleAndIcon)
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
}
