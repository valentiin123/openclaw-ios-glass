import Foundation
import OpenClawKit
import SwiftUI

/// Read-only summary of the Gateway Talk configuration plus Voice Wake triggers.
struct NativeTalkVoiceSummary: Equatable {
    var provider: String?
    var speechLocale: String?
    var interruptOnSpeech: Bool?
    var silenceTimeoutMs: Int?
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

        let provider: String? = talk.string("provider")
        let locale: String? = talk.string("speechLocale")
        let interrupt: Bool? = talk.bool("interruptOnSpeech")
        let silence: Int? = talk.int("silenceTimeoutMs")
        return NativeTalkVoiceSummary(
            provider: provider,
            speechLocale: locale,
            interruptOnSpeech: interrupt,
            silenceTimeoutMs: silence,
            triggers: triggers)
    }
}

/// Native Talk & Voice settings. Two toggles on this device, then the Gateway values read-only.
/// Device toggles are local (`NodeAppModel.setTalkEnabled` / `setVoiceWakeEnabled`).
@MainActor
struct NativeTalkVoiceScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @AppStorage(VoiceWakePreferences.enabledKey) private var voiceWakeEnabled: Bool = false
    @State private var loader: NativeSettingsLoader<NativeTalkVoiceSummary>
    @State private var newWord: String = ""
    @State private var isSavingWords: Bool = false
    @State private var wordsError: String?
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
        .openClawAnimation(value: self.loadedSummary)
    }

    private var loadedSummary: NativeTalkVoiceSummary? {
        if case let .loaded(value) = self.loader.state { return value }
        return nil
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

    private var gatewaySection: some View {
        Section {
            NativeSettingsInlineState(
                state: self.loader.state,
                retry: { await self.loader.refresh(appModel: self.appModel, showSpinner: true) },
                content: { (summary: NativeTalkVoiceSummary) in
                    self.summaryRows(summary)
                })
        } header: {
            NativeSettingsHeader("Gateway")
        } footer: {
            NativeSettingsFooter("These values are read from the Gateway and can be changed in the Dashboard.")
        }
    }

    @ViewBuilder
    private func summaryRows(_ summary: NativeTalkVoiceSummary) -> some View {
        let notSet: String = String(localized: "Not set")
        let providerValue: String = summary.provider ?? notSet
        let localeValue: String = summary.speechLocale ?? notSet
        let silenceValue: String = Self.silenceText(summary.silenceTimeoutMs, fallback: notSet)
        let interruptValue: String = Self.interruptText(summary.interruptOnSpeech, fallback: notSet)

        self.valueRow(
            title: String(localized: "Provider"),
            value: providerValue,
            systemImage: "speaker.wave.2",
            index: 2)
        self.valueRow(
            title: String(localized: "Speech language"),
            value: localeValue,
            systemImage: "globe",
            index: 3)
        self.valueRow(
            title: String(localized: "Silence timeout"),
            value: silenceValue,
            systemImage: "timer",
            index: 4)
        self.valueRow(
            title: String(localized: "Interrupt on speech"),
            value: interruptValue,
            systemImage: "hand.raised",
            index: 5)
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

    private func valueRow(
        title: String,
        value: String,
        systemImage: String,
        index: Int,
        lineLimit: Int? = 2) -> some View
    {
        NativeSettingsRow(
            title: title,
            detail: value,
            systemImage: systemImage,
            detailLineLimit: lineLimit)
            .nativeSettingsCopyMenu(value)
            .nativeSettingsCopySwipe(value)
            .openClawEntrance(index: index)
    }

    private static func silenceText(_ milliseconds: Int?, fallback: String) -> String {
        guard let milliseconds else { return fallback }
        let seconds: Double = Double(milliseconds) / 1000
        return seconds.formatted(.number.precision(.fractionLength(0...1))) + " s"
    }

    private static func interruptText(_ value: Bool?, fallback: String) -> String {
        guard let value else { return fallback }
        return value ? String(localized: "On") : String(localized: "Off")
    }
}
