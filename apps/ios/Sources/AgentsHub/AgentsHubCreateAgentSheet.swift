import SwiftUI

/// Feuille de création d'un agent (`agents.create`, scope operator.admin).
/// Surface de formulaire système opaque ; le verre reste réservé à la barre de navigation.
struct CreateAgentSheet: View {
    @Bindable var model: AgentsHubViewModel
    var onCreated: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var agentID = ""
    @State private var emoji = ""
    @State private var modelID = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        let hasName: Bool = !trimmedName.isEmpty
        return model.canCreateAgent && hasName && !model.isCreatingAgent
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                advancedSection
                permissionSection
                errorSection
            }
            .navigationTitle("New agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(model.isCreatingAgent)
            .onAppear(perform: resetError)
        }
        .presentationDetents([.medium, .large])
    }

    private var identitySection: some View {
        Section("Identity") {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
                .frame(minHeight: 44)
            TextField("Emoji (optional)", text: $emoji)
                .frame(minHeight: 44)
        }
    }

    private var advancedSection: some View {
        Section("Advanced (optional)") {
            TextField("Agent ID", text: $agentID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
            TextField("Model", text: $modelID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if !model.canCreateAgent {
            Section {
                Label("Creating agents requires administrator access on this Gateway.",
                      systemImage: "lock.fill")
                    .font(OpenClawType.subhead)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = model.createAgentError {
            Section { AgentsHubErrorRow(message: error, retry: nil) }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: close)
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isCreatingAgent {
                ProgressView().accessibilityLabel(Text("Creating agent"))
            } else {
                Button("Create", action: submit)
                    .disabled(!canSubmit)
            }
        }
    }

    private func resetError() {
        model.clearCreateAgentError()
    }

    private func close() {
        dismiss()
    }

    private func submit() {
        let chosenName: String = name
        let chosenID: String = agentID
        let chosenEmoji: String = emoji
        let chosenModel: String = modelID
        Task {
            let created: String? = await model.createAgent(
                name: chosenName, agentID: chosenID, emoji: chosenEmoji, modelID: chosenModel)
            if let created {
                onCreated(created)
                dismiss()
            }
        }
    }
}
