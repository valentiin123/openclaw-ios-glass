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

/// Native replacement for the Dashboard Talk & Voice settings.
/// Device toggles are local (`NodeAppModel.setTalkEnabled` / `setVoiceWakeEnabled`);
/// Gateway values are shown read-only.
@MainActor
struct NativeTalkVoiceScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @AppStorage(VoiceWakePreferences.enabledKey) private var voiceWakeEnabled: Bool = false
    @State private var loader: NativeSettingsLoader<NativeTalkVoiceSummary>
    var headerSidebarAction: OpenClawSidebarHeaderAction?
    var embedded: Bool = false

    init(headerSidebarAction: OpenClawSidebarHeaderAction? = nil, embedded: Bool = false) {
        self.headerSidebarAction = headerSidebarAction
        self.embedded = embedded
        let load: NativeSettingsLoader<NativeTalkVoiceSummary>.Load = { app in
            try await NativeTalkVoiceLoader.summary(app)
        }
        self._loader = State(initialValue: NativeSettingsLoader<NativeTalkVoiceSummary>(load: load))
    }

    var body: some View {
        NativeSettingsPage(
            title: NativeSettingsDestination.talkVoice.title,
            headerSidebarAction: self.headerSidebarAction,
            embedded: self.embedded)
        {
            self.list
        }
        .task { await self.loader.refresh(appModel: self.appModel, showSpinner: true) }
    }

    private var list: some View {
        List {
            self.deviceSection
            self.gatewaySection
        }
        .refreshable { await self.loader.refresh(appModel: self.appModel, showSpinner: false) }
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
            .frame(minHeight: 44)
            Toggle(isOn: self.voiceWakeBinding) {
                Label {
                    Text("Voice Wake")
                        .font(OpenClawType.body)
                } icon: {
                    Image(systemName: "mic")
                }
            }
            .frame(minHeight: 44)
        } header: {
            Text("This device")
        } footer: {
            Text("Voice Wake listens for the trigger words below while the app is open.")
                .font(OpenClawType.footnote)
        }
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
            Text("Gateway")
        } footer: {
            Text("These values are read from the Gateway and can be changed in the Dashboard.")
                .font(OpenClawType.footnote)
        }
    }

    @ViewBuilder
    private func summaryRows(_ summary: NativeTalkVoiceSummary) -> some View {
        let notSet: String = String(localized: "Not set")
        let providerValue: String = summary.provider ?? notSet
        let localeValue: String = summary.speechLocale ?? notSet
        let triggersValue: String = summary.triggers.isEmpty
            ? notSet
            : summary.triggers.joined(separator: ", ")
        let silenceValue: String = Self.silenceText(summary.silenceTimeoutMs, fallback: notSet)
        let interruptValue: String = Self.interruptText(summary.interruptOnSpeech, fallback: notSet)

        self.valueRow(title: String(localized: "Provider"), value: providerValue, systemImage: "speaker.wave.2")
        self.valueRow(title: String(localized: "Speech language"), value: localeValue, systemImage: "globe")
        self.valueRow(title: String(localized: "Silence timeout"), value: silenceValue, systemImage: "timer")
        self.valueRow(title: String(localized: "Interrupt on speech"), value: interruptValue, systemImage: "hand.raised")
        self.valueRow(title: String(localized: "Wake words"), value: triggersValue, systemImage: "text.bubble")
    }

    private func valueRow(title: String, value: String, systemImage: String) -> some View {
        NativeSettingsRow(title: title, detail: value, systemImage: systemImage)
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
