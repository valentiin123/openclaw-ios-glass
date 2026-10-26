import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension OpenClawChatComposer {
    @ViewBuilder
    var cleanAttachmentMenu: some View {
        #if os(macOS)
        Button {
            self.pickFilesMac()
        } label: {
            CompactChatAttachmentLabel(controlSize: self.cleanControlHeight)
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .help("Add attachment")
        .accessibilityLabel("Attachments")
        .accessibilityIdentifier("chat-attachment-picker")
        .disabled(!self.isAttachmentInputEnabled)
        #elseif os(iOS)
        ChatPopoverButton {
            self.attachmentPopoverContent
        } label: {
            CompactChatAttachmentLabel()
        }
        .help("Composer options")
        .accessibilityLabel("Composer options")
        .accessibilityIdentifier("chat-attachment-picker")
        .task(id: self.viewModel.composerCapabilityOwnerID) {
            await self.viewModel.loadComposerCapabilities()
        }
        #else
        EmptyView()
        #endif
    }

    #if os(iOS)
    /// Attachments and tool toggles only. Verbosity and branch switching no longer live here.
    private var attachmentPopoverContent: some View {
        let cameraAvailable: Bool = UIImagePickerController.isSourceTypeAvailable(.camera)
        let inputEnabled: Bool = self.isAttachmentInputEnabled
        return VStack(spacing: 0) {
            ChatPopoverRow(
                title: String(localized: "Photo Library"),
                systemImage: "photo.on.rectangle",
                tint: OpenClawChatTheme.info,
                isEnabled: inputEnabled,
                closesBeforeAction: true)
            {
                self.photoPickerPresentation.wrappedValue = true
            }
            ChatPopoverRow(
                title: String(localized: "Camera"),
                systemImage: "camera",
                tint: OpenClawChatTheme.brandAccent,
                isEnabled: inputEnabled && cameraAvailable,
                closesBeforeAction: true)
            {
                self.cameraPickerPresentation.wrappedValue = true
            }
            ChatPopoverRow(
                title: String(localized: "File"),
                systemImage: "folder",
                tint: OpenClawChatTheme.brandSecondary,
                isEnabled: inputEnabled,
                closesBeforeAction: true)
            {
                self.fileImporterPresentation.wrappedValue = true
            }
            self.cleanComposerCapabilityItems
        }
        .padding(.vertical, 8)
    }
    #endif

    #if os(iOS)
    var cleanDraftRow: some View {
        self.editorOverlay
            .frame(maxWidth: .infinity, minHeight: self.textMinHeight, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, CleanChatComposerMetrics.editorInlineInset)
            .padding(.top, self.draftTopInset)
            // The room under a short draft belongs to the draft: a tap there starts typing.
            .contentShape(Rectangle())
            .onTapGesture { self.focusDraft() }
    }
    #endif

    @ViewBuilder
    var cleanLeadingControls: some View {
        #if os(macOS)
        Menu {
            Button {
                self.pickFilesMac()
            } label: {
                Label("Attach…", systemImage: "paperclip")
            }
            .disabled(!self.isAttachmentInputEnabled)
            Divider()
            if self.viewModel.sessionBranches.count > 1 {
                self.branchMenu
            }
            self.verbosityPicker
                .disabled(!self.viewModel.composerEffortMutationAvailable)
        } label: {
            CompactChatAttachmentLabel(controlSize: self.cleanControlHeight)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Composer options")
        .accessibilityLabel("Composer options")
        .accessibilityIdentifier("chat-attachment-picker")
        #else
        self.cleanAttachmentMenu
        #if os(iOS)
        if self.viewModel.supportsComposerCapabilities {
            self.cleanInlinePermissionMenu
        }
        #endif
        #endif
    }

    @ViewBuilder
    var cleanContextUsageMenu: some View {
        if let usage = self.viewModel.contextUsage {
            OpenClawChatContextUsageControl(
                usage: usage,
                canCompact: self.viewModel.canRequestSessionCompact,
                controlSize: self.cleanControlHeight,
                onCompact: self.viewModel.requestSessionCompact)
        }
    }

    var cleanTrailingControls: some View {
        ViewThatFits(in: .horizontal) {
            self.cleanInlineControls(compactModel: false)
            self.cleanInlineControls(compactModel: true)
        }
    }

    private func cleanInlineControls(compactModel: Bool) -> some View {
        HStack(spacing: CleanChatComposerMetrics.footerControlGap) {
            self.cleanContextUsageMenu
            // Camera switching only displaces settings in the compact iOS footer.
            #if os(macOS)
            self.cleanInlineModelPicker(compact: compactModel)
            self.cleanInlineEffortMenu
            #else
            if !self.cleanShowsCameraFlip {
                self.cleanInlineModelPicker(compact: compactModel)
                self.cleanInlineEffortMenu
            }
            #endif
            self.cleanCaptureAndPrimaryControls
        }
    }

    #if os(macOS)
    private func cleanInlineModelPicker(compact: Bool) -> some View {
        let sections: ChatModelPickerSections = self.viewModel.modelPickerSectionsWithoutRecents
        return Menu {
            Group {
                if self.viewModel.canSelectDefaultModel {
                    self.modelMenuOption(
                        self.viewModel.defaultModelLabel,
                        selectionID: OpenClawChatViewModel.defaultModelSelectionID)
                }
                if !sections.pinned.isEmpty {
                    Section("Pinned") {
                        self.modelOptions(sections.pinned, showsDefaultBadge: false)
                    }
                }
                ForEach(sections.providers) { provider in
                    Section(provider.displayName) {
                        self.modelOptions(provider.models, showsDefaultBadge: false)
                    }
                }
            }
            .disabled(self.cleanModelChoicesDisabled)
            #if os(macOS)
            if self.viewModel.modelSelectionID != OpenClawChatViewModel.defaultModelSelectionID {
                Divider()
                Button {
                    self.viewModel.toggleSelectedModelPinned()
                } label: {
                    Label(
                        self.viewModel.isSelectedModelPinned ? "Unpin model" : "Pin model",
                        systemImage: self.viewModel.isSelectedModelPinned ? "star.slash" : "star")
                }
            }
            if self.usesDesktopModelMenu {
                Divider()
                self.modelSignInButton
            }
            #endif
        } label: {
            self.cleanInlineModelLabel(compact: compact)
        }
        .menuIndicator(.hidden)
        .tint(OpenClawChatTheme.muted)
        #if os(macOS)
        // Mac session settings remain editable during a response; pinning is
        // local and stays available while a Gateway settings save is pending.
        .fixedSize()
        #elseif !os(iOS)
        .disabled(
            !self.viewModel.showsModelPicker ||
                !self.viewModel.composerModelMutationAvailable ||
                self.viewModel.isUpdatingSessionSettings ||
                self.viewModel.hasActiveRunForComposerSettings)
        #endif
        // Sign-in stays reachable even when choosing a model is unavailable.
        .help(self.cleanInlineModelDisabledHint ?? self.viewModel.composerInlineModelLabel)
        .accessibilityLabel("Model")
        .accessibilityValue(self.viewModel.composerInlineModelLabel)
        .accessibilityHint(self.cleanInlineModelDisabledHint ?? "")
        .accessibilityIdentifier("chat-composer-inline-model")
        .layoutPriority(1)
    }
    #elseif os(iOS)
    private func cleanInlineModelPicker(compact: Bool) -> some View {
        ChatPopoverButton {
            self.modelPopoverContent
        } label: {
            self.cleanInlineModelLabel(compact: compact)
        }
        .help(self.cleanInlineModelDisabledHint ?? self.viewModel.composerInlineModelLabel)
        .accessibilityLabel("Model")
        .accessibilityValue(self.viewModel.composerInlineModelLabel)
        .accessibilityHint(self.cleanInlineModelDisabledHint ?? "")
        .accessibilityIdentifier("chat-composer-inline-model")
        .layoutPriority(1)
    }

    /// Readable model names only: no provider prefix, no id, no "this session only" caption.
    private var modelPopoverContent: some View {
        let sections: ChatModelPickerSections = self.viewModel.modelPickerSectionsWithoutRecents
        let choicesDisabled: Bool = self.cleanModelChoicesDisabled
        let showsHeaders: Bool = sections.providers.count > 1 || !sections.pinned.isEmpty
        return VStack(spacing: 0) {
            if !sections.pinned.isEmpty {
                ChatPopoverSectionHeader(title: String(localized: "Pinned"))
                self.modelPopoverRows(sections.pinned, disabled: choicesDisabled)
            }
            ForEach(sections.providers) { provider in
                if showsHeaders {
                    ChatPopoverSectionHeader(title: provider.displayName)
                }
                self.modelPopoverRows(provider.models, disabled: choicesDisabled)
            }
        }
        .padding(.vertical, 8)
    }

    private func modelPopoverRows(_ models: [OpenClawChatModelChoice], disabled: Bool) -> some View {
        ForEach(models) { model in
            let unavailable: String? = self.viewModel.modelUnavailableDescription(model)
            ChatPopoverRow(
                title: model.pickerName,
                detail: unavailable,
                isSelected: self.viewModel.isSelectedModel(model.selectionID),
                indicator: .exclusive,
                isEnabled: !disabled && unavailable == nil,
                hint: unavailable ?? "")
            {
                self.viewModel.selectModel(model.selectionID)
            }
        }
    }
    #else
    private func cleanInlineModelPicker(compact _: Bool) -> some View {
        EmptyView()
    }
    #endif

    @ViewBuilder
    private func cleanInlineModelLabel(compact: Bool) -> some View {
        #if os(macOS)
        HStack(spacing: 6) {
            Text(self.viewModel.composerInlineModelLabel)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
        }
        .font(OpenClawChatTypography.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .frame(width: compact ? 104 : 160, height: self.cleanControlHeight)
        .contentShape(Rectangle())
        #else
        if compact || self.dynamicTypeSize.isAccessibilitySize {
            Image(systemName: "cpu")
                .font(.system(size: OpenClawChatTypography.scaled(16), weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(
                    width: CleanChatComposerMetrics.compactModelWidth,
                    height: CleanChatComposerMetrics.controlTouchSize)
                .contentShape(Rectangle())
        } else {
            Text(self.viewModel.composerInlineModelLabel)
                .font(OpenClawChatTypography.captionSemiBold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(
                    width: CleanChatComposerMetrics.regularModelWidth,
                    height: CleanChatComposerMetrics.controlTouchSize)
                .contentShape(Rectangle())
        }
        #endif
    }

    private var cleanInlineEffortMenu: some View {
        #if os(macOS)
        OpenClawChatEffortControl(
            thinkingOptions: self.viewModel.showsThinkingPicker ? self.viewModel.thinkingLevelOptions : [],
            thinkingLevel: self.viewModel.thinkingLevel,
            thinkingIsInherited: self.viewModel.thinkingOverrideIsInherited,
            fastModeEnabled: self.viewModel.fastModeIsEnabled,
            fastModeIsInherited: self.viewModel.fastModeSelectionID == OpenClawChatViewModel
                .inheritedThinkingSelectionID,
            showsFastMode: self.viewModel.showsFastModeControls,
            supportsFastMode: self.viewModel.selectedModelSupportsFastMode,
            isEnabled: self.viewModel.composerEffortMutationAvailable && !self.viewModel.isUpdatingSessionSettings,
            controlHeight: self.cleanControlHeight,
            showsLabel: false,
            onSelectThinkingLevel: {
                self.viewModel.selectThinkingLevel($0 ?? OpenClawChatViewModel.inheritedThinkingSelectionID)
            },
            onSelectFastMode: {
                self.viewModel.selectFastMode($0.map { $0 ? "on" : "off" }
                    ?? OpenClawChatViewModel.inheritedThinkingSelectionID)
            })
            .help(self.cleanInlineEffortDisabledHint ?? self.viewModel.composerInlineEffortLabel)
            .accessibilityHint(self.cleanInlineEffortDisabledHint ?? "")
            .fixedSize()
        #elseif os(iOS)
        ChatPopoverButton(
            width: ChatPopoverMetrics.wideWidth,
            blursBackground: true,
            scrollsContent: false,
            style: .floatingBar) {
            ChatThinkingPopoverContent(viewModel: self.viewModel)
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .trim(from: 0.12, to: 0.88)
                        .stroke(.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(90))
                    Capsule()
                        .fill(.secondary)
                        .frame(width: 1.5, height: 7)
                        .offset(y: -3.5)
                        .rotationEffect(.degrees(self.viewModel.composerInlineEffortAngle))
                }
                .frame(width: 18, height: 18)
                if self.viewModel.fastModeIsEnabled {
                    Image(systemName: "bolt.fill")
                        .font(OpenClawChatTypography.caption)
                        .foregroundStyle(OpenClawChatTheme.accent)
                        .offset(x: 7, y: -6)
                }
            }
            .frame(
                width: self.cleanControlHeight,
                height: self.cleanControlHeight)
            .contentShape(Rectangle())
        }
        .disabled(
            !self.viewModel.composerEffortMutationAvailable ||
                self.viewModel.isUpdatingSessionSettings)
        .help(self.cleanInlineEffortDisabledHint ?? self.viewModel.composerInlineEffortLabel)
        .accessibilityLabel("Effort")
        .accessibilityValue(self.viewModel.composerInlineEffortLabel)
        .accessibilityHint(self.cleanInlineEffortDisabledHint ?? "")
        .accessibilityIdentifier("chat-composer-inline-effort")
        #else
        EmptyView()
        #endif
    }

    /// Keep recovery visible only when authentication genuinely blocks the composer.
    var showsModelSignInRow: Bool {
        #if os(iOS)
        guard self.composerChrome == .clean else { return true }
        return self.viewModel.composerModelAvailabilityMessage != nil
        #else
        !self.usesDesktopModelMenu
        #endif
    }

    private var cleanModelChoicesDisabled: Bool {
        let unavailable = !self.viewModel.composerModelMutationAvailable ||
            self.viewModel.isUpdatingSessionSettings
        #if os(iOS)
        return unavailable || !self.viewModel.showsModelPicker || self.viewModel.hasActiveRunForComposerSettings
        #else
        return unavailable
        #endif
    }

    private var cleanInlineModelDisabledHint: String? {
        #if os(iOS)
        if self.viewModel.hasActiveRunForComposerSettings {
            return String(localized: "Model changes are available after the current response finishes.")
        }
        #endif
        if !self.viewModel.composerModelMutationAvailable {
            return String(localized: "Changing the model requires operator.write or operator.admin access.")
        }
        if self.viewModel.isUpdatingSessionSettings {
            return String(localized: "Saving session settings.")
        }
        return nil
    }

    private var cleanInlineEffortDisabledHint: String? {
        if !self.viewModel.composerEffortMutationAvailable {
            return String(localized: "Thinking and Fast controls require operator.admin access.")
        }
        if self.viewModel.isUpdatingSessionSettings {
            return String(localized: "Saving session settings.")
        }
        return nil
    }

    @ViewBuilder
    var cleanCaptureAndPrimaryControls: some View {
        if self.dictationControl != nil || self.voiceNoteControl != nil {
            OpenClawChatMicButton(
                dictationControl: self.dictationControl,
                voiceNoteControl: self.voiceNoteControl,
                isDictationPending: self.dictationTask != nil,
                isRealtimeTalkActive: self.talkControl?.isEnabled == true,
                isComposerEnabled: self.isComposerEnabled,
                isAttachmentInputEnabled: self.isAttachmentInputEnabled,
                controlSize: self.cleanControlHeight,
                onCancelDictation: {
                    ChatDictationActions.cancel(task: self.$dictationTask, control: self.dictationControl)
                },
                onStartDictation: {
                    if let dictationControl = self.dictationControl {
                        ChatDictationActions.start(
                            dictationControl,
                            task: self.$dictationTask,
                            viewModel: self.viewModel)
                    }
                })
        }

        if let talkControl, self.cleanShowsCameraFlip {
            ChatCameraFlipButton(
                control: talkControl,
                controlHeight: self.cleanControlHeight,
                visualSize: self.cleanIconControlSize)
        }

        self.cleanTrailingControl
    }

    private var cleanShowsCameraFlip: Bool {
        guard let talkControl = self.talkControl else { return false }
        return ChatCameraFlipButton.isAvailable(for: talkControl)
    }
}
