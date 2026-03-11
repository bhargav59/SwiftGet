import Foundation

struct NativeMessage: Codable {
    var action: String
    var url: String?
    var filename: String?
    var cookies: String?
    var headers: [String: String]?
    var segmentCount: Int?
}

class NativeMessagingBridge {
    static let shared = NativeMessagingBridge()
    private var inputThread: Thread?
    
    private init() {}
    
    func start() {
        inputThread = Thread {
            self.readLoop()
        }
        inputThread?.name = "NativeMessagingInput"
        inputThread?.start()
    }
    
    private func readLoop() {
        let stdin = FileHandle.standardInput
        
        while true {
            // Chrome Native Messaging protocol: 4-byte little-endian length prefix
            let lengthData = stdin.readData(ofLength: 4)
            guard lengthData.count == 4 else { break }
            
            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            guard length > 0 && length < 1_048_576 else { continue } // Max 1MB
            
            let messageData = stdin.readData(ofLength: Int(length))
            guard messageData.count == Int(length) else { break }
            
            do {
                let message = try JSONDecoder().decode(NativeMessage.self, from: messageData)
                handleMessage(message)
            } catch {
                print("Failed to decode native message: \(error)")
            }
        }
    }
    
    private func handleMessage(_ message: NativeMessage) {
        switch message.action {
        case "download":
            guard let urlString = message.url, let url = URL(string: urlString) else { return }
            DispatchQueue.main.async {
                DownloadManager.shared.addDownload(url: url, segmentCount: message.segmentCount ?? 8)
            }
        case "ping":
            sendResponse(["status": "ok", "version": "1.0"])
        default:
            print("Unknown action: \(message.action)")
        }
    }
    
    func sendResponse(_ data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return }
        var length = UInt32(jsonData.count).littleEndian
        let lengthData = Data(bytes: &length, count: 4)
        FileHandle.standardOutput.write(lengthData)
        FileHandle.standardOutput.write(jsonData)
    }
    
    static func installHostManifest() {
        let manifest: [String: Any] = [
            "name": "com.swiftget.native",
            "description": "SwiftGet Native Messaging Host",
            "path": Bundle.main.executablePath ?? "/Applications/SwiftGet.app/Contents/MacOS/SwiftGet",
            "type": "stdio",
            "allowed_origins": ["chrome-extension://"]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted) else { return }
        
        let hostDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        
        try? FileManager.default.createDirectory(at: hostDir, withIntermediateDirectories: true)
        
        let manifestPath = hostDir.appendingPathComponent("com.swiftget.native.json")
        try? jsonData.write(to: manifestPath)
    }
}
