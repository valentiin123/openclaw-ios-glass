import AVFoundation
import Foundation
import ImageIO
import OpenClawKit
import UniformTypeIdentifiers

extension OpenClawChatViewModel {
    /// Bound memory for resize input independently of the encoded upload budget.
    private static let maxImageSourceBytes = 64 * 1024 * 1024

    public func addAttachments(urls: [URL]) {
        self.addAttachments(urls: urls, for: nil)
    }

    func addAttachments(urls: [URL], for session: SessionSnapshot?) {
        guard self.ownsAttachmentSession(session) else { return }
        self.beginAttachmentStaging()
        Task {
            defer { self.endAttachmentStaging() }
            await self.loadAttachments(urls: urls, expectedSession: session)
        }
    }

    public func addImageAttachment(data: Data, fileName: String, mimeType: String) {
        self.beginAttachmentStaging()
        Task {
            defer { self.endAttachmentStaging() }
            let advertisedLimits = await self.transport.attachmentLimits()
            await self.stageImageAttachment(
                url: nil, data: data, fileName: fileName, mimeType: mimeType, advertisedLimits: advertisedLimits)
        }
    }

    func addImageAttachment(
        data: Data,
        fileName: String,
        mimeType: String,
        for session: SessionSnapshot) async
    {
        guard self.isCurrentSession(session) else { return }
        self.beginAttachmentStaging()
        defer { self.endAttachmentStaging() }
        let advertisedLimits = await self.transport.attachmentLimits()
        await self.stageImageAttachment(
            url: nil,
            data: data,
            fileName: fileName,
            mimeType: mimeType,
            advertisedLimits: advertisedLimits,
            expectedSession: session)
    }

    func validateAttachmentBudgetForSend(
        _ draftAttachments: [OpenClawPendingAttachment],
        session: SessionSnapshot) async -> Bool
    {
        guard !draftAttachments.isEmpty else { return self.isCurrentSession(session) }
        let limits = await self.transport.attachmentLimits() ?? .legacyClientFallback
        guard self.isCurrentSession(session) else { return false }
        return self.validateAttachmentBudget(draftAttachments, limits: limits)
    }

    private func validateAttachmentBudget(
        _ candidates: [OpenClawPendingAttachment],
        limits: GatewayAttachmentLimits) -> Bool
    {
        // Every attachment shares one base64-encoded chat.send frame. Subtract
        // from the decoded budget to include prior selections without sum overflow.
        var remaining = limits.maxBytes
        for attachment in candidates {
            guard attachment.data.count <= remaining else {
                self.errorText = String(format: String(localized: "Too large to send: %@"), attachment.fileName)
                return false
            }
            remaining -= attachment.data.count
        }
        return true
    }

    @discardableResult
    private func stageAttachment(_ attachment: OpenClawPendingAttachment, limits: GatewayAttachmentLimits) -> Bool {
        guard self.validateAttachmentBudget(self.attachments + [attachment], limits: limits) else { return false }
        self.attachments.append(attachment)
        return true
    }

    public func removeAttachment(_ id: OpenClawPendingAttachment.ID) {
        attachments.removeAll { $0.id == id }
        applyDeferredExternalStateIfReady()
    }

    func restoreEditorAttachments(_ editorAttachments: [OpenClawChatEditorAttachment]?) {
        self.attachments = (editorAttachments ?? []).enumerated().compactMap { index, attachment in
            guard let data = Data(base64Encoded: attachment.data),
                  data.count <= Self.maxAttachmentBytes,
                  let contentType = UTType(mimeType: attachment.mimeType),
                  contentType.conforms(to: .image)
            else { return nil }
            let fileExtension = contentType.preferredFilenameExtension ?? "img"
            return OpenClawPendingAttachment(
                url: nil,
                data: data,
                fileName: "image-\(index + 1).\(fileExtension)",
                mimeType: attachment.mimeType,
                preview: OpenClawPlatformImage(data: data))
        }
    }

    /// True while replacing this model could move an attachment across chats.
    public var isAttachmentOwnerPinned: Bool {
        attachmentOwnerIsActive() ||
            isSendingAttachmentDraft ||
            attachmentStagingCount > 0 ||
            !attachments.isEmpty
    }

    func canCreateSessionForImmediateSwitch() -> Bool {
        guard !self.isAttachmentOwnerPinned else {
            self.errorText = String(
                localized: "Remove attachments or wait for delivery to resolve before starting a new chat.")
            return false
        }
        return true
    }

    /// Applies external owner changes once recording or staging releases them.
    public func attachmentOwnerActivityChanged() {
        applyDeferredExternalStateIfReady()
    }

