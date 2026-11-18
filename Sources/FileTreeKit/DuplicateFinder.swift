import CryptoKit
import Foundation

// ponytail: APFS clones share their blocks, so removing one frees nothing; telling them apart
// needs the clone ID that macOS does not offer for a path.

/// A file the duplicate search can compare: where it is and how many bytes it holds.
public protocol SizedFile: Sendable {
    var path: String { get }
    var bytes: Int64 { get }
}

/// A file found by `DuplicateFinder.duplicates(in:)`.
public struct FileInfo: SizedFile, Hashable {
    public let path: String
    public let bytes: Int64

    public init(path: String, bytes: Int64) {
        self.path = path
        self.bytes = bytes
    }
}

/// Finds files that exist more than once with the same content, in three steps: only files of
/// equal size can be duplicates, then a hash of their first megabyte splits them, and only what
/// is still together is read in full. So very few files are ever read whole.
public enum DuplicateFinder {
    /// Smaller duplicates hardly free space and would mean reading many more files.
    public static let defaultSmallestBytes: Int64 = 10_000_000
    private static let sampleBytes = 1_000_000
    private static let chunkBytes = 4_000_000

    /// The duplicates among the files below a folder, the biggest first; reads in the background
    /// and ends early when the calling task is canceled.
    public static func duplicates(
        in folder: String, smallestBytes: Int64 = defaultSmallestBytes
    ) async -> [[FileInfo]] {
        // The walk too runs off the caller's actor: a big folder would hold the main thread.
        let walking = Task.detached(priority: .utility) {
            sameSizeGroups(files(in: folder), smallestBytes: smallestBytes)
        }
        return await confirmed(await walking.value)
    }

    /// Every file below a folder with its size in bytes; hard links to one file count once, since
    /// removing a link frees nothing.
    public static func files(in folder: String) -> [FileInfo] {
        var found: [FileInfo] = []
        var seenLinks: Set<String> = []
        FileTreeWalker.walk(folder) { entry in
            guard FileTreeWalker.kind(of: entry) == FTS_F,
                let status = entry.pointee.fts_statp?.pointee
            else { return true }
            let isNew =
                status.st_nlink < 2
                || seenLinks.insert("\(status.st_dev)-\(status.st_ino)").inserted
            if isNew {
                found.append(
                    FileInfo(path: FileTreeWalker.path(of: entry), bytes: Int64(status.st_size)))
            }
            return true
        }
        return found
    }

    /// Files of equal size, the biggest size first; only these can be duplicates.
    public static func sameSizeGroups<File: SizedFile>(
        _ files: [File], smallestBytes: Int64 = defaultSmallestBytes
    ) -> [[File]] {
        let candidates = files.filter { file in file.bytes >= smallestBytes }
        return Dictionary(grouping: candidates, by: \.bytes).values
            .filter { group in group.count > 1 }
            .sorted { first, second in first[0].bytes > second[0].bytes }
    }

    /// The groups once a file is gone; a group with a single file left is no duplicate any more.
    public static func without<File: SizedFile>(_ path: String, in groups: [[File]]) -> [[File]] {
        groups.map { group in group.filter { file in file.path != path } }
            .filter { group in group.count > 1 }
    }

    /// What keeping one file of each group and removing the others would free.
    public static func spareBytes<File: SizedFile>(_ groups: [[File]]) -> Int64 {
        groups.reduce(0) { total, group in
            total + (group.first?.bytes ?? 0) * Int64(max(group.count - 1, 0))
        }
    }

    /// The groups whose files really have the same content, read in the background; ends early
    /// when the calling task is canceled.
    public static func confirmed<File: SizedFile>(_ groups: [[File]]) async -> [[File]] {
        let reading = Task.detached(priority: .utility) {
            split(split(groups, by: sampleDigest), by: fullDigest)
        }
        return await withTaskCancellationHandler {
            await reading.value
        } onCancel: {
            reading.cancel()
        }
    }

    /// Splits each group by the key of its files; files without a key and single files drop out.
    static func split<File: SizedFile>(_ groups: [[File]], by key: (String) -> Data?) -> [[File]] {
        groups.flatMap { group in
            let keyed = group.compactMap { file in key(file.path).map { digest in (file, digest) } }
            return Dictionary(grouping: keyed, by: \.1).values
                .map { pairs in pairs.map(\.0) }
                .filter { files in files.count > 1 }
        }
    }

    private static func sampleDigest(_ path: String) -> Data? { digest(path, upTo: sampleBytes) }
    private static func fullDigest(_ path: String) -> Data? { digest(path, upTo: .max) }

    private static func digest(_ path: String, upTo limit: Int) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit
        while remaining > 0, !Task.isCancelled {
            let readBytes = readChunk(of: handle, upTo: remaining, into: &hasher)
            guard readBytes > 0 else { break }
            remaining -= readBytes
        }
        return Task.isCancelled ? nil : Data(hasher.finalize())
    }

    /// Adds the next chunk to the hash and returns its length, 0 at the end. The pool frees each
    /// chunk at once; otherwise a large file would stay in memory until the search ends.
    private static func readChunk(of handle: FileHandle, upTo limit: Int, into hasher: inout SHA256)
        -> Int
    {
        autoreleasepool {
            guard let chunk = try? handle.read(upToCount: min(chunkBytes, limit)) else { return 0 }
            hasher.update(data: chunk)
            return chunk.count
        }
    }
}
