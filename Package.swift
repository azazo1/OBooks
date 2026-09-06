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
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20")
    ],
    targets: [
        .executableTarget(
            name: "OBooks",
            dependencies: ["ZIPFoundation"],
            path: "Sources/OBooks"
        ),
        .testTarget(
            name: "OBooksTests",
            dependencies: ["OBooks"],
            path: "Tests/OBooksTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