    /// File reads and image processing suspend before the attachment exists.
    /// Keep their original chat owner pinned until staging succeeds or fails.
    func beginAttachmentStaging() {
        attachmentStagingCount += 1
    }

    func endAttachmentStaging() {
        precondition(attachmentStagingCount > 0)
        attachmentStagingCount -= 1
        applyDeferredExternalStateIfReady()
    }

    /// Stages a recorded m4a voice note and removes its temporary file.
    public func addVoiceNoteAttachment(fileURL: URL, durationSeconds: Double) async {
        self.beginAttachmentStaging()
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            self.endAttachmentStaging()
        }

        let data: Data
        do {
            data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: fileURL)
            }.value
        } catch {
            errorText = String(
                format: String(localized: "Could not attach voice note: %@"),
                error.localizedDescription)
            return
        }

        guard data.count <= Self.maxAttachmentBytes else {
            errorText = String(localized: "Voice note exceeds the 5 MB attachment limit")
            return
        }

        let limits = await self.transport.attachmentLimits() ?? .legacyClientFallback
        let normalizedDuration = durationSeconds.isFinite
            ? min(max(0, durationSeconds), OpenClawVoiceNoteRecorder.maximumDurationSeconds)
            : 0
        self.stageAttachment(
            OpenClawPendingAttachment(
                url: nil,
                data: data,
                fileName: fileURL.lastPathComponent,
                mimeType: "audio/mp4",
                preview: nil,
                durationSeconds: normalizedDuration),
            limits: limits)
    }

    func loadAttachments(urls: [URL], expectedSession: SessionSnapshot? = nil) async {
        // One selection owns one policy snapshot. Reacquiring route-dependent
        // limits between files can strand a partially staged batch during recovery.
        let advertisedLimits = await self.transport.attachmentLimits()
        var unreadable: [String] = []
        var oversized: [String] = []
        for url in urls {
            guard self.ownsAttachmentSession(expectedSession) else { return }
            do {
                try await self.addFileAttachment(
                    url: url,
                    fileName: url.lastPathComponent,
                    mimeType: Self.mimeType(for: url) ?? "application/octet-stream",
                    advertisedLimits: advertisedLimits,
                    expectedSession: expectedSession)
            } catch ChatAttachmentReadError.tooLarge {
                oversized.append(url.lastPathComponent)
            } catch {
                unreadable.append(url.lastPathComponent)
            }
        }
        guard self.ownsAttachmentSession(expectedSession) else { return }
        let errors = [
            unreadable.isEmpty ? nil : String(
                format: String(localized: "Could not attach: %@"), Self.attachmentNames(unreadable)),
            oversized.isEmpty ? nil : String(
                format: String(localized: "Too large to send: %@"), Self.attachmentNames(oversized)),
        ].compactMap(\.self)
        if !errors.isEmpty { self.errorText = errors.joined(separator: "\n") }
    }

    private static func attachmentNames(_ names: [String]) -> String {
        let more = names.count > 3 ? String(format: String(localized: " +%@"), String(names.count - 3)) : ""
        return names.prefix(3).joined(separator: ", ") + more
    }

    nonisolated static func mimeType(for url: URL) -> String? {
        let ext = url.pathExtension
        guard !ext.isEmpty else { return nil }
        return (UTType(filenameExtension: ext) ?? .data).preferredMIMEType
    }

    @discardableResult
    private func stageImageAttachment(
        url: URL?,
        data: Data,
        fileName: String,
        mimeType: String,
        advertisedLimits: GatewayAttachmentLimits?,
        expectedSession: SessionSnapshot? = nil) async -> ChatAttachmentReadError?
    {
        let limits = advertisedLimits ?? .legacyClientFallback
        guard self.ownsAttachmentSession(expectedSession) else { return nil }
        guard !data.isEmpty else {
            errorText = String(format: String(localized: "Could not attach: %@"), fileName)
            return .unreadable
        }
        if data.count > Self.maxImageSourceBytes {
            errorText = String(format: String(localized: "Too large to send: %@"), fileName)
            return .tooLarge
        }
        let uti: UTType = {
            if let url {
                return UTType(filenameExtension: url.pathExtension) ?? .data
            }
            return UTType(mimeType: mimeType) ?? .data
        }()
        guard uti.conforms(to: .image) else {
            errorText = String(localized: "Only image attachments are supported right now")
            return .unreadable
        }

        let processed: Data
        do {
            processed = try await Task.detached(priority: .userInitiated) {
                try ChatImageProcessor.processForUpload(data: data)
            }.value
        } catch {
            guard self.ownsAttachmentSession(expectedSession) else { return nil }
            errorText = String(
                format: String(localized: "Could not process %1$@: %2$@"),
                fileName,
                error.localizedDescription)
            return .unreadable
        }

        // Image processing runs off actor. Revalidate the draft owner before
        // publishing either the attachment or any session-scoped error state.
        guard self.ownsAttachmentSession(expectedSession) else { return nil }
        if processed.count > limits.maxImageBytes {
            errorText = String(
                format: String(localized: "Too large to send: %@"),
                fileName)
            return .tooLarge
        }

        let outputFileName: String = {
            let baseName = (fileName as NSString).deletingPathExtension
            return baseName.isEmpty ? "image.jpg" : "\(baseName).jpg"
        }()

        let preview = OpenClawPlatformImage(data: processed)
        return self.stageAttachment(
            OpenClawPendingAttachment(
                url: url,
                data: processed,
                fileName: outputFileName,
                mimeType: "image/jpeg",
                preview: preview),
            limits: limits) ? nil : .tooLarge
    }

    func addVideoAttachment(
        url: URL,
        fileName: String,
        mimeType: String,
        expectedSession: SessionSnapshot? = nil) async
    {
        guard self.ownsAttachmentSession(expectedSession) else { return }
        let advertisedLimits = await self.transport.attachmentLimits()
        do {
            try await self.addFileAttachment(
                url: url,
                fileName: fileName,
                mimeType: mimeType,
                advertisedLimits: advertisedLimits,
                expectedSession: expectedSession)
        } catch ChatAttachmentReadError.tooLarge {
            guard self.ownsAttachmentSession(expectedSession) else { return }
            self.errorText = String(
                format: String(localized: "Too large to send: %@"),
                fileName)
        } catch {
            guard self.ownsAttachmentSession(expectedSession) else { return }
            self.errorText = String(format: String(localized: "Could not attach: %@"), fileName)
        }
    }

    private func addFileAttachment(
        url: URL,
        fileName: String,
        mimeType: String,
        advertisedLimits: GatewayAttachmentLimits?,
        expectedSession: SessionSnapshot?) async throws
    {
        let limits = advertisedLimits ?? .legacyClientFallback
        guard self.ownsAttachmentSession(expectedSession) else { return }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
        }
        let isImage = mimeType.hasPrefix("image/")
        // Images are shrunk before upload, so only their source is bounded. Any
        // other file is sent as is and must fit what is left of the shared frame.
        let maximumSourceBytes = isImage
            ? Self.maxImageSourceBytes
            : self.remainingAttachmentBudget(limits: limits)
        // Copy in chunks into a private temporary folder, then map the copy: the
        // file never sits on the heap. The folder is removed on every exit below;
        // the mapping stays valid once the file is unlinked.
        let staged = try await ChatAttachmentTemporaryStorage.copyIn(
            from: url,
            fileName: fileName,
            maximumBytes: maximumSourceBytes)
        defer { try? FileManager.default.removeItem(at: staged.directory) }
        let data = try await ChatAttachmentTemporaryStorage.mappedData(of: staged)
        guard self.ownsAttachmentSession(expectedSession) else { return }
        if isImage {
            if let error = await self.stageImageAttachment(
                url: url,
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                advertisedLimits: advertisedLimits,
                expectedSession: expectedSession)
            {
                throw error
            }
            return
        }

        var thumbnailData: Data?
        if mimeType.hasPrefix("video/") {
            thumbnailData = await Self.videoThumbnailData(fileURL: staged.url)
        }
        guard self.ownsAttachmentSession(expectedSession) else { return }
        guard self.stageAttachment(OpenClawPendingAttachment(
            url: nil,
            data: data,
            fileName: fileName,
            mimeType: mimeType,
            preview: thumbnailData.flatMap(OpenClawPlatformImage.init(data:))), limits: limits)
        else { throw ChatAttachmentReadError.tooLarge }
    }

    private func ownsAttachmentSession(_ expectedSession: SessionSnapshot?) -> Bool {
        expectedSession.map(self.isCurrentSession) ?? true
    }

    /// Decoded bytes still available in the one chat.send frame all attachments share.
    /// Used to refuse a file from its size alone, before any byte is copied.
    private func remainingAttachmentBudget(limits: GatewayAttachmentLimits) -> Int {
        self.attachments.reduce(limits.maxBytes) { max(0, $0 - $1.data.count) }
    }

    /// Reads the preview from the staged copy, so the video is not written out a second time.
    private nonisolated static func videoThumbnailData(fileURL: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            do {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: fileURL))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 640, height: 640)
                let image = try await generator.image(at: .zero).image
                let encoded = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(
                    encoded,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil)
                else { return nil }
                CGImageDestinationAddImage(
                    destination,
                    image,
                    [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { return nil }
                return encoded as Data
            } catch {
                return nil
            }
        }.value
    }
}
