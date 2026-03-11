import Foundation

/// Runs yt-dlp to extract video stream URLs and quality options from supported platforms.
actor VideoExtractor {

    static let shared = VideoExtractor()

    // MARK: - Types

    struct VideoInfo {
        let title: String
        let thumbnail: URL?
        let formats: [VideoFormat]
        let bestAudioOnly: VideoFormat?
    }

    struct VideoFormat: Identifiable {
        let id: String         // yt-dlp format_id
        let quality: String    // e.g. "1080p", "720p", "audio only"
        let ext: String        // e.g. "mp4", "webm", "m4a"
        let filesize: Int64?
        let vcodec: String?
        let acodec: String?
        let url: URL?
        var displayLabel: String { "\(quality) \(ext.uppercased())" }
    }

    // MARK: - yt-dlp Path

    private var ytdlpPath: String {
        // The bundled yt-dlp binary inside the app's Resources
        if let resourcesPath = Bundle.main.resourcePath {
            let bundled = resourcesPath + "/yt-dlp"
            if FileManager.default.isExecutableFile(atPath: bundled) {
                return bundled
            }
        }
        // Fallback: search common locations
        for path in ["/usr/local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp", "/usr/bin/yt-dlp"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "yt-dlp"
    }

    // MARK: - Extract Info

    func extractInfo(from url: URL) async throws -> VideoInfo {
        let json = try await runYtDlp(arguments: [
            "--dump-json",
            "--no-playlist",
            url.absoluteString
        ])
        return try parseVideoInfo(from: json)
    }

    // MARK: - Download Video

    func buildDownloadTask(from url: URL, format: VideoFormat, destination: URL) -> DownloadTask {
        // If we have a direct URL, use the regular engine
        if let directURL = format.url {
            return DownloadTask(url: directURL, suggestedFilename: "\(format.displayLabel).\(format.ext)", destinationFolder: destination)
        }
        // Otherwise build a yt-dlp task (handled specially)
        return DownloadTask(url: url, suggestedFilename: nil, destinationFolder: destination)
    }

    func downloadWithYtDlp(
        url: URL,
        formatID: String,
        destination: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let outputTemplate = destination.appendingPathComponent("%(title)s.%(ext)s").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = [
            "-f", formatID,
            "--newline",
            "--progress",
            "-o", outputTemplate,
            url.absoluteString
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let outputHandle = pipe.fileHandleForReading
        var finalPath: URL?

        // Stream output line by line
        for try await line in outputHandle.bytes.lines {
            if line.contains("[download]") && line.contains("%") {
                // Parse progress: "[download]  45.2% of ..."
                if let pct = parseYtDlpProgress(line) {
                    progressHandler(pct)
                }
            } else if line.hasPrefix("[Merger]") || line.contains("Destination:") {
                if let path = parseDestinationPath(line) {
                    finalPath = URL(fileURLWithPath: path)
                }
            }
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VideoExtractorError.ytDlpFailed(process.terminationStatus)
        }
        return finalPath ?? destination
    }

    // MARK: - Update yt-dlp

    func updateYtDlp() async throws {
        _ = try await runYtDlp(arguments: ["-U"])
    }

    // MARK: - Private Helpers

    private func runYtDlp(arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? ""
            throw VideoExtractorError.ytDlpFailed(process.terminationStatus, stderr: errMsg)
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseVideoInfo(from json: String) throws -> VideoInfo {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VideoExtractorError.parseError
        }

        let title = root["title"] as? String ?? "Unknown"
        let thumbnailString = root["thumbnail"] as? String
        let thumbnail = thumbnailString.flatMap { URL(string: $0) }

        var formats: [VideoFormat] = []
        if let rawFormats = root["formats"] as? [[String: Any]] {
            for f in rawFormats {
                let id = f["format_id"] as? String ?? ""
                let ext = f["ext"] as? String ?? "mp4"
                let height = f["height"] as? Int
                let quality: String
                if let h = height {
                    quality = "\(h)p"
                } else if let formatNote = f["format_note"] as? String {
                    quality = formatNote
                } else {
                    quality = f["format"] as? String ?? "unknown"
                }
                let filesize = (f["filesize"] as? Int64) ?? (f["filesize_approx"] as? Int64)
                let urlString = f["url"] as? String
                let directURL = urlString.flatMap { URL(string: $0) }
                let vcodec = f["vcodec"] as? String
                let acodec = f["acodec"] as? String
                formats.append(VideoFormat(
                    id: id,
                    quality: quality,
                    ext: ext,
                    filesize: filesize,
                    vcodec: vcodec,
                    acodec: acodec,
                    url: directURL
                ))
            }
        }

        let audioOnly = formats.first(where: { $0.vcodec == "none" || $0.vcodec == nil })
        return VideoInfo(title: title, thumbnail: thumbnail, formats: formats, bestAudioOnly: audioOnly)
    }

    private func parseYtDlpProgress(_ line: String) -> Double? {
        // e.g. "[download]  45.2% of ~100.00MiB"
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for part in parts {
            if part.hasSuffix("%"), let value = Double(part.dropLast()) {
                return value / 100.0
            }
        }
        return nil
    }

    private func parseDestinationPath(_ line: String) -> String? {
        if let range = line.range(of: "Destination: ") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

// MARK: - Errors

enum VideoExtractorError: LocalizedError {
    case ytDlpNotFound
    case ytDlpFailed(Int32, stderr: String = "")
    case parseError

    var errorDescription: String? {
        switch self {
        case .ytDlpNotFound:
            return "yt-dlp is not installed or not found in the app bundle."
        case .ytDlpFailed(let code, let stderr):
            return "yt-dlp exited with code \(code).\n\(stderr)"
        case .parseError:
            return "Failed to parse video information from yt-dlp output."
        }
    }
}
