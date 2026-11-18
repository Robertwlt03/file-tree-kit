# file-tree-kit: working notes for Claude

## Toolchain

- Swift 6 package `FileTreeKit`, Foundation and CryptoKit only, macOS 13 and iOS 16.
- swift format (`.swift-format`) and SwiftLint (`.swiftlint.yml`), lines at most 100 characters.
- check-pipeline runs every check (`check-pipeline.toml`).

## Commands

- Tests: `swift test`
- All checks, as CI runs them: `check-pipeline`

## Hard rules

- No dependency beyond Foundation and CryptoKit.
- The walk allocates nothing per entry: it hands out fts's own entries; helpers read them.
- The duplicate search reads files only off the calling actor and stops when its task is canceled.
- Tests write only into their own temporary folder.

## Where things go

- The walk: `Sources/FileTreeKit/FileTreeWalker.swift`
- The duplicate search: `Sources/FileTreeKit/DuplicateFinder.swift`
- Tests: `Tests/FileTreeKitTests/`

## Before every commit

Run `check-pipeline`; add a line to `CHANGELOG.md` under a new version for anything a user notices.

## Git

- English everywhere; commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:` …).
- Work on a branch and merge into `main` through a pull request with green CI.
- A release is a tag `vX.Y.Z` that matches `CHANGELOG.md`.
