import SwiftUI

/// One action revealed by swiping a sidebar row to the right.
struct SessionSwipeAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let perform: () -> Void
}

/// Swipe-to-reveal actions for rows living in a `ScrollView` (where `.swipeActions` is unavailable).
///
/// The tray opens on a rightward drag only. Leftward drags belong to the sidebar shell
/// (closing the drawer), so the two recognizers never compete for the same direction.
/// Every action is also exposed as a VoiceOver custom action, and the tray follows the
/// finger, then settles on the shared `OpenClawMotion` spring (fade under Reduce Motion).
struct SessionSwipeActionsModifier: ViewModifier {
    private enum Metric {
        static let actionWidth: CGFloat = 64
        static let minimumHeight: CGFloat = 44
        static let activationDistance: CGFloat = 16
        static let settleFraction: CGFloat = 0.4
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = false
    @GestureState private var dragWidth: CGFloat = 0

    let actions: [SessionSwipeAction]
    let isEnabled: Bool

    private var trayWidth: CGFloat {
        Metric.actionWidth * CGFloat(self.actions.count)
    }

    private var revealedWidth: CGFloat {
        let base = self.isOpen ? self.trayWidth : 0
        return min(self.trayWidth, max(0, base + self.dragWidth))
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if self.isEnabled, !self.actions.isEmpty {
            ZStack(alignment: .leading) {
                if self.revealedWidth > 0 {
                    self.tray
                }
                content
                    .background(OpenClawSidebarPalette.background)
                    .offset(x: self.reduceMotion ? 0 : self.revealedWidth)
                    .opacity(self.reduceMotion && self.isOpen ? 0.4 : 1)
                    .allowsHitTesting(!self.isOpen)
                    .simultaneousGesture(self.dragGesture)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: self.isOpen)
            .accessibilityElement(children: .contain)
            .modifier(AccessibilitySwipeActions(actions: self.actions))
        } else {
            content
        }
    }

    private var tray: some View {
        HStack(spacing: 0) {
            ForEach(self.actions) { action in
                Button {
                    self.close()
                    action.perform()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: action.systemImage)
                            .font(OpenClawType.subheadSemiBold)
                        Text(verbatim: action.title)
                            .font(OpenClawType.caption2Medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Color.white)
                    .frame(width: Metric.actionWidth)
                    .frame(maxHeight: .infinity)
                    .frame(minHeight: Metric.minimumHeight)
                    .background(action.tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: self.trayWidth)
        .clipShape(RoundedRectangle(cornerRadius: OpenClawProMetric.controlRadius, style: .continuous))
        .opacity(self.trayOpacity)
    }

    private var trayOpacity: Double {
        guard self.trayWidth > 0 else { return 0 }
        return Double(min(1, self.revealedWidth / self.trayWidth))
    }

    private var dragGesture: some Gesture {
        let trayWidth = self.trayWidth
        let isOpen = self.isOpen
        return DragGesture(minimumDistance: Metric.activationDistance)
            .updating(self.$dragWidth) { value, state, _ in
                let width = value.translation.width
                let height = value.translation.height
                // Horizontal intent only; vertical scrolling keeps priority.
                guard abs(width) > 2 * abs(height) else { return }
                // Closed: only rightward opens. Open: only leftward closes.
                state = isOpen ? min(0, max(-trayWidth, width)) : max(0, min(trayWidth, width))
            }
            .onEnded { value in
                let width = value.translation.width
                let height = value.translation.height
                guard abs(width) > 2 * abs(height) else { return }
                let threshold = trayWidth * Metric.settleFraction
                OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
                    if isOpen {
                        if -width > threshold { self.isOpen = false }
                    } else if width > threshold {
                        self.isOpen = true
                    }
                }
            }
    }

    private func close() {
        OpenClawMotion.perform(reduceMotion: self.reduceMotion) {
            self.isOpen = false
        }
    }
}

private struct AccessibilitySwipeActions: ViewModifier {
    let actions: [SessionSwipeAction]

    func body(content: Content) -> some View {
        self.actions.reduce(AnyView(content)) { view, action in
            AnyView(view.accessibilityAction(named: Text(verbatim: action.title)) {
                action.perform()
            })
        }
    }
}

extension View {
    /// Rightward swipe reveals `actions` (pin, snooze, archive...). No-op when disabled or empty.
    func sessionSwipeActions(_ actions: [SessionSwipeAction], isEnabled: Bool = true) -> some View {
        modifier(SessionSwipeActionsModifier(actions: actions, isEnabled: isEnabled))
    }
}
