// swift-tools-version: 5.10
// SPM-Build-Alternative zu xcodegen/xcodebuild — erlaubt Bauen ohne volles Xcode
// (nur Command Line Tools). Bundle-Assembly übernimmt build-spm.sh im Repo-Root.
import PackageDescription

let package = Package(
    name: "Blitztext",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "0.18.0")
    ],
    targets: [
        .executableTarget(
            name: "Blitztext",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: ".",
            exclude: ["Resources", "project.yml"],
            sources: ["App", "Features", "Services", "Views"]
        )
    ]
)
