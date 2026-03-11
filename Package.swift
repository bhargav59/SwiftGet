// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftGet",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "SwiftGet", targets: ["SwiftGet"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SwiftGet",
            path: "Sources/SwiftGet",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SwiftGetTests",
            dependencies: ["SwiftGet"],
            path: "Tests/SwiftGetTests"
        )
    ]
)
