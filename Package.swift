// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "metaLetter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "metaLetter",
            path: "Sources/metaLetter"
        )
    ]
)
