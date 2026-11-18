import Foundation
import Testing

@testable import FileTreeKit

/// A folder of its own for each test, removed when the test ends.
final class TemporaryFolder {
    let path: String

    init() throws {
        path = NSTemporaryDirectory() + "file-tree-kit-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: path) }

    /// Writes a file below the folder, making the folders on the way.
    func write(_ name: String, _ data: Data) throws {
        let file = URL(fileURLWithPath: path).appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }
}

private func bytes(_ count: Int, _ value: UInt8) -> Data { Data(repeating: value, count: count) }

@Test("The walk visits every entry and leaves out excluded folders with their contents")
func walkVisitsAndExcludes() throws {
    let folder = try TemporaryFolder()
    try folder.write("a/one.txt", bytes(10, 1))
    try folder.write("skip/two.txt", bytes(10, 2))
    var names: [String] = []
    let finished = FileTreeWalker.walk(folder.path, excluding: [folder.path + "/skip"]) { entry in
        if FileTreeWalker.kind(of: entry) == FTS_F { names.append(FileTreeWalker.name(of: entry)) }
        return true
    }
    #expect(finished)
    #expect(names == ["one.txt"])
}

@Test("Returning false stops the walk, and a missing folder is reported")
func walkStopsAndReportsMissingFolders() throws {
    let folder = try TemporaryFolder()
    try folder.write("one.txt", bytes(1, 1))
    var visited = 0
    #expect(
        !FileTreeWalker.walk(folder.path) { _ in
            visited += 1
            return false
        })
    #expect(visited == 1)
    #expect(!FileTreeWalker.walk(folder.path + "/missing") { _ in true })
}

@Test("A start folder that cannot be read is no finished walk")
func unreadableStartIsReported() throws {
    let folder = try TemporaryFolder()
    let locked = folder.path + "/locked"
    try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: false)
    chmod(locked, 0)
    defer { chmod(locked, 0o755) }
    #expect(!FileTreeWalker.walk(locked) { _ in true })
}

@Test("Hard links to one file are no duplicates")
func hardLinksCountOnce() async throws {
    let folder = try TemporaryFolder()
    try folder.write("original.bin", bytes(5_000, 4))
    try FileManager.default.linkItem(
        atPath: folder.path + "/original.bin", toPath: folder.path + "/link.bin")
    #expect(DuplicateFinder.files(in: folder.path).count == 1)
    #expect(await DuplicateFinder.duplicates(in: folder.path, smallestBytes: 1).isEmpty)
}

@Test("Allocated bytes count what the files take on disk")
func allocatedBytesCountTheFiles() throws {
    let folder = try TemporaryFolder()
    try folder.write("one.bin", bytes(100_000, 1))
    #expect(FileTreeWalker.allocatedBytes(of: folder.path) >= 100_000)
}

@Test("Only files of equal size and the same content are duplicates")
func duplicatesNeedTheSameContent() async throws {
    let folder = try TemporaryFolder()
    let sample = 1_000_000
    // Same first megabyte, different afterwards: only the full read keeps them apart.
    let twin = bytes(sample, 7) + bytes(500_000, 1)
    try folder.write("copy-a.bin", twin)
    try folder.write("nested/copy-b.bin", twin)
    try folder.write("lookalike.bin", bytes(sample, 7) + bytes(500_000, 2))
    try folder.write("small-a.bin", bytes(10, 3))
    try folder.write("small-b.bin", bytes(10, 3))
    let groups = await DuplicateFinder.duplicates(in: folder.path, smallestBytes: 1_000)
    let names = groups.map { group in
        group.map { file in URL(fileURLWithPath: file.path).lastPathComponent }.sorted()
    }
    #expect(names == [["copy-a.bin", "copy-b.bin"]])
    #expect(DuplicateFinder.spareBytes(groups) == Int64(twin.count))
}

@Test("A removed file leaves a group, and a group of one is no duplicate")
func removingAFileUpdatesTheGroups() {
    let files = [FileInfo(path: "/a", bytes: 50), FileInfo(path: "/b", bytes: 50)]
    let groups = DuplicateFinder.sameSizeGroups(files, smallestBytes: 1)
    #expect(groups.count == 1)
    #expect(DuplicateFinder.without("/a", in: groups).isEmpty)
    #expect(DuplicateFinder.spareBytes([[], [FileInfo(path: "/c", bytes: 9)]]) == 0)
}
