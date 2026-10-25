import Foundation
import OpenClawKit
import SwiftUI
import UIKit

/// Summary of the Gateway Talk configuration plus Voice Wake triggers.
struct NativeTalkVoiceSummary: Equatable {
    var provider: String?
    var speechLocale: String?
    var interruptOnSpeech: Bool?
    var silenceTimeoutMs: Int?
    /// Voice of the active provider (`talk.providers.<provider>.voiceId` or `.voice`).
    var voiceId: String?
    /// Config key that currently holds the voice for the active provider (`voiceId` or `voice`).
    var voiceKey: String = "voiceId"
    var triggers: [String]
}

/// Gateway calls for Talk & Voice. Verified methods: `talk.config` (params: includeSecrets?) and
/// `voicewake.get` (the iOS app decodes `{ "triggers": [String] }`).
@MainActor
enum NativeTalkVoiceLoader {
    static func summary(_ appModel: NodeAppModel) async throws -> NativeTalkVoiceSummary {
        let root: [String: Any] = try await NativeSettingsGateway.call(
            appModel: appModel,
            method: "talk.config")
        let config: [String: Any] = root.dict("config") ?? [:]
        let talk: [String: Any] = config.dict("talk") ?? [:]

        var triggers: [String] = []
        let wakeResult: [String: Any]? = try? await NativeSettingsGateway.call(
            appModel: appModel,
            method: "voicewake.get",
            timeoutSeconds: 8)
        if let wakeResult {
            let rawTriggers: [String] = (wakeResult["triggers"] as? [String]) ?? []
            triggers = VoiceWakePreferences.sanitizeTriggerWords(rawTriggers)
        }

        let resolved: [String: Any] = talk.dict("resolved") ?? [:]
        let provider: String? = talk.string("provider") ?? resolved.string("provider")
        let providerConfig: [String: Any] = Self.providerConfig(talk: talk, resolved: resolved, provider: provider)
        let voiceId: String? = Self.nonEmpty(providerConfig.string("voiceId"))
        let voice: String? = Self.nonEmpty(providerConfig.string("voice"))
        var voiceKey: String = "voiceId"
        var currentVoice: String? = voiceId
        if voiceId == nil, let voice {
            voiceKey = "voice"
            currentVoice = voice
        }

        let locale: String? = talk.string("speechLocale")
        let interrupt: Bool? = talk.bool("interruptOnSpeech")
        let silence: Int? = talk.int("silenceTimeoutMs")
        return NativeTalkVoiceSummary(
            provider: provider,
            speechLocale: locale,
            interruptOnSpeech: interrupt,
            silenceTimeoutMs: silence,
            voiceId: currentVoice,
            voiceKey: voiceKey,
            triggers: triggers)
    }

