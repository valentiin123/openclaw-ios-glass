import Foundation
import OpenClawKit

// MARK: - Draft

/// Editable copy of the Gateway Talk values shown on the Talk & Voice screen.
/// `silenceText` stays a string so a half-typed number never fights the text field.
struct NativeTalkConfigDraft: Equatable {
    var provider: String
    var voiceId: String
    var speechLocale: String
    var silenceText: String
    var interruptOnSpeech: Bool

    static let empty: NativeTalkConfigDraft = NativeTalkConfigDraft(
        provider: "",
        voiceId: "",
        speechLocale: "",
        silenceText: "",
        interruptOnSpeech: true)
}

extension NativeTalkConfigDraft {
    /// Baseline draft for a loaded summary. `interruptOnSpeech` defaults to `true` (Gateway documented default).
    init(summary: NativeTalkVoiceSummary) {
        var silence: String = ""
        if let milliseconds = summary.silenceTimeoutMs {
            silence = String(milliseconds)
        }
        self.init(
            provider: summary.provider ?? "",
            voiceId: summary.voiceId ?? "",
            speechLocale: summary.speechLocale ?? "",
            silenceText: silence,
            interruptOnSpeech: summary.interruptOnSpeech ?? true)
    }
}

// MARK: - Errors

enum NativeTalkConfigError: LocalizedError {
    case invalid(String)
    case missingAdminScope
    case conflict
    case gateway(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message):
            message
        case .missingAdminScope:
            String(localized: "Changing Talk settings requires operator.admin access.")
        case .conflict:
            String(localized: "The Gateway configuration changed while you were editing. Pull to refresh, then try again.")
        case let .gateway(message):
            message
        }
    }
}

// MARK: - Patch

/// A minimal `config.patch` payload plus the human-readable names of what it changes.
struct NativeTalkConfigPlan {
    var patch: [String: Any]
    var fields: [String]
}

/// Builds the merge patch for `config.patch`. Only the `talk` keys the user changed are included.
/// Verified in `src/config/merge-patch.ts`: objects merge recursively and `null` deletes a key.
enum NativeTalkConfigPatch {
    static func plan(original: NativeTalkVoiceSummary, draft: NativeTalkConfigDraft) throws -> NativeTalkConfigPlan? {
        let baseline: NativeTalkConfigDraft = NativeTalkConfigDraft(summary: original)
        var talk: [String: Any] = [:]
        var fields: [String] = []

        // Provider: `talk.provider`.
        let provider: String = Self.trimmed(draft.provider)
        let providerChanged: Bool = provider != baseline.provider
        if providerChanged {
            guard !provider.isEmpty else {
                throw NativeTalkConfigError.invalid(String(localized: "Choose a provider."))
            }
            talk["provider"] = provider
            fields.append(String(localized: "Provider"))
        }

        // Voice: `talk.providers.<provider>.<voiceId|voice>`. A new provider starts from an empty baseline
        // so switching provider never deletes the voice that provider already has.
        let voice: String = Self.trimmed(draft.voiceId)
        let voiceBaseline: String = providerChanged ? "" : baseline.voiceId
        if voice != voiceBaseline {
            let target: String = providerChanged ? provider : baseline.provider
            guard !target.isEmpty else {
                throw NativeTalkConfigError.invalid(String(localized: "Choose a provider before setting a voice."))
            }
            let key: String = providerChanged ? "voiceId" : original.voiceKey
            var providerValues: [String: Any] = [:]
            if voice.isEmpty {
                providerValues[key] = NSNull()
            } else {
                providerValues[key] = voice
            }
            talk["providers"] = [target: providerValues]
            fields.append(String(localized: "Voice"))
        }

        // Speech language: `talk.speechLocale` (BCP 47).
        let locale: String = Self.trimmed(draft.speechLocale)
        if locale != baseline.speechLocale {
            if locale.isEmpty {
                talk["speechLocale"] = NSNull()
            } else {
                guard Self.isValidLocale(locale) else {
                    throw NativeTalkConfigError.invalid(
                        String(localized: "Enter a language code such as fr-FR or en-US."))
                }
                talk["speechLocale"] = locale
            }
            fields.append(String(localized: "Speech language"))
        }

        // Silence timeout: `talk.silenceTimeoutMs` (integer >= 1; verified in the Gateway schema).
        let silenceText: String = Self.trimmed(draft.silenceText)
        if silenceText != baseline.silenceText {
            if silenceText.isEmpty {
                talk["silenceTimeoutMs"] = NSNull()
            } else {
                guard let milliseconds = Int(silenceText), milliseconds >= 1 else {
                    throw NativeTalkConfigError.invalid(
                        String(localized: "The silence timeout must be a whole number of milliseconds, at least 1."))
                }
                talk["silenceTimeoutMs"] = milliseconds
            }
            fields.append(String(localized: "Silence timeout"))
        }

        // Interrupt on speech: `talk.interruptOnSpeech` (boolean).
        if draft.interruptOnSpeech != baseline.interruptOnSpeech {
            talk["interruptOnSpeech"] = draft.interruptOnSpeech
            fields.append(String(localized: "Interrupt on speech"))
        }

        guard !talk.isEmpty else { return nil }
        return NativeTalkConfigPlan(patch: ["talk": talk], fields: fields)
    }

