// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OBooks",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OBooks", targets: ["OBooks"])
    ],
    targets: [
        .executableTarget(
            name: "OBooks",
            path: "Sources/OBooks",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OBooksTests",
            dependencies: ["OBooks"],
            path: "Tests/OBooksTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