    private static func providerConfig(
        talk: [String: Any],
        resolved: [String: Any],
        provider: String?) -> [String: Any]
    {
        let providers: [String: Any] = talk.dict("providers") ?? [:]
        if let provider, let entry = providers.dict(provider) {
            return entry
        }
        return resolved.dict("config") ?? [:]
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Native Talk & Voice settings. Two toggles on this device, the editable Gateway Talk values
/// (written through `config.patch`, `operator.admin`), then the wake words.
/// Device toggles are local (`NodeAppModel.setTalkEnabled` / `setVoiceWakeEnabled`).
@MainActor
struct NativeTalkVoiceScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @AppStorage(VoiceWakePreferences.enabledKey) private var voiceWakeEnabled: Bool = false
    @State private var loader: NativeSettingsLoader<NativeTalkVoiceSummary>
    @State private var newWord: String = ""
    @State private var isSavingWords: Bool = false
    @State private var wordsError: String?
    @State private var draft: NativeTalkConfigDraft = NativeTalkConfigDraft.empty
    @State private var pendingPlan: NativeTalkConfigPlan?
    @State private var pendingDraft: NativeTalkConfigDraft = NativeTalkConfigDraft.empty
    @State private var showConfirm: Bool = false
    @State private var isSavingConfig: Bool = false
    @State private var saveError: String?
    @State private var saveNotice: String?
    @State private var saveCount: Int = 0
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false
    var onClose: (() -> Void)?

    init(
        headerSidebarAction: OpenClawSidebarHeaderAction? = nil,
        embedded: Bool = false,
        onClose: (() -> Void)? = nil)
    {
        self.headerSidebarAction = headerSidebarAction
        self.embedded = embedded
        self.onClose = onClose
        let load: NativeSettingsLoader<NativeTalkVoiceSummary>.Load = { app in
            try await NativeTalkVoiceLoader.summary(app)
        }
        self._loader = State(initialValue: NativeSettingsLoader<NativeTalkVoiceSummary>(load: load))
    }

    var body: some View {
        NativeSettingsPage(
            title: NativeSettingsDestination.talkVoice.title,
            headerSidebarAction: self.headerSidebarAction,
            embedded: self.embedded,
            onClose: self.onClose)
        {
            self.list
        }
        .task { await self.loader.refresh(appModel: self.appModel, showSpinner: true) }
    }

    private var list: some View {
        List {
            self.deviceSection
            self.wakeWordsSection
            self.gatewaySection
        }
        .refreshable { await self.loader.refresh(appModel: self.appModel, showSpinner: false) }
        .openClawHaptic(.selection, trigger: self.appModel.talkMode.isEnabled)
        .openClawHaptic(.selection, trigger: self.voiceWakeEnabled)
        .openClawHaptic(.selection, trigger: self.saveCount)
        .openClawAnimation(value: self.loadedSummary)
        .onChange(of: self.loadedSummary) { (_: NativeTalkVoiceSummary?, newValue: NativeTalkVoiceSummary?) in
            guard let newValue else { return }
            self.draft = NativeTalkConfigDraft(summary: newValue)
        }
        .confirmationDialog(
            String(localized: "Change the Gateway configuration?"),
            isPresented: self.$showConfirm,
            titleVisibility: .visible)
        {
            Button(String(localized: "Apply changes")) {
                Task { await self.confirmSave() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                self.pendingPlan = nil
            }
        } message: {
            Text(verbatim: self.confirmationMessage)
        }
    }

    private var loadedSummary: NativeTalkVoiceSummary? {
        if case let .loaded(value) = self.loader.state { return value }
        return nil
    }

    private var canEditConfig: Bool {
        self.appModel.hasOperatorAdminScope
    }

    private var isDirty: Bool {
        guard let summary = self.loadedSummary else { return false }
        return self.draft != NativeTalkConfigDraft(summary: summary)
    }

    private var canSave: Bool {
        self.canEditConfig && self.isDirty && !self.isSavingConfig
    }

    private var confirmationMessage: String {
        let fields: [String] = self.pendingPlan?.fields ?? []
        let list: String = fields.joined(separator: ", ")
        return String(
            localized: "This changes the Gateway Talk settings (\(list)). The Gateway may restart and this app may briefly disconnect.")
    }

    private var talkBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.appModel.talkMode.isEnabled },
            set: { (newValue: Bool) in self.appModel.setTalkEnabled(newValue) })
    }

    private var voiceWakeBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.voiceWakeEnabled },
            set: { (newValue: Bool) in
                self.voiceWakeEnabled = newValue
                self.appModel.setVoiceWakeEnabled(newValue)
            })
    }

    private var deviceSection: some View {
        Section {
            Toggle(isOn: self.talkBinding) {
                Label {
                    Text("Talk mode")
                        .font(OpenClawType.body)
                } icon: {
                    Image(systemName: "waveform")
                }
            }
            .frame(minHeight: OpenClawHitTarget.minimum)
            .openClawEntrance(index: 0)
            .accessibilityIdentifier("NativeSettings.TalkVoice.Talk")
            Toggle(isOn: self.voiceWakeBinding) {
                Label {
                    Text("Voice Wake")
                        .font(OpenClawType.body)
                } icon: {
                    Image(systemName: "mic")
                }
            }
            .frame(minHeight: OpenClawHitTarget.minimum)
            .openClawEntrance(index: 1)
            .accessibilityIdentifier("NativeSettings.TalkVoice.VoiceWake")
        } header: {
            NativeSettingsHeader("This device")
        } footer: {
            NativeSettingsFooter("Voice Wake listens for the trigger words below while the app is open.")
        }
        .openClawAnimation(value: self.voiceWakeEnabled)
    }

    // MARK: - Gateway Talk configuration (config.get + config.patch, operator.admin)

    private var gatewaySection: some View {
        Section {
            NativeSettingsInlineState(
                state: self.loader.state,
                retry: { await self.loader.refresh(appModel: self.appModel, showSpinner: true) },
                content: { (_: NativeTalkVoiceSummary) in
                    self.editorRows
                })
        } header: {
            NativeSettingsHeader("Gateway")
        } footer: {
            if self.canEditConfig {
                NativeSettingsFooter("Changes are written to the Gateway configuration. The Gateway may restart.")
            } else {
                NativeSettingsFooter("Changing Talk settings requires operator.admin access.")
            }
        }
        .openClawAnimation(value: self.saveError)
        .openClawAnimation(value: self.saveNotice)
    }

    @ViewBuilder
    private var editorRows: some View {
        self.fieldRow(
            title: String(localized: "Provider"),
            placeholder: String(localized: "Not set"),
            text: self.$draft.provider,
            systemImage: "speaker.wave.2",
            index: 2,
            identifier: "NativeSettings.TalkVoice.Provider")
        self.fieldRow(
            title: String(localized: "Voice"),
            placeholder: String(localized: "Not set"),
            text: self.$draft.voiceId,
            systemImage: "person.wave.2",
            index: 3,
            identifier: "NativeSettings.TalkVoice.Voice")
        self.fieldRow(
            title: String(localized: "Speech language"),
            placeholder: String(localized: "fr-FR"),
            text: self.$draft.speechLocale,
            systemImage: "globe",
            index: 4,
            identifier: "NativeSettings.TalkVoice.Locale")
        self.fieldRow(
            title: String(localized: "Silence timeout (ms)"),
            placeholder: String(localized: "Not set"),
            text: self.$draft.silenceText,
            systemImage: "timer",
            index: 5,
            identifier: "NativeSettings.TalkVoice.Silence",
            keyboard: .numberPad)
        Toggle(isOn: self.$draft.interruptOnSpeech) {
            Label {
                Text("Interrupt on speech")
                    .font(OpenClawType.body)
            } icon: {
                Image(systemName: "hand.raised")
            }
        }
        .disabled(!self.canEditConfig)
        .frame(minHeight: OpenClawHitTarget.minimum)
        .openClawEntrance(index: 6)
        .accessibilityIdentifier("NativeSettings.TalkVoice.Interrupt")
        self.saveRow
    }

    private func fieldRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        systemImage: String,
        index: Int,
        identifier: String,
        keyboard: UIKeyboardType = .default) -> some View
    {
        VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
            Label {
                Text(verbatim: title)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: systemImage)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
            }
            TextField(placeholder, text: text)
                .font(OpenClawType.body)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .disabled(!self.canEditConfig)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum, alignment: .leading)
        .openClawEntrance(index: index)
    }

    private var saveRow: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.sm) {
            if let error = self.saveError {
                Text(verbatim: error)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
            }
            if let notice = self.saveNotice {
                Text(verbatim: notice)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: OpenClawSpace.md) {
                OpenClawGlassButton(title: "Save changes", systemImage: "checkmark", kind: .prominent) {
                    self.requestSave()
                }
                .disabled(!self.canSave)
                .accessibilityIdentifier("NativeSettings.TalkVoice.Save")
                if self.isSavingConfig {
                    ProgressView()
                        .accessibilityLabel(Text("Saving"))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum, alignment: .leading)
    }

    /// Validates the draft, builds the minimal patch and asks for confirmation. Nothing is sent yet.
    private func requestSave() {
        guard self.canEditConfig, let summary = self.loadedSummary else { return }
        self.saveError = nil
        self.saveNotice = nil
        do {
            let plan: NativeTalkConfigPlan? = try NativeTalkConfigPatch.plan(original: summary, draft: self.draft)
            guard let plan else { return }
            self.pendingPlan = plan
            self.pendingDraft = self.draft
            self.showConfirm = true
        } catch {
            self.saveError = error.localizedDescription
        }
    }

    /// Sends the confirmed patch (`config.get` for the hash, then `config.patch`).
    private func confirmSave() async {
        guard let plan = self.pendingPlan, let summary = self.loadedSummary else { return }
        let draftToApply: NativeTalkConfigDraft = self.pendingDraft
        self.pendingPlan = nil
        self.isSavingConfig = true
        defer { self.isSavingConfig = false }
        do {
            let outcome: NativeTalkConfigWriter.Outcome = try await NativeTalkConfigWriter.apply(
                appModel: self.appModel,
                patch: plan.patch)
            let applied: NativeTalkVoiceSummary = NativeTalkConfigPatch.applying(draftToApply, to: summary)
            self.loader.state = .loaded(applied)
            self.saveCount += 1
            if outcome.restartScheduled {
                self.saveNotice = String(localized: "Saved. The Gateway is restarting; the app will reconnect.")
            } else {
                self.saveNotice = String(localized: "Saved.")
            }
        } catch is CancellationError {
            return
        } catch {
            self.saveError = error.localizedDescription
        }
    }

    // MARK: - Wake words (voicewake.set, operator.write)

    private var wakeWordsSection: some View {
        Section {
            if let summary = self.loadedSummary {
                ForEach(summary.triggers, id: \.self) { (word: String) in
                    self.wakeWordRow(word, canDelete: summary.triggers.count > 1)
                }
                self.addWordRow(summary)
                if let error = self.wordsError {
                    Text(verbatim: error)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            NativeSettingsHeader("Wake words")
        } footer: {
            NativeSettingsFooter("Wake words are shared with every device connected to this Gateway.")
        }
    }

    private func wakeWordRow(_ word: String, canDelete: Bool) -> some View {
        Text(verbatim: word)
            .font(OpenClawType.body)
            .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum, alignment: .leading)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canDelete {
                    Button(role: .destructive) {
                        Task { await self.removeWord(word) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    private func addWordRow(_ summary: NativeTalkVoiceSummary) -> some View {
        TextField("Add a wake word", text: self.$newWord)
            .font(OpenClawType.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .disabled(self.isSavingWords)
            .frame(minHeight: OpenClawHitTarget.minimum)
            .onSubmit {
                Task { await self.addWord() }
            }
            .accessibilityIdentifier("NativeSettings.TalkVoice.AddWakeWord")
    }

    private func addWord() async {
        let word: String = self.newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, let summary = self.loadedSummary else { return }
        if summary.triggers.contains(word) {
            self.newWord = ""
            return
        }
        var words: [String] = summary.triggers
        words.append(word)
        let saved: Bool = await self.saveWords(words)
        if saved { self.newWord = "" }
    }

    private func removeWord(_ word: String) async {
        guard let summary = self.loadedSummary else { return }
        let words: [String] = summary.triggers.filter { (item: String) -> Bool in item != word }
        _ = await self.saveWords(words)
    }

    /// Calls `voicewake.set` with `{ triggers: [String] }`; the Gateway normalizes and broadcasts `voicewake.changed`.
    private func saveWords(_ words: [String]) async -> Bool {
        let cleaned: [String] = VoiceWakePreferences.sanitizeTriggerWords(words)
        self.isSavingWords = true
        defer { self.isSavingWords = false }
        do {
            let result: [String] = try await NativeSettingsGateway.call(
                appModel: self.appModel,
                method: "voicewake.set",
                params: ["triggers": cleaned]).strings("triggers")
            let stored: [String] = VoiceWakePreferences.sanitizeTriggerWords(result)
            VoiceWakePreferences.saveTriggerWords(stored)
            if var summary = self.loadedSummary {
                summary.triggers = stored
                self.loader.state = .loaded(summary)
            }
            self.wordsError = nil
            return true
        } catch {
            self.wordsError = error.localizedDescription
            return false
        }
    }
}
