import Foundation

/// Pure display-name logic for model pickers and the composer model button.
///
/// - `listName`: readable model name for picker lists (no provider, no full id).
/// - `composerName`: same, with a leading "Claude" removed ("Claude Sonnet 5.5" -> "Sonnet 5.5").
/// - `derivedName(fromID:)`: when only an id is known ("omniroute/claude-sonnet-5-5" -> "Claude Sonnet 5.5").
public enum ChatModelDisplayName {
    private static let acronymTokens: Set<String> = ["gpt", "glm", "llm", "xai"]
    private static let claudePrefix: String = "claude"

    /// Readable name for a picker row. A name that merely repeats the id is treated as missing.
    public static func listName(name: String?, modelID: String) -> String {
        let bareID: String = Self.bareModelID(modelID)
        let fullID: String = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = Self.trimmed(name), name != bareID, name != fullID {
            return name
        }
        return Self.derivedName(fromID: modelID)
    }

    /// Name for the composer model button: the list name without a leading "Claude".
    public static func composerName(name: String?, modelID: String) -> String {
        Self.strippingClaudePrefix(Self.listName(name: name, modelID: modelID))
    }

    /// Derives a tidy name from an id: provider removed, dashes become spaces,
    /// consecutive 1-2 digit parts become a version ("5-5" -> "5.5"), trailing date dropped.
    public static func derivedName(fromID modelID: String) -> String {
        let bareID: String = Self.bareModelID(modelID)
        var tokens: [String] = bareID
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { String($0) }
        if tokens.count > 1, let last = tokens.last, Self.isDateStamp(last) {
            tokens.removeLast()
        }
        var words: [String] = []
        var index: Int = 0
        while index < tokens.count {
            let token: String = tokens[index]
            if Self.isVersionComponent(token) {
                var version: String = token
                var next: Int = index + 1
                while next < tokens.count, Self.isVersionComponent(tokens[next]) {
                    version += "." + tokens[next]
                    next += 1
                }
                words.append(version)
                index = next
            } else {
                words.append(Self.capitalizedToken(token))
                index += 1
            }
        }
        let joined: String = words.joined(separator: " ")
        return joined.isEmpty ? modelID : joined
    }

    /// Removes a leading "Claude" word (any case) when something meaningful remains.
    public static func strippingClaudePrefix(_ name: String) -> String {
        let trimmedName: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.lowercased().hasPrefix(Self.claudePrefix) else { return trimmedName }
        let rest: Substring = trimmedName.dropFirst(Self.claudePrefix.count)
        guard let first = rest.first, Self.isSeparator(first) else { return trimmedName }
        let stripped: Substring = rest.drop(while: { Self.isSeparator($0) })
        return stripped.isEmpty ? trimmedName : String(stripped)
    }

    // MARK: - Helpers

    static func bareModelID(_ modelID: String) -> String {
        let trimmedID: String = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts: [Substring] = trimmedID.split(separator: "/", omittingEmptySubsequences: true)
        guard let last = parts.last else { return trimmedID }
        return String(last)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == " " || character == "-" || character == "_"
    }

    private static func isDateStamp(_ token: String) -> Bool {
        token.count == 8 && token.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isVersionComponent(_ token: String) -> Bool {
        let length: Int = token.count
        return length >= 1 && length <= 2 && token.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func capitalizedToken(_ token: String) -> String {
        if Self.acronymTokens.contains(token.lowercased()) {
            return token.uppercased()
        }
        guard let first = token.first else { return token }
        return String(first).uppercased() + token.dropFirst()
    }
}

extension OpenClawChatModelChoice {
    /// Readable name for picker lists (no provider, no full id).
    public var pickerName: String {
        ChatModelDisplayName.listName(name: self.name, modelID: self.modelID)
    }

    /// Name for the composer model button ("Sonnet 5.5").
    public var composerName: String {
        ChatModelDisplayName.composerName(name: self.name, modelID: self.modelID)
    }
}
