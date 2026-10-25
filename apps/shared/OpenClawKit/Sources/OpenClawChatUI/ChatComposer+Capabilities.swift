import SwiftUI

#if os(iOS)

// Capability rows of the "+" popover and the permission popover. Opaque palette rows, no system menus.
extension OpenClawChatComposer {
    @ViewBuilder
    var cleanComposerCapabilityItems: some View {
        if self.viewModel.supportsComposerCapabilities,
           self.viewModel.composerCapabilityControlsAvailable
        {
            ChatPopoverDivider()
            self.composerWebSearchRow
            self.composerSkillsDisclosure
            self.composerConnectorsDisclosure
            if self.viewModel.composerToolOverrides.overrideCount > 0 {
                ChatPopoverDivider()
                ChatPopoverRow(
                    title: String(localized: "Clear tool overrides"),
                    systemImage: "xmark.circle",
                    isEnabled: !self.viewModel.composerClearToolOverridesDisabled,
                    closesPopover: false,
                    hint: self.viewModel.composerToolOverrideMutationDisabledReason ?? "")
                {
                    self.viewModel.clearComposerToolOverrides()
                }
            }
            self.composerCapabilityNotes
        }
    }

    @ViewBuilder
    private var composerCapabilityNotes: some View {
        let catalog: OpenClawChatComposerCapabilityCatalog = self.viewModel.composerCapabilityCatalog
        let loading: Bool = self.viewModel.composerCapabilitiesLoading
        if !loading,
           let reason = self.viewModel.composerPermissionMutationDisabledReason,
           !catalog.permissionMutationAvailable
        {
            ChatPopoverNote(text: reason)
        }
        if !loading,
           let reason = self.viewModel.composerToolOverrideMutationDisabledReason,
           !catalog.toolOverrideMutationAvailable
        {
            ChatPopoverNote(text: reason)
        }
        if !loading, !catalog.webSearchAvailable, self.viewModel.composerCapabilityErrorMessage == nil {
            ChatPopoverNote(text: String(localized: "Web Search is unavailable on this Gateway."))
        }
        if let errorMessage = self.viewModel.composerCapabilityErrorMessage {
            ChatPopoverNote(text: errorMessage)
            ChatPopoverRow(
                title: String(localized: "Retry capability loading"),
                systemImage: "arrow.clockwise",
                closesPopover: false)
            {
                Task { await self.viewModel.loadComposerCapabilities(force: true) }
            }
        }
    }

    // MARK: Permissions popover

    @ViewBuilder
    var cleanInlinePermissionMenu: some View {
        if self.viewModel.composerCapabilityControlsAvailable {
            ChatPopoverButton {
                self.permissionPopoverContent
            } label: {
                self.cleanInlinePermissionGlyph
                    .frame(
                        width: CleanChatComposerMetrics.controlTouchSize,
                        height: CleanChatComposerMetrics.controlTouchSize)
                    .contentShape(Rectangle())
            }
            .disabled(
                !self.viewModel.composerCapabilityCatalog.permissionMutationAvailable ||
                    self.viewModel.composerCapabilityMutationDisabled)
            .accessibilityLabel("Session permissions")
            .accessibilityValue(
                self.viewModel.composerPermissionMode?.displayName ?? String(localized: "Default (inherited)"))
            .accessibilityHint(self.viewModel.composerPermissionMutationDisabledReason ?? "")
            .accessibilityIdentifier("chat-composer-inline-permissions")
        }
    }

    private var permissionPopoverContent: some View {
        let canSelectFull: Bool = self.viewModel.composerCapabilityCatalog.canSelectFullPermission
        return VStack(spacing: 0) {
            self.permissionRow(nil, title: String(localized: "Default (inherited)"), isEnabled: true)
            ForEach(OpenClawChatPermissionMode.allCases, id: \.rawValue) { mode in
                self.permissionRow(
                    mode,
                    title: mode.displayName,
                    isEnabled: mode != OpenClawChatPermissionMode.full || canSelectFull)
            }
            if !canSelectFull {
                ChatPopoverNote(text: String(localized: "Full permission requires operator.admin access."))
            }
        }
        .padding(.vertical, 4)
    }

    private func permissionRow(
        _ mode: OpenClawChatPermissionMode?,
        title: String,
        isEnabled: Bool) -> some View
    {
        let isSelected: Bool = self.viewModel.composerPermissionMode == mode
        return ChatPopoverRow(
            title: title,
            isSelected: isSelected,
            isEnabled: isEnabled,
            hint: self.viewModel.composerPermissionDisabledReason(mode) ?? "")
        {
            self.viewModel.selectComposerPermissionMode(mode)
        }
    }

    private var cleanInlinePermissionGlyph: some View {
        ZStack {
            Image(systemName: "shield")
                .font(.system(size: OpenClawChatTypography.scaled(18), weight: .semibold))
            Image(systemName: self.cleanInlinePermissionOverlaySymbol)
                .font(.system(size: OpenClawChatTypography.scaled(7), weight: .bold))
                .offset(y: -1)
        }
        .foregroundStyle(.secondary)
    }

    private var cleanInlinePermissionOverlaySymbol: String {
        switch self.viewModel.composerPermissionMode {
        case .readOnly: "ellipsis"
        case .guarded: "lock.fill"
        case .workspace: "gearshape.fill"
        case .full: "exclamationmark"
        case nil: "checkmark"
        }
    }

    // MARK: Web search, skills, connectors

