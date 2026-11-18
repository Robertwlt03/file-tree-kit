// swift-tools-version:6.0
// Walks a file tree fast with fts(3) and finds files that exist more than once.
//
// Start:  add https://github.com/Robertwlt03/file-tree-kit as a package dependency, then
//         import FileTreeKit; swift test runs the tests
// Needs:  Swift 6, macOS 13 or iOS 16 (CryptoKit hashes the files)
import PackageDescription

let package = Package(
    name: "FileTreeKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "FileTreeKit", targets: ["FileTreeKit"])
    ],
    targets: [
        .target(name: "FileTreeKit"),
        .testTarget(name: "FileTreeKitTests", dependencies: ["FileTreeKit"]),
    ]
)
