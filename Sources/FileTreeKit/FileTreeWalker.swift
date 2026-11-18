import Foundation

/// A thin wrapper around fts(3): a physical walk (links are not followed), without changing the
/// current folder, staying on one volume. Each entry is the fts entry itself, so a walk over
/// millions of files allocates nothing per file; `kind`, `name` and `allocatedBytes` read it.
public enum FileTreeWalker {
    private static let walkOptions = FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV
    private static let bytesPerBlock: Int64 = 512
    private static let terminatingZeroLength = 1

    /// Calls `visit` for every entry below `path`, the folder itself first; returning false stops
    /// the walk. Folders in `excluded`, by their full path, are left out with everything inside.
    /// Returns false if stopped, if the start cannot be read, or if an error ends it early.
    @discardableResult
    public static func walk(
        _ path: String, excluding excluded: Set<String> = [],
        _ visit: (UnsafeMutablePointer<FTSENT>) -> Bool
    ) -> Bool {
        let pathCopy = strdup(path)
        defer { free(pathCopy) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [pathCopy, nil]
        guard let walkHandle = fts_open(&arguments, walkOptions, nil) else {
            return false
        }
        defer { fts_close(walkHandle) }
        var skippedFolder: UnsafeMutablePointer<FTSENT>?
        while let entry = fts_read(walkHandle) {
            // A start that cannot be read (missing, or no permission) is no walk at all; fts
            // reports it as an entry, not as an error.
            if entry.pointee.fts_level == FTS_ROOTLEVEL
                && [FTS_NS, FTS_ERR, FTS_DNR].contains(kind(of: entry))
            {
                return false
            }
            // fts returns a skipped folder once more as FTS_DP; neither visit reaches `visit`.
            if entry == skippedFolder {
                skippedFolder = nil
                continue
            }
            if !excluded.isEmpty && kind(of: entry) == FTS_D
                && excluded.contains(String(cString: entry.pointee.fts_path))
            {
                fts_set(walkHandle, entry, FTS_SKIP)
                skippedFolder = entry
                continue
            }
            if !visit(entry) { return false }
        }
        // fts_read sets errno to 0 at the regular end and to the error when it gives up early.
        return errno == 0
    }

    /// What the entry is: FTS_F for a file, FTS_D for a folder before its contents, FTS_DP for a
    /// folder after them, FTS_SL for a link, FTS_ERR or FTS_DNR when it could not be read.
    public static func kind(of entry: UnsafeMutablePointer<FTSENT>) -> Int32 {
        Int32(entry.pointee.fts_info)
    }

    public static func name(of entry: UnsafeMutablePointer<FTSENT>) -> String {
        let capacity = Int(entry.pointee.fts_namelen) + terminatingZeroLength
        return withUnsafePointer(to: &entry.pointee.fts_name) { namePointer in
            namePointer.withMemoryRebound(to: CChar.self, capacity: capacity) { characters in
                String(cString: characters)
            }
        }
    }

    public static func path(of entry: UnsafeMutablePointer<FTSENT>) -> String {
        String(cString: entry.pointee.fts_path)
    }

    /// What a file or folder takes on disk, summed over its files, like `du`.
    public static func allocatedBytes(of path: String) -> Int64 {
        var total: Int64 = 0
        walk(path) { entry in
            if kind(of: entry) == FTS_F, let fileStatus = entry.pointee.fts_statp?.pointee {
                total += allocatedBytes(fileStatus)
            }
            return true
        }
        return total
    }

    /// The bytes a file takes on disk, from its status, like `du`.
    public static func allocatedBytes(_ fileStatus: stat) -> Int64 {
        Int64(fileStatus.st_blocks) * bytesPerBlock
    }
}