    /// Mirrors a successful patch onto the displayed summary so the screen needs no reload
    /// (the Gateway may be restarting and the operator connection briefly offline).
    static func applying(_ draft: NativeTalkConfigDraft, to summary: NativeTalkVoiceSummary) -> NativeTalkVoiceSummary {
        var updated: NativeTalkVoiceSummary = summary
        let baseline: NativeTalkConfigDraft = NativeTalkConfigDraft(summary: summary)
        let provider: String = Self.trimmed(draft.provider)
        let providerChanged: Bool = provider != baseline.provider
        if providerChanged {
            updated.provider = provider
            updated.voiceKey = "voiceId"
            updated.voiceId = nil
        }
        let voice: String = Self.trimmed(draft.voiceId)
        let voiceBaseline: String = providerChanged ? "" : baseline.voiceId
        if voice != voiceBaseline {
            if voice.isEmpty {
                updated.voiceId = nil
            } else {
                updated.voiceId = voice
            }
        }
        let locale: String = Self.trimmed(draft.speechLocale)
        if locale.isEmpty {
            updated.speechLocale = nil
        } else {
            updated.speechLocale = locale
        }
        let silenceText: String = Self.trimmed(draft.silenceText)
        updated.silenceTimeoutMs = Int(silenceText)
        if draft.interruptOnSpeech != baseline.interruptOnSpeech {
            updated.interruptOnSpeech = draft.interruptOnSpeech
        }
        return updated
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValidLocale(_ value: String) -> Bool {
        let pattern: String = "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Writer

/// Writes the Talk configuration through `config.get` (operator.read) then `config.patch` (operator.admin).
/// Verified params in `packages/gateway-protocol/src/schema/config.ts`:
/// `config.get` takes `{}`; `config.patch` takes `raw` (JSON merge-patch string, required), `baseHash?`,
/// `note?`, `restartDelayMs?`, `sessionKey?`, `deliveryContext?`, `replacePaths?`, `response?: "summary"`.
@MainActor
enum NativeTalkConfigWriter {
    struct Outcome {
        var restartScheduled: Bool
    }

    /// Sends the patch. On a hash conflict it reloads the hash and retries exactly once.
    static func apply(appModel: NodeAppModel, patch: [String: Any]) async throws -> Outcome {
        guard appModel.hasOperatorAdminScope else {
            throw NativeTalkConfigError.missingAdminScope
        }
        do {
            return try await Self.send(appModel: appModel, patch: patch)
        } catch NativeTalkConfigError.conflict {
            return try await Self.send(appModel: appModel, patch: patch)
        }
    }

    private static func send(appModel: NodeAppModel, patch: [String: Any]) async throws -> Outcome {
        let raw: String = NativeSettingsJSON.encode(patch)
        guard raw != "{}" else {
            throw NativeTalkConfigError.invalid(String(localized: "There is nothing to change."))
        }
        do {
            let current: [String: Any] = try await NativeSettingsGateway.call(
                appModel: appModel,
                method: "config.get")
            var params: [String: Any] = ["raw": raw, "response": "summary"]
            if let hash = current.string("hash"), !hash.isEmpty {
                params["baseHash"] = hash
            }
            let result: [String: Any] = try await NativeSettingsGateway.call(
                appModel: appModel,
                method: "config.patch",
                params: params,
                timeoutSeconds: 20)
            let restart: Any? = result["restart"]
            var scheduled: Bool = false
            if let restart, !(restart is NSNull) {
                scheduled = true
            }
            return Outcome(restartScheduled: scheduled)
        } catch {
            throw Self.map(error)
        }
    }

    /// Gateway conflict messages (`config changed since last load; re-run config.get and retry`,
    /// `config base hash required; re-run config.get and retry`) all contain "re-run config.get".
    private static func map(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if error is NativeTalkConfigError { return error }
        if let response = error as? GatewayResponseError {
            if response.missingScopeDetails != nil {
                return NativeTalkConfigError.missingAdminScope
            }
            if response.message.contains("re-run config.get") {
                return NativeTalkConfigError.conflict
            }
            return NativeTalkConfigError.gateway(response.message)
        }
        return error
    }
}