    private var composerCapabilityBlocked: Bool {
        let catalog: OpenClawChatComposerCapabilityCatalog = self.viewModel.composerCapabilityCatalog
        return !catalog.toolOverrideMutationAvailable || self.viewModel.composerCapabilityMutationDisabled
    }

    private var composerWebSearchRow: some View {
        let isOn: Bool = self.viewModel.composerWebSearchEnabled
        let catalog: OpenClawChatComposerCapabilityCatalog = self.viewModel.composerCapabilityCatalog
        let available: Bool = catalog.webSearchAvailable && catalog.webSearchBaseEnabled
        return ChatPopoverRow(
            title: String(localized: "Web Search"),
            systemImage: "globe",
            isSelected: isOn,
            isEnabled: available && !self.composerCapabilityBlocked,
            closesPopover: false,
            hint: self.viewModel.composerWebSearchMutationDisabledReason ?? "")
        {
            self.viewModel.toggleComposerWebSearch()
        }
        .accessibilityIdentifier("chat-composer-web-search")
    }

    private var composerSkillsDisclosure: some View {
        ChatPopoverDisclosure(title: String(localized: "Skills"), systemImage: "book.closed") {
            self.composerSkillRows
        }
        .accessibilityIdentifier("chat-composer-skills")
    }

    @ViewBuilder
    private var composerSkillRows: some View {
        let catalog: OpenClawChatComposerCapabilityCatalog = self.viewModel.composerCapabilityCatalog
        if self.viewModel.composerCapabilitiesLoading {
            ChatPopoverNote(text: String(localized: "Loading skills…"))
        } else if !catalog.skillsAvailable {
            ChatPopoverNote(text: String(localized: "Skills unavailable"))
        } else if catalog.skills.isEmpty {
            ChatPopoverNote(text: String(localized: "No skills configured"))
        } else {
            ForEach(catalog.skills) { skill in
                self.composerSkillRow(skill)
            }
        }
    }

    private func composerSkillRow(_ skill: OpenClawChatComposerSkill) -> some View {
        let isOn: Bool = self.viewModel.composerSkillEnabled(skill)
        let status: String? = self.viewModel.composerSkillStatusMessage(skill)
        let skillBlocked: Bool = !skill.baseEnabled || skill.missingDependencies || skill.blocked
        let hint: String = status ?? self.viewModel.composerToolOverrideMutationDisabledReason ?? ""
        return ChatPopoverRow(
            title: skill.name,
            detail: status,
            isSelected: isOn,
            isEnabled: !skillBlocked && !self.composerCapabilityBlocked,
            closesPopover: false,
            hint: hint)
        {
            self.viewModel.toggleComposerSkill(skill)
        }
    }

    private var composerConnectorsDisclosure: some View {
        ChatPopoverDisclosure(title: String(localized: "Connectors"), systemImage: "puzzlepiece.extension") {
            self.composerConnectorRows
        }
        .accessibilityIdentifier("chat-composer-connectors")
    }

    @ViewBuilder
    private var composerConnectorRows: some View {
        let catalog: OpenClawChatComposerCapabilityCatalog = self.viewModel.composerCapabilityCatalog
        if self.viewModel.composerCapabilitiesLoading {
            ChatPopoverNote(text: String(localized: "Loading connectors…"))
        } else if !catalog.connectorsAvailable {
            ChatPopoverNote(text: String(localized: "Connectors unavailable"))
        } else if catalog.connectors.isEmpty {
            ChatPopoverNote(text: String(localized: "No connectors configured"))
        } else {
            ForEach(catalog.connectors) { connector in
                self.composerConnectorSection(connector)
            }
        }
    }

    private func composerConnectorSection(_ connector: OpenClawChatComposerConnector) -> some View {
        let isOn: Bool = self.viewModel.composerConnectorEnabled(connector)
        let reason: String = self.viewModel.composerToolOverrideMutationDisabledReason ?? ""
        return ChatPopoverDisclosure(
            title: connector.name,
            systemImage: isOn ? "checkmark.circle.fill" : "circle")
        {
            ChatPopoverRow(
                title: String(localized: "Enabled for this session"),
                isSelected: isOn,
                isEnabled: !self.composerCapabilityBlocked,
                closesPopover: false,
                hint: reason)
            {
                self.viewModel.toggleComposerConnector(connector)
            }
            if let notice = connector.notice {
                ChatPopoverNote(text: notice)
            }
            if !connector.tools.isEmpty {
                ChatPopoverDisclosure(
                    title: String(localized: "Tool Access"),
                    systemImage: "wrench.and.screwdriver")
                {
                    ForEach(connector.tools) { tool in
                        self.composerToolRow(connector: connector, tool: tool)
                    }
                }
            }
        }
    }

    private func composerToolRow(
        connector: OpenClawChatComposerConnector,
        tool: OpenClawChatComposerTool) -> some View
    {
        let isOn: Bool = self.viewModel.composerToolEnabled(server: connector.name, tool: tool.name)
        let accessAvailable: Bool = self.viewModel.composerCapabilityCatalog.toolAccessAvailable
        return ChatPopoverRow(
            title: tool.label,
            isSelected: isOn,
            isEnabled: accessAvailable && !self.composerCapabilityBlocked,
            closesPopover: false,
            hint: self.viewModel.composerToolOverrideMutationDisabledReason ?? "")
        {
            self.viewModel.toggleComposerTool(server: connector.name, tool: tool.name)
        }
    }
}

#endif
