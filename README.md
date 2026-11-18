<p align="center">
  <img src="assets/banner-readme.svg" alt="file-tree-kit: walk a file tree fast and find duplicates." width="100%">
</p>

Two building blocks every Mac tool that looks into folders needs: a fast walk over a file tree with fts(3), and a search
for files that exist more than once, which reads as few files as possible.

## <img src="assets/icons/features.svg" height="33" align="absmiddle" alt="">What it does

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/pictures/features-dark.svg">
  <img src="assets/pictures/features-light.svg" alt="Fast walk: fts(3) without changing folders, on one volume, nothing allocated per file. Leave folders out: skip caches, build folders or anything else with everything inside. Sizes like du: the bytes a file or folder really takes on disk. Duplicates: equal size, first megabyte, full read, so very few files are read whole. Cancelable: the search reads in the background and stops when its task is canceled. No dependencies: Foundation and CryptoKit, Swift 6 with strict concurrency." width="100%">
</picture>

## <img src="assets/icons/install.svg" height="33" align="absmiddle" alt="">Install

Swift 6, macOS 13 or iOS 16. In `Package.swift`, then add the product `FileTreeKit` to your target:

```swift
dependencies: [.package(url: "https://github.com/Robertwlt03/file-tree-kit", from: "0.1.0")]
```

## <img src="assets/icons/use.svg" height="33" align="absmiddle" alt="">Use

Walk a folder; returning `false` stops the walk:

```swift
import FileTreeKit

var largest: (path: String, bytes: Int64) = ("", 0)
FileTreeWalker.walk("/Users/me", excluding: ["/Users/me/Library/Caches"]) { entry in
    if FileTreeWalker.kind(of: entry) == FTS_F, let status = entry.pointee.fts_statp?.pointee {
        let bytes = FileTreeWalker.allocatedBytes(status)
        if bytes > largest.bytes { largest = (FileTreeWalker.path(of: entry), bytes) }
    }
    return true
}
```

The walk is physical (links are not followed), never changes the current folder and stays on the volume it starts on.
Each entry is fts's own, so walking millions of files allocates nothing per file. `walk` returns `false` when it was
stopped, when the start cannot be read, or when an error ended it early.

```swift
let onDisk = FileTreeWalker.allocatedBytes(of: "/Users/me/Movies")
```

## <img src="assets/icons/duplicates.svg" height="33" align="absmiddle" alt="">Duplicates

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/pictures/flow-dark.svg">
  <img src="assets/pictures/flow-light.svg" alt="1 Same size: only files of equal size can be duplicates; the walk already knows every size. 2 First megabyte: a hash of the first megabyte splits most groups apart. 3 Full read: only what is still together is read in full and hashed." width="100%">
</picture>

```swift
let groups = await DuplicateFinder.duplicates(in: "/Users/me/Downloads")
let freeable = DuplicateFinder.spareBytes(groups)  // keep one of each, remove the rest
```

Files under 10 MB are left out by default (`smallestBytes:`), since they hardly free space and would mean reading many
more files. Have your own file list, such as a scanned tree? Make its type `SizedFile` (a `path` and `bytes`) and use
`sameSizeGroups`, then `confirmed`; `without(_:in:)` updates the groups once a file is gone.

Hard links to one file count once. APFS clones share their blocks too, so removing one frees nothing; macOS offers no
way to tell a clone from a copy by its path, so the search counts both.

## <img src="assets/icons/contribute.svg" height="33" align="absmiddle" alt="">Contribute

Issues and pull requests are welcome. The tests build small trees in a temporary folder:

```bash
swift test
```

## <img src="assets/icons/license.svg" height="33" align="absmiddle" alt="">License

[MIT](LICENSE)
