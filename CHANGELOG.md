# Changelog

All notable changes to this project are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-18

### Added

- `FileTreeWalker`: a physical fts(3) walk on one volume, with folders to leave out, and sizes
  on disk like `du`. Taken from storage-manager.
- `DuplicateFinder`: same size, first megabyte, full read; for a folder, or for any `SizedFile`
  list; cancelable with its task.

### Fixed

- A walk whose start cannot be read (missing, or no permission) now returns false; fts reports
  that as an entry, so it looked like a finished walk before.
- Hard links to one file no longer count as duplicates; removing a link frees nothing.
- `duplicates(in:)` walks the folder off the caller's actor too, not only the reading.

[0.1.0]: https://github.com/Robertwlt03/file-tree-kit/releases/tag/v0.1.0
