import SwiftUI

/// Injection point for rich fenced blocks (```chart, ```svg, ```html).
///
/// OpenClawChatUI is a shared package and cannot import the app's `Widgets` module.
/// The host app supplies a renderer (typically wrapping `WidgetCardView`) through the
/// environment. Returning `nil` falls back to the regular code block, so hosts that
/// provide nothing keep the previous behavior. Canvas-URL widgets still go through
/// `ChatInlineWidgetView`.
public struct OpenClawChatRichBlockRenderer: Sendable {
    public static let supportedLanguages: Set<String> = ["chart", "svg", "html"]

    public let render: @MainActor @Sendable (_ language: String, _ body: String) -> AnyView?

    public init(render: @escaping @MainActor @Sendable (_ language: String, _ body: String) -> AnyView?) {
        self.render = render
    }
}

extension EnvironmentValues {
    @Entry public var openClawChatRichBlockRenderer: OpenClawChatRichBlockRenderer?
}
