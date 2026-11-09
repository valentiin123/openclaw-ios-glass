import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Owns only the temporary copy handed to the system exporter, not Gateway paths.
final class ChatDownloadedFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    private let directory: URL

    init(data: Data, fileName: String) throws {
        // Dedicated folder under <tmp>/OpenClawAttachments/, swept after 24 h if the app is killed.
        let directory = try ChatAttachmentTemporaryStorage.makeWorkingDirectory()
        self.directory = directory
        self.url = directory.appendingPathComponent(
            ChatAttachmentTemporaryStorage.safeFileName(fileName),
            isDirectory: false)
        do {
            try data.write(to: self.url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: self.directory)
    }
}

struct ChatFileAttachment: View {
    let artifactId: String
    let label: String
    let fileName: String
    let resolverReady: Bool
    let load: @MainActor @Sendable (String) async throws -> OpenClawChatLoadedMedia?

    @State private var requestID: UUID?
    @State private var isLoading = false
    @State private var downloadedFile: ChatDownloadedFile?
    @State private var showsError = false
    /// True when the Gateway artifact is above the client download ceiling, so the
    /// alert can say so instead of suggesting a reconnect that cannot help.
    @State private var failureIsTooLarge = false

    var body: some View {
        Button {
            self.requestID = UUID()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.label)
                        .font(OpenClawChatTypography.footnote)
                        .lineLimit(2)
                    Text(self.isLoading ? "Downloading…" : "Download file")
                        .font(OpenClawChatTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if self.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!self.resolverReady || self.isLoading)
        .accessibilityIdentifier("chat-file-download")
        .task(id: self.requestID) {
            guard self.requestID != nil else { return }
            await self.download()
        }
        .onChange(of: self.resolverReady) { _, ready in
            if !ready { self.requestID = nil }
        }
        .alert("Unable to Download File", isPresented: self.$showsError) {
            Button(role: .cancel) {} label: {
                Text("OK").font(OpenClawChatTypography.body)
            }
        } message: {
            if self.failureIsTooLarge {
                Text("This file is too large to download in the app.")
                    .font(OpenClawChatTypography.body)
            } else {
                Text("Reconnect and try again. If the file has expired or was removed, ask the assistant to send it again.")
                    .font(OpenClawChatTypography.body)
            }
        }
        #if os(iOS)
        .sheet(item: self.$downloadedFile) { file in
            // The sheet retains the file until the system activity finishes.
            OpenClawChatFileShareSheet(fileURL: file.url, onCompletion: { _ = file })
        }
        #endif
    }

    @MainActor private func download() async {
        self.isLoading = true
        self.failureIsTooLarge = false
        defer {
            self.isLoading = false
            self.requestID = nil
        }
        do {
            let loaded = try await self.load(self.artifactId)
            try Task.checkCancellation()
            guard case let .data(media) = loaded else {
                self.showsError = true
                return
            }
            try Task.checkCancellation()
            let fileName = self.fileName
            let file = try await Task.detached(priority: .userInitiated) {
                try ChatDownloadedFile(data: media.data, fileName: fileName)
            }.value
            try Task.checkCancellation()
            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.url.lastPathComponent
            panel.begin { response in
                guard response == .OK, let destination = panel.url else { return }
                let source = file.url
                Task {
                    do {
                        // File to file, off the main thread: the document never lands on the heap.
                        try await ChatAttachmentTemporaryStorage.runOffMain {
                            try ChatAttachmentTemporaryStorage.exportCopy(from: source, to: destination)
                        }
                    } catch {
                        self.showsError = true
                    }
                    // Keeps the temporary folder alive until the copy has finished.
                    withExtendedLifetime(file) {}
                }
            }
            #else
            self.downloadedFile = file
            #endif
        } catch is CancellationError {
            // Leaving the message or changing Gateway cancels the export.
        } catch OpenClawChatMediaArtifactLoader.LoadError.payloadTooLarge {
            if !Task.isCancelled {
                self.failureIsTooLarge = true
                self.showsError = true
            }
        } catch {
            if !Task.isCancelled { self.showsError = true }
        }
    }
}

#if os(iOS)
/// System file sharing used by chat attachments, transcript export, and workspace files.
public struct OpenClawChatFileShareSheet: UIViewControllerRepresentable {
    public let fileURL: URL
    private let onCompletion: (() -> Void)?

    public init(fileURL: URL, onCompletion: (() -> Void)? = nil) {
        self.fileURL = fileURL
        self.onCompletion = onCompletion
    }

    public func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [self.fileURL], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in self.onCompletion?() }
        return controller
    }

    public func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
#endif
