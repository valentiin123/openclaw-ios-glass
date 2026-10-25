import Foundation
import Observation
import SwiftUI

/// Writes API key / env of one skill through `skills.update`.
/// Verified (`SkillsUpdateParamsSchema`, `updateSkillConfigEntry`): params `skillKey` + `apiKey?` (string) +
/// `env?` (record of strings), scope operator.admin. An empty `apiKey` removes the stored key; an empty env
/// value removes that variable; omitted fields are left untouched. The Gateway never returns the stored values
/// (they come back redacted), so every field here is write-only.
/// Secrets are never logged, never put in an error message and are cleared when the sheet goes away.
@MainActor
@Observable
final class NativeSkillSecretsModel {
    private(set) var isSaving: Bool = false
    private(set) var savedCount: Int = 0
    var errorMessage: String?

    /// Returns `true` when the Gateway accepted the update. Nothing is sent when there is nothing to change.
    func save(
        skillKey: String,
        apiKey: String?,
        env: [String: String],
        appModel: NodeAppModel) async -> Bool
    {
        guard appModel.isOperatorGatewayConnected else {
            self.errorMessage = NativeGateway.offlineMessage
            return false
        }
        guard appModel.hasOperatorAdminScope else {
            self.errorMessage = String(localized: "Changing skills requires operator.admin access.")
            return false
        }
        guard !self.isSaving else { return false }
        var params: [String: Any] = ["skillKey": skillKey]
        if let apiKey {
            params["apiKey"] = apiKey
        }
        if !env.isEmpty {
            params["env"] = env
        }
        guard params.count > 1 else { return true }
        self.isSaving = true
        self.errorMessage = nil
        defer { self.isSaving = false }
        do {
            _ = try await NativeSettingsGateway.call(
                appModel: appModel,
                method: "skills.update",
                params: params,
                timeoutSeconds: 20)
            self.savedCount += 1
            return true
        } catch is CancellationError {
            return false
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
}

/// Sheet to set or remove the API key and environment variables of a skill.
/// Secret inputs are `SecureField`s; fields stay in the list (no overlay).
@MainActor
struct NativeSkillSecretsScreen: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var model: NativeSkillSecretsModel = NativeSkillSecretsModel()
    @State private var apiKey: String = ""
    @State private var envValues: [String: String] = [:]
    @State private var customName: String = ""
    @State private var customValue: String = ""
    @State private var confirmRemoveKey: Bool = false
    let item: NativeSkillItem
    var onSaved: () -> Void = {}

    /// Variables the skill needs, without the one already covered by the API key field.
    private var envNames: [String] {
        let primary: String? = self.item.primaryEnv
        var names: [String] = []
        for name in self.item.requiredEnv where name != primary {
            names.append(name)
        }
        return names
    }

    private var pendingEnv: [String: String] {
        var env: [String: String] = [:]
        for name in self.envNames {
            let value: String = (self.envValues[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { env[name] = value }
        }
        let key: String = self.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String = self.customValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty, !value.isEmpty { env[key] = value }
        return env
    }

    private var pendingApiKey: String? {
        let trimmed: String = self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var canSave: Bool {
        let hasChange: Bool = self.pendingApiKey != nil || !self.pendingEnv.isEmpty
        return hasChange && !self.model.isSaving && self.appModel.hasOperatorAdminScope
    }

    var body: some View {
        NativeSettingsPage(
            title: self.item.name,
            embedded: false,
            onClose: { self.dismiss() })
        {
            self.list
        }
        .onDisappear { self.clearSecrets() }
    }

    private var list: some View {
        let saving: Bool = self.model.isSaving
        return List {
            if let message = self.model.errorMessage {
                self.errorSection(message)
            }
            self.apiKeySection
            self.envSection
            self.saveSection
        }
        .openClawAnimation(value: self.model.errorMessage)
        .openClawAnimation(value: saving)
        .sensoryFeedback(.success, trigger: self.model.savedCount)
        .sensoryFeedback(trigger: self.model.errorMessage) { (_: String?, new: String?) -> SensoryFeedback? in
            new != nil ? .error : nil
        }
        .confirmationDialog(
            "Remove the API key?",
            isPresented: self.$confirmRemoveKey)
        {
            Button(role: .destructive) {
                self.removeApiKey()
            } label: {
                Text("Remove API key")
                    .font(OpenClawType.body)
            }
        } message: {
            Text("The stored API key is deleted from the Gateway configuration.")
                .font(OpenClawType.body)
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Label {
                Text(verbatim: message)
                    .font(OpenClawType.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(OpenClawBrand.warn)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var apiKeySection: some View {
        let primary: String? = self.item.primaryEnv
        return Section {
            self.secretField(
                title: String(localized: "API key"),
                text: self.$apiKey,
                identifier: "NativeSettings.Skills.ApiKey")
            Button(role: .destructive) {
                self.confirmRemoveKey = true
            } label: {
                Label {
                    Text("Remove API key")
                        .font(OpenClawType.body)
                } icon: {
                    Image(systemName: "trash")
                }
                .frame(maxWidth: .infinity, minHeight: OpenClawHitTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
            }
            .disabled(self.model.isSaving || !self.appModel.hasOperatorAdminScope)
            .accessibilityIdentifier("NativeSettings.Skills.ApiKey.Remove")
        } header: {
            NativeSettingsHeader("API key")
        } footer: {
            if let primary {
                let format: String = String(localized: "Exposed to the skill as %@. Leave empty to keep the stored value.")
                NativeSettingsVerbatimFooter(text: String(format: format, primary))
            } else {
                NativeSettingsFooter("Leave empty to keep the stored value.")
            }
        }
    }

    private var envSection: some View {
        Section {
            ForEach(self.envNames, id: \.self) { (name: String) in
                self.secretField(
                    title: name,
                    text: self.envBinding(name),
                    identifier: "NativeSettings.Skills.Env.\(name)")
            }
            self.customNameField
            self.secretField(
                title: String(localized: "Value"),
                text: self.$customValue,
                identifier: "NativeSettings.Skills.Env.CustomValue")
        } header: {
            NativeSettingsHeader("Environment variables")
        } footer: {
            NativeSettingsFooter("Values are write-only: the Gateway never sends them back. Empty fields are left unchanged.")
        }
    }

    private var customNameField: some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
            Text("Variable name")
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
            TextField("", text: self.$customName)
                .font(OpenClawType.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("Variable name"))
                .accessibilityIdentifier("NativeSettings.Skills.Env.CustomName")
        }
        .frame(minHeight: OpenClawHitTarget.minimum)
    }

    private var saveSection: some View {
        Section {
            OpenClawGlassButton(
                title: .localized("Save"),
                systemImage: "checkmark",
                kind: .prominent)
            {
                self.save()
            }
            .frame(maxWidth: .infinity)
            .disabled(!self.canSave)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("NativeSettings.Skills.Save")
        }
    }

    private func secretField(title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: OpenClawSpace.xs) {
            Text(verbatim: title)
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
            SecureField("", text: text)
                .font(OpenClawType.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityIdentifier(identifier)
        }
        .frame(minHeight: OpenClawHitTarget.minimum)
    }

    private func envBinding(_ name: String) -> Binding<String> {
        Binding<String>(
            get: { self.envValues[name] ?? "" },
            set: { (newValue: String) in self.envValues[name] = newValue })
    }

    private func save() {
        let key: String? = self.pendingApiKey
        let env: [String: String] = self.pendingEnv
        let skillKey: String = self.item.id
        Task {
            let ok: Bool = await self.model.save(
                skillKey: skillKey,
                apiKey: key,
                env: env,
                appModel: self.appModel)
            guard ok else { return }
            self.clearSecrets()
            self.onSaved()
            self.dismiss()
        }
    }

    private func removeApiKey() {
        let skillKey: String = self.item.id
        Task {
            let ok: Bool = await self.model.save(
                skillKey: skillKey,
                apiKey: "",
                env: [:],
                appModel: self.appModel)
            guard ok else { return }
            self.clearSecrets()
            self.onSaved()
            self.dismiss()
        }
    }

    private func clearSecrets() {
        self.apiKey = ""
        self.envValues = [:]
        self.customName = ""
        self.customValue = ""
    }
}

/// Footer for text computed at runtime.
struct NativeSettingsVerbatimFooter: View {
    let text: String

    var body: some View {
        Text(verbatim: self.text)
            .font(OpenClawType.footnote)
    }
}
