import Foundation

/// Why a picked file could not be staged for sending.
enum ChatAttachmentReadError: Error {
    case tooLarge
    case unreadable
}

/// A private, size-checked copy of a picked file inside its own folder.
struct ChatAttachmentStagedCopy: Sendable {
    let directory: URL
    let url: URL
    let byteCount: Int
}

/// App-level hook: call once at launch, off the main thread, to delete stale
/// temporary attachment files (older than 24 hours) left by a crash or a kill.
public enum OpenClawChatTemporaryFiles {
    @discardableResult
    public static func purgeExpired() -> Int {
        ChatAttachmentTemporaryStorage.purgeExpired()
    }
}

/// Dedicated temporary storage for attachments that can be large.
///
/// Everything lives under `<tmp>/OpenClawAttachments/<uuid>/`. Files are copied
/// in fixed-size chunks, so peak memory does not depend on the file size, and
/// the limit is enforced on the bytes actually copied, not only on metadata.
enum ChatAttachmentTemporaryStorage {
    static let directoryName = "OpenClawAttachments"
    /// Anything older than this is a leftover from a crash or a killed app.
    static let expirationAge: TimeInterval = 24 * 60 * 60
    /// Chunk size for streaming copies.
    static let copyChunkBytes = 1024 * 1024

    /// Names used before the dedicated root existed. They get the same age rule.
    /// `openclaw-picker-video-` is deliberately absent: ChatComposer owns that copy,
    /// removes it itself, and the copy keeps the source's old modification date, so
    /// an age rule could delete a video that is being sent right now.
    private static let legacyPrefixes = [
        "openclaw-chat-file-",
        "openclaw-chat-video-",
        "openclaw-upload-preview-",
    ]

    static var rootDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(self.directoryName, isDirectory: true)
    }

    /// Runs once per process, the first time any attachment folder is created.
    /// This module has no app-launch hook, so this is the earliest point it can sweep.
    private static let launchSweep: Void = {
        _ = ChatAttachmentTemporaryStorage.purgeExpired()
    }()

    /// Creates a fresh, empty folder for one attachment.
    static func makeWorkingDirectory() throws -> URL {
        _ = self.launchSweep
        let directory = self.rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Strips path components and control characters from a user-visible file name.
    static func safeFileName(_ fileName: String) -> String {
        let name = (fileName.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        let safeName = name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init).joined()
        return safeName.isEmpty || safeName == "." || safeName == ".." ? "Attachment" : safeName
    }

    /// Runs blocking file work off the caller's actor and forwards cancellation to it.
    static func runOffMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated) { try work() }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Copies `source` into a new private folder, refusing anything above
    /// `maximumBytes`. The size is checked before copying and again while copying.
    /// The caller owns the returned folder and must remove it.
    static func copyIn(
        from source: URL,
        fileName: String,
        maximumBytes: Int) async throws -> ChatAttachmentStagedCopy
    {
        try await ChatAttachmentTemporaryStorage.runOffMain { () throws -> ChatAttachmentStagedCopy in
            guard source.isFileURL else { throw ChatAttachmentReadError.unreadable }
            let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw ChatAttachmentReadError.unreadable }
            if let fileSize = values.fileSize, fileSize > maximumBytes {
                throw ChatAttachmentReadError.tooLarge
            }
            let directory = try ChatAttachmentTemporaryStorage.makeWorkingDirectory()
            do {
                let destination = directory.appendingPathComponent(
                    ChatAttachmentTemporaryStorage.safeFileName(fileName),
                    isDirectory: false)
                let byteCount = try ChatAttachmentTemporaryStorage.copyChunked(
                    from: source,
                    to: destination,
                    maximumBytes: maximumBytes)
                return ChatAttachmentStagedCopy(directory: directory, url: destination, byteCount: byteCount)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
    }

    /// Maps a staged copy into memory without reading it onto the heap. The
    /// mapping stays valid after the file is removed, so the folder can be
    /// deleted right away and its space is freed when the `Data` is released.
    static func mappedData(of copy: ChatAttachmentStagedCopy) async throws -> Data {
        try await ChatAttachmentTemporaryStorage.runOffMain { () throws -> Data in
            let data = try Data(contentsOf: copy.url, options: [.alwaysMapped])
            guard data.count == copy.byteCount else { throw ChatAttachmentReadError.unreadable }
            return data
        }
    }

    /// Copies a finished file to the place the person picked, replacing what is there.
    static func exportCopy(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.copyItem(at: source, to: destination)
    }

    private static func copyChunked(from source: URL, to destination: URL, maximumBytes: Int) throws -> Int {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw ChatAttachmentReadError.unreadable
        }
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }
        var copied = 0
        var finished = false
        while !finished {
            try Task.checkCancellation()
            // Release each chunk right away instead of at the end of the whole job.
            try autoreleasepool { () throws -> Void in
                guard let chunk = try reader.read(upToCount: ChatAttachmentTemporaryStorage.copyChunkBytes),
                      !chunk.isEmpty
                else {
                    finished = true
                    return
                }
                copied += chunk.count
                // A file can grow after the metadata check; stop on the bytes really read.
                if copied > maximumBytes { throw ChatAttachmentReadError.tooLarge }
                try writer.write(contentsOf: chunk)
            }
        }
        guard copied > 0 else { throw ChatAttachmentReadError.unreadable }
        return copied
    }

    /// Removes attachment folders and legacy temporary files not touched for `maximumAge`.
    @discardableResult
    static func purgeExpired(
        maximumAge: TimeInterval = ChatAttachmentTemporaryStorage.expirationAge,
        now: Date = Date()) -> Int
    {
        let manager = FileManager.default
        let cutoff = now.addingTimeInterval(-maximumAge)
        var candidates = (try? manager.contentsOfDirectory(
            at: self.rootDirectory,
            includingPropertiesForKeys: nil,
            options: [])) ?? []
        let temporaryEntries = (try? manager.contentsOfDirectory(
            at: manager.temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [])) ?? []
        candidates += temporaryEntries.filter { entry in
            self.legacyPrefixes.contains { entry.lastPathComponent.hasPrefix($0) }
        }
        var removed = 0
        for candidate in candidates {
            guard let activity = self.lastActivity(of: candidate), activity < cutoff else { continue }
            if (try? manager.removeItem(at: candidate)) != nil { removed += 1 }
        }
        return removed
    }

    /// Newest modification among an entry and its direct children, so a folder
    /// whose file is still being written is not mistaken for a leftover.
    private static func lastActivity(of url: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        var latest = (try? url.resourceValues(forKeys: keys))?.contentModificationDate
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [])) ?? []
        for child in children {
            guard let date = (try? child.resourceValues(forKeys: keys))?.contentModificationDate else { continue }
            if date > (latest ?? .distantPast) { latest = date }
        }
        return latest
    }
}
