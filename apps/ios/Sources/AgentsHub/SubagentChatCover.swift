import Observation
import OpenClawChatUI
import SwiftUI

// Full-screen host for the subagent chat. A full-screen cover hides the tab bar, so the composer
// (a bottom safe-area inset of `OpenClawChatView`) sits on the keyboard and never overlaps it.
// Children are pushed inside the cover's own NavigationStack (edge swipe-back keeps working).
// Compiler hygiene: typed constants, small @ViewBuilder properties, no nested trailing closures.

// MARK: - Request and route

/// What the shell presents: the session key of the subagent to open.
struct SubagentChatRequest: Identifiable, Hashable, Sendable {
    let key: String
    /// Global frame of the tapped tile (zoom origin). Nil -> plain cross-fade.
    var sourceRect: CGRect?
    var id: String { self.key }
}

/// One pushed subagent (a child of the one below it in the stack).
struct SubagentChatRoute: Hashable, Sendable {
    let key: String
}

// MARK: - Stack model

/// Reference type so the `@Sendable` environment hook can push a child without capturing a Binding.
@MainActor
@Observable
final class SubagentChatStackModel {
    var path: [SubagentChatRoute] = []

    /// Set by the zoom host: the root screen closes through it (reverse animation) instead of `dismiss`.
    @ObservationIgnored var onCloseRoot: (@MainActor () -> Void)?

    func open(_ key: String) {
        let trimmed: String = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if self.path.last?.key == trimmed { return }
        let route: SubagentChatRoute = SubagentChatRoute(key: trimmed)
        self.path.append(route)
    }
}

// MARK: - Presenter

/// Owns the "which subagent chat is open" state of a host (tab content or the system chat cover).
/// A reference type so the `openClawChatOpenSubagent` hook (`@Sendable`) can drive it.
@MainActor
@Observable
final class SubagentChatPresenter {
    var request: SubagentChatRequest?

    func open(_ key: String) {
        let trimmed: String = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.request = SubagentChatRequest(key: trimmed)
    }

    /// Zoom host: presents WITHOUT the system animation; the host animates the frame itself.
    func open(_ key: String, from rect: CGRect?) {
        let trimmed: String = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let value: SubagentChatRequest = SubagentChatRequest(key: trimmed, sourceRect: rect)
        self.setRequest(value)
    }

    /// Called by the zoom host once the reverse animation is done.
    func finishClose() {
        self.setRequest(nil)
    }

    private func setRequest(_ value: SubagentChatRequest?) {
        var transaction: Transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.request = value
        }
    }

    /// Hook for the zoom host (no tile frame -> cross-fade).
    var zoomHook: OpenClawChatOpenSubagent {
        let presenter: SubagentChatPresenter = self
        let hook: OpenClawChatOpenSubagent = { key in
            presenter.open(key, from: nil)
        }
        return hook
    }

    /// Host hook handed to `OpenClawChatView` through `openClawChatOpenSubagent`.
    var openHook: OpenClawChatOpenSubagent {
        let presenter: SubagentChatPresenter = self
        let hook: OpenClawChatOpenSubagent = { key in
            presenter.open(key)
        }
        return hook
    }
}

// MARK: - Cover

struct SubagentChatCover: View {
    let rootKey: String
    let onCloseRoot: (@MainActor () -> Void)?

    @State private var stack: SubagentChatStackModel = SubagentChatStackModel()

    init(rootKey: String, onCloseRoot: (@MainActor () -> Void)? = nil) {
        self.rootKey = rootKey
        self.onCloseRoot = onCloseRoot
    }

    private var pathBinding: Binding<[SubagentChatRoute]> {
        Binding<[SubagentChatRoute]>(
            get: { self.stack.path },
            set: { newValue in self.stack.path = newValue })
    }

    var body: some View {
        NavigationStack(path: self.pathBinding) {
            self.screen(key: self.rootKey, isRoot: true)
                .navigationDestination(for: SubagentChatRoute.self) { route in
                    self.screen(key: route.key, isRoot: false)
                }
        }
        .accessibilityIdentifier("AppShell.SubagentChat")
        .onAppear(perform: self.installCloseHandler)
    }

    private func installCloseHandler() {
        self.stack.onCloseRoot = self.onCloseRoot
    }

    private func screen(key: String, isRoot: Bool) -> some View {
        SubagentChatScreen(sessionKey: key, isRoot: isRoot, stack: self.stack)
            .id(key)
    }
}

// MARK: - Presentation

private struct SubagentChatPresentation: ViewModifier {
    @Bindable var presenter: SubagentChatPresenter

    func body(content: Content) -> some View {
        content
            .environment(\.openClawChatOpenSubagent, self.presenter.openHook)
            .fullScreenCover(item: self.$presenter.request) { request in
                SubagentChatCover(rootKey: request.key)
            }
    }
}

extension View {
    /// Presents the subagent chat full screen. Attach it to a view that is not already presenting.
    func subagentChatCover(item: Binding<SubagentChatRequest?>) -> some View {
        self.fullScreenCover(item: item) { request in
            SubagentChatCover(rootKey: request.key)
        }
    }

    /// Wires `openClawChatOpenSubagent` for every chat below this view and presents the subagent
    /// chat full screen (no tab bar underneath) when a helper is opened.
    func subagentChatPresentation(presenter: SubagentChatPresenter) -> some View {
        modifier(SubagentChatPresentation(presenter: presenter))
    }
}
