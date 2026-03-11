import Foundation
import Combine

// MARK: - Download Category

enum DownloadCategory: String, CaseIterable, Identifiable {
    case all = "All Downloads"
    case videos = "Videos"
    case documents = "Documents"
    case music = "Music"
    case archives = "Archives"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all:       return "arrow.down.circle"
        case .videos:    return "film"
        case .documents: return "doc"
        case .music:     return "music.note"
        case .archives:  return "archivebox"
        case .other:     return "folder"
        }
    }

    static func category(for url: URL, mimeType: String? = nil) -> DownloadCategory {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return .videos }
        if documentExtensions.contains(ext) { return .documents }
        if musicExtensions.contains(ext) { return .music }
        if archiveExtensions.contains(ext) { return .archives }
        if let mime = mimeType {
            if mime.hasPrefix("video/") { return .videos }
            if mime.hasPrefix("audio/") { return .music }
            if mime.hasPrefix("application/zip") ||
               mime.hasPrefix("application/x-") { return .archives }
        }
        return .other
    }

    private static let videoExtensions: Set<String> = [
        "mp4","m4v","mov","avi","mkv","webm","flv","wmv","ts","m3u8","mpd","mpeg","mpg"
    ]
    private static let documentExtensions: Set<String> = [
        "pdf","doc","docx","xls","xlsx","ppt","pptx","txt","rtf","epub","pages","numbers","key"
    ]
    private static let musicExtensions: Set<String> = [
        "mp3","aac","flac","wav","ogg","m4a","wma","opus","alac"
    ]
    private static let archiveExtensions: Set<String> = [
        "zip","tar","gz","bz2","7z","rar","xz","dmg","pkg","iso"
    ]
}

// MARK: - Download Status

enum DownloadStatus: String, Codable {
    case queued     = "Queued"
    case downloading = "Downloading"
    case paused     = "Paused"
    case assembling = "Assembling"
    case completed  = "Completed"
    case failed     = "Failed"
    case scheduled  = "Scheduled"

    var isTerminal: Bool {
        self == .completed || self == .failed
    }

    var isActive: Bool {
        self == .downloading || self == .assembling
    }
}

// MARK: - Download Priority

enum DownloadPriority: Int, Codable, CaseIterable {
    case low    = 0
    case normal = 1
    case high   = 2

    var label: String {
        switch self {
        case .low:    return "Low"
        case .normal: return "Normal"
        case .high:   return "High"
        }
    }
}

// MARK: - Download Segment

struct DownloadSegment: Identifiable, Codable {
    let id: Int
    let startByte: Int64
    let endByte: Int64
    var downloadedBytes: Int64 = 0
    var isComplete: Bool = false

    var progress: Double {
        let total = endByte - startByte + 1
        guard total > 0 else { return isComplete ? 1.0 : 0.0 }
        return Double(downloadedBytes) / Double(total)
    }
}

// MARK: - DownloadTask

@MainActor
final class DownloadTask: ObservableObject, Identifiable {

    // MARK: Persistent Properties
    let id: UUID
    let url: URL
    var suggestedFilename: String?
    var referrer: String?
    var cookies: String?
    var destinationFolder: URL
    var priority: DownloadPriority
    var category: DownloadCategory
    var scheduledAt: Date?
    var createdAt: Date

    // MARK: Runtime State
    @Published var status: DownloadStatus = .queued
    @Published var totalBytes: Int64 = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var speed: Double = 0          // bytes/sec
    @Published var segments: [DownloadSegment] = []
    @Published var errorMessage: String?
    @Published var filename: String
    @Published var mimeType: String?
    @Published var etag: String?
    @Published var checksumMD5: String?
    @Published var checksumSHA256: String?

    // Speed history for live graph (last 60 samples)
    @Published var speedHistory: [Double] = Array(repeating: 0, count: 60)

    // MARK: Computed
    var displayName: String { filename.isEmpty ? url.lastPathComponent : filename }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }

    var eta: TimeInterval? {
        guard speed > 0, totalBytes > 0 else { return nil }
        let remaining = totalBytes - downloadedBytes
        return Double(remaining) / speed
    }

    var formattedSize: String {
        guard totalBytes > 0 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var formattedSpeed: String {
        guard speed > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
    }

    var formattedETA: String {
        guard let eta else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: eta) ?? ""
    }

    var localFileURL: URL {
        destinationFolder.appendingPathComponent(filename)
    }

    // MARK: Init

    init(
        id: UUID = UUID(),
        url: URL,
        suggestedFilename: String? = nil,
        referrer: String? = nil,
        cookies: String? = nil,
        destinationFolder: URL? = nil,
        priority: DownloadPriority = .normal,
        scheduledAt: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.suggestedFilename = suggestedFilename
        self.referrer = referrer
        self.cookies = cookies
        self.priority = priority
        self.scheduledAt = scheduledAt
        self.createdAt = Date()

        // Determine filename
        let rawName = suggestedFilename ?? url.lastPathComponent
        self.filename = rawName.isEmpty ? "download" : rawName

        // Destination folder
        let defaultFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        self.destinationFolder = destinationFolder ?? defaultFolder

        // Auto-categorize
        self.category = DownloadCategory.category(for: url)
    }

    // MARK: Helpers

    func updateSpeedHistory(_ newSpeed: Double) {
        speedHistory.removeFirst()
        speedHistory.append(newSpeed)
        speed = newSpeed
    }
}
