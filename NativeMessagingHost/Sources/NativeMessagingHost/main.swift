import Foundation

/// SwiftGetNativeHost — Chrome Native Messaging host binary.
///
/// Chrome launches this process and communicates via stdin/stdout using the
/// Native Messaging protocol: each message is prefixed with a 4-byte
/// little-endian length, followed by the UTF-8 JSON payload.
///
/// This binary receives "add" requests from the Chrome extension and
/// relays them to the main SwiftGet app via the swiftget:// URL scheme.

// MARK: - Message Types

struct IncomingMessage: Codable {
    let action: String
    let url: String?
    let filename: String?
    let referrer: String?
    let cookies: String?
    let requestID: String?
}

struct OutgoingMessage: Codable {
    let success: Bool
    let taskID: String?
    let error: String?
}

// MARK: - I/O Helpers

/// Read exactly `count` bytes from stdin; returns nil on EOF or error.
func readBytes(_ count: Int) -> Data? {
    var data = Data(count: count)
    let read = data.withUnsafeMutableBytes { ptr -> Int in
        guard let base = ptr.baseAddress else { return 0 }
        return Foundation.read(STDIN_FILENO, base, count)
    }
    guard read == count else { return nil }
    return data
}

/// Write a length-prefixed JSON message to stdout.
func writeMessage<T: Encodable>(_ value: T) {
    guard let payload = try? JSONEncoder().encode(value) else { return }
    var length = UInt32(payload.count).littleEndian
    let lengthData = Data(bytes: &length, count: 4)
    FileHandle.standardOutput.write(lengthData)
    FileHandle.standardOutput.write(payload)
}

// MARK: - Main Loop

func runMessageLoop() {
    while true {
        // Read 4-byte length prefix
        guard let lengthData = readBytes(4) else { break }
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        guard length > 0, length < 1_000_000 else { break }  // Sanity check

        // Read message body
        guard let messageData = readBytes(Int(length)) else { break }

        // Decode
        guard let message = try? JSONDecoder().decode(IncomingMessage.self, from: messageData) else {
            writeMessage(OutgoingMessage(success: false, taskID: nil, error: "Invalid JSON"))
            continue
        }

        // Handle
        handle(message: message)
    }
}

func handle(message: IncomingMessage) {
    switch message.action {
    case "add":
        guard let urlString = message.url,
              let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            writeMessage(OutgoingMessage(success: false, taskID: nil, error: "Missing or invalid URL"))
            return
        }

        var components = "swiftget://add?url=\(encodedURL)"
        if let filename = message.filename,
           let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            components += "&filename=\(encodedFilename)"
        }
        if let referrer = message.referrer,
           let encodedReferrer = referrer.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            components += "&referrer=\(encodedReferrer)"
        }
        if let cookies = message.cookies,
           let encodedCookies = cookies.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            components += "&cookies=\(encodedCookies)"
        }

        guard let schemeURL = URL(string: components) else {
            writeMessage(OutgoingMessage(success: false, taskID: nil, error: "Failed to build swiftget:// URL"))
            return
        }

        // Open the URL; this activates SwiftGet and triggers the download
        let result = openURL(schemeURL)
        let taskID = message.requestID ?? UUID().uuidString
        writeMessage(OutgoingMessage(success: result, taskID: taskID, error: result ? nil : "Failed to open SwiftGet"))

    case "ping":
        writeMessage(OutgoingMessage(success: true, taskID: nil, error: nil))

    default:
        writeMessage(OutgoingMessage(success: false, taskID: nil, error: "Unknown action: \(message.action)"))
    }
}

/// Open a URL using the macOS open(1) command (avoids linking AppKit into this minimal binary).
func openURL(_ url: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

// MARK: - Entry Point

runMessageLoop()
