import Foundation

/// Message structure sent from Chrome Extension to SwiftGet via Native Messaging.
struct NativeMessage: Codable {
    let action: String      // "add", "query", "pause", "resume"
    let url: String?
    let filename: String?
    let referrer: String?
    let cookies: String?
    let requestID: String?
}

/// Response sent back to the Chrome Extension.
struct NativeResponse: Codable {
    let success: Bool
    let taskID: String?
    let error: String?
    let downloads: [NativeDownloadInfo]?

    struct NativeDownloadInfo: Codable {
        let id: String
        let filename: String
        let status: String
        let progress: Double
        let speed: Double
        let totalBytes: Int64
        let downloadedBytes: Int64
    }
}

/// Runs an HTTPS/Unix server to receive messages from the Chrome extension.
/// Uses stdin/stdout Native Messaging protocol (length-prefixed JSON).
@MainActor
final class NativeMessagingServer {

    static let shared = NativeMessagingServer()

    private var isRunning = false
    private var listeningTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Install the native messaging host manifest on first launch
        installManifestIfNeeded()
    }

    func stop() {
        isRunning = false
        listeningTask?.cancel()
    }

    // MARK: - Manifest Installation

    private func installManifestIfNeeded() {
        let hostName = "com.swiftget.nativehost"
        let manifestDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")

        try? FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)

        let manifestURL = manifestDir.appendingPathComponent("\(hostName).json")
        guard !FileManager.default.fileExists(atPath: manifestURL.path) else { return }

        // Path to the helper binary bundled inside SwiftGet.app
        let helperPath: String
        if let resourcesPath = Bundle.main.resourcePath {
            helperPath = (resourcesPath as NSString)
                .deletingLastPathComponent
                .appending("/MacOS/SwiftGetNativeHost")
        } else {
            helperPath = "/Applications/SwiftGet.app/Contents/MacOS/SwiftGetNativeHost"
        }

        let manifest: [String: Any] = [
            "name": hostName,
            "description": "SwiftGet Native Messaging Host",
            "path": helperPath,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://PLACEHOLDER_EXTENSION_ID/"
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted) {
            try? data.write(to: manifestURL)
        }
    }

    // MARK: - Message Handling (called by NativeHost binary via XPC/socket)

    func handleMessage(_ message: NativeMessage) {
        NotificationCenter.default.post(name: .nativeMessageReceived, object: message)
    }
}
