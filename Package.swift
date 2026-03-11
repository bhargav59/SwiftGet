// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftGet",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "SwiftGetNativeHost", targets: ["NativeMessagingHost"]),
    ],
    dependencies: [],
    targets: [
        // Native Messaging Host — lightweight command-line binary
        .executableTarget(
            name: "NativeMessagingHost",
            path: "NativeMessagingHost/Sources/NativeMessagingHost"
        ),
    ]
)
