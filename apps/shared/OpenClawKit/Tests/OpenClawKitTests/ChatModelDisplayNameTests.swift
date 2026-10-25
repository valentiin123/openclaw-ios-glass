import Foundation
import Testing
@testable import OpenClawChatUI

struct ChatModelDisplayNameTests {
    @Test func `list name uses the readable name when one exists`() {
        let label: String = ChatModelDisplayName.listName(name: "Claude Sonnet 5.5", modelID: "omniroute/claude-sonnet-5-5")
        #expect(label == "Claude Sonnet 5.5")
    }

    @Test func `list name derives a tidy name from the id when the name is missing or repeats the id`() {
        let missing: String = ChatModelDisplayName.listName(name: nil, modelID: "omniroute/claude-sonnet-5-5")
        let empty: String = ChatModelDisplayName.listName(name: "  ", modelID: "omniroute/claude-sonnet-5-5")
        let repeated: String = ChatModelDisplayName.listName(
            name: "omniroute/claude-sonnet-5-5",
            modelID: "omniroute/claude-sonnet-5-5")
        #expect(missing == "Claude Sonnet 5.5")
        #expect(empty == "Claude Sonnet 5.5")
        #expect(repeated == "Claude Sonnet 5.5")
    }

    @Test func `composer name drops the Claude prefix`() {
        let fromName: String = ChatModelDisplayName.composerName(name: "Claude Sonnet 5.5", modelID: "x/claude-sonnet-5-5")
        let fromID: String = ChatModelDisplayName.composerName(name: nil, modelID: "omniroute/claude-sonnet-5-5")
        #expect(fromName == "Sonnet 5.5")
        #expect(fromID == "Sonnet 5.5")
    }

    @Test func `composer name keeps non Claude names`() {
        let label: String = ChatModelDisplayName.composerName(name: "GPT-5", modelID: "openai/gpt-5")
        #expect(label == "GPT-5")
    }

    @Test func `stripping Claude prefix leaves a bare Claude name alone`() {
        #expect(ChatModelDisplayName.strippingClaudePrefix("Claude") == "Claude")
        #expect(ChatModelDisplayName.strippingClaudePrefix("Claudette 2") == "Claudette 2")
    }

    @Test func `derived name drops provider, date stamp and joins version parts`() {
        #expect(ChatModelDisplayName.derivedName(fromID: "anthropic/claude-opus-4-1-20250805") == "Claude Opus 4.1")
        #expect(ChatModelDisplayName.derivedName(fromID: "openai/gpt-5") == "GPT 5")
    }
}
