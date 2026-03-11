import Foundation
import Combine

public enum DownloadStatus: String, Codable, CaseIterable {
    case queued = "Queued"
    case downloading = "Downloading"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

public enum DownloadPriority: String, Codable, CaseIterable {
    case high = "High"
    case normal = "Normal"
    case low = "Low"
}

public enum FileCategory: String, Codable, CaseIterable {
    case video = "Videos"
    case document = "Documents"
    case music = "Music"
    case archive = "Archives"
    case other = "Other"
    
    static func from(url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "avi", "mov", "webm", "m3u8", "mpd", "flv":
            return .video
        case "pdf", "doc", "docx", "txt", "xlsx", "pptx":
            return .document
        case "mp3", "aac", "flac", "wav", "m4a", "ogg":
            return .music
        case "zip", "tar", "gz", "rar", "7z", "dmg", "pkg":
            return .archive
        default:
            return .other
        }
    }
}

public class DownloadItem: ObservableObject, Identifiable {
    public let id: UUID
    public let url: URL
    
    @Published public var status: DownloadStatus = .queued
    @Published public var progress: Double = 0.0
    @Published public var downloadedBytes: Int64 = 0
    @Published public var totalBytes: Int64 = 0
    @Published public var speed: Double = 0.0 // bytes per second
    @Published public var eta: TimeInterval = 0.0
    @Published public var filename: String
    @Published public var savePath: URL
    @Published public var priority: DownloadPriority = .normal
    @Published public var category: FileCategory
    @Published public var segments: [DownloadSegment] = []
    @Published public var errorMessage: String?
    
    public var createdAt: Date = Date()
    public var completedAt: Date?
    public var segmentCount: Int = 8
    public var bandwidthLimit: Double = 0 // 0 = unlimited, bytes/s
    public var scheduledTime: Date?
    
    public init(url: URL, savePath: URL? = nil) {
        self.id = UUID()
        self.url = url
        self.filename = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        self.category = FileCategory.from(url: url)
        let defaultDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.savePath = savePath ?? defaultDir.appendingPathComponent(self.filename)
    }
    
    public var formattedSize: String {
        guard totalBytes > 0 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    public var formattedSpeed: String {
        guard speed > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
    }
    
    public var formattedETA: String {
        guard eta > 0 && eta < .infinity else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: eta) ?? ""
    }
}

public class DownloadSegment: ObservableObject, Identifiable {
    public let id: UUID
    public var index: Int
    public var startByte: Int64
    public var endByte: Int64
    @Published public var downloadedBytes: Int64 = 0
    @Published public var isCompleted: Bool = false
    
    public init(index: Int, startByte: Int64, endByte: Int64) {
        self.id = UUID()
        self.index = index
        self.startByte = startByte
        self.endByte = endByte
    }
    
    public var totalBytes: Int64 { endByte - startByte + 1 }
    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }
}
