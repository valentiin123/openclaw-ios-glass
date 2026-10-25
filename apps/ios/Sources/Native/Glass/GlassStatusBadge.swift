import SwiftUI

// Small animated state indicators for agent / subagent tiles.
// - Running: a rotating arc (static arc under Reduce Motion).
// - Done: a check mark that bounces once when the state flips.
// - Failed: an alert glyph that wiggles once when the state flips.
// The badge sits INSIDE a glass tile, so it is a flat tinted disc (no glass on glass).
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Phase

/// Coarse phase derived from the playful `AgentTileState` wording.
enum AgentGlassPhase: Equatable, Sendable {
    case running
    case done
    case failed
    case idle

    init(_ state: AgentTileState) {
        switch state {
        case .working, .thinking, .reading, .searching, .writing, .delegating, .queued:
            self = .running
        case .done:
            self = .done
        case .failed, .stuck:
            self = .failed
        case .napping, .hungry:
            self = .idle
        }
    }

    var tint: Color {
        switch self {
        case .running: OpenClawBrand.info
        case .done: OpenClawBrand.ok
        case .failed: OpenClawBrand.danger
        case .idle: OpenClawBrand.textSecondary
        }
    }

    var symbol: String {
        switch self {
        case .running: "arrow.triangle.2.circlepath"
        case .done: "checkmark"
        case .failed: "exclamationmark"
        case .idle: "moon.zzz.fill"
        }
    }

    /// Changes whenever the phase changes; drives one-shot symbol effects.
    var pulseKey: Int {
        switch self {
        case .running: 1
        case .done: 2
        case .failed: 3
        case .idle: 4
        }
    }
}

// MARK: - Spinner

private struct AgentGlassSpinnerArc: View {
    let tint: Color
    let animated: Bool

    @State private var spinning: Bool = false

    private let lineWidth: CGFloat = 2.5

    var body: some View {
        let degrees: Double = self.spinning ? 360 : 0
        return Circle()
            .trim(from: 0.08, to: 0.72)
            .stroke(self.tint, style: StrokeStyle(lineWidth: self.lineWidth, lineCap: .round))
            .rotationEffect(.degrees(degrees))
            .onAppear(perform: self.start)
    }

    private func start() {
        guard self.animated, !self.spinning else { return }
        let loop: Animation = .linear(duration: 1.0).repeatForever(autoreverses: false)
        withAnimation(loop) {
            self.spinning = true
        }
    }
}

// MARK: - Badge

struct AgentGlassStatusBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: AgentTileState
    var size: CGFloat = 20

    private var phase: AgentGlassPhase {
        AgentGlassPhase(self.state)
    }

    private var effectKey: Int {
        self.reduceMotion ? 0 : self.phase.pulseKey
    }

    private var inset: CGFloat {
        self.size * 0.24
    }

    var body: some View {
        ZStack {
            self.glyph
                .id(self.phase)
                .transition(OpenClawMotion.appear(reduceMotion: self.reduceMotion))
        }
        .frame(width: self.size, height: self.size)
        .background(self.phase.tint.opacity(0.16), in: Circle())
        .animation(OpenClawMotion.animation(reduceMotion: self.reduceMotion), value: self.phase)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch self.phase {
        case .running:
            AgentGlassSpinnerArc(tint: self.phase.tint, animated: !self.reduceMotion)
                .padding(self.inset)
        case .failed:
            self.symbolView
                .symbolEffect(.wiggle, value: self.effectKey)
        case .done:
            self.symbolView
                .symbolEffect(.bounce, value: self.effectKey)
        case .idle:
            self.symbolView
        }
    }

    private var symbolView: some View {
        let fontSize: CGFloat = self.size * 0.5
        return Image(systemName: self.phase.symbol)
            .font(OpenClawType.avatar(size: fontSize))
            .foregroundStyle(self.phase.tint)
    }
}

// MARK: - Progress bar

/// Thin determinate bar (flat, no glass). The fill glides with the shared spring.
struct AgentGlassProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double
    let tint: Color
    var height: CGFloat = 4

    private var clamped: Double {
        min(max(self.progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            self.bar(width: proxy.size.width)
        }
        .frame(height: self.height)
        .animation(OpenClawMotion.animation(reduceMotion: self.reduceMotion), value: self.clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(self.clamped, format: .percent.precision(.fractionLength(0))))
    }

    private func bar(width: CGFloat) -> some View {
        let fillWidth: CGFloat = max(self.height, width * CGFloat(self.clamped))
        return ZStack(alignment: .leading) {
            Capsule().fill(Color(uiColor: .tertiarySystemFill))
            Capsule().fill(self.tint).frame(width: fillWidth)
        }
    }
}
