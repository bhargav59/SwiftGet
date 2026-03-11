import Foundation
import CommonCrypto

/// Multi-segment parallel HTTP download engine.
/// Each segment is downloaded on an independent URLSession data task.
actor DownloadEngine {

    // MARK: - Properties

    private let task: DownloadTask
    private let segmentCount: Int
    private let bandwidthLimit: Double
    private var session: URLSession
    private var segmentTasks: [Int: URLSessionDataTask] = [:]
    private var segmentBuffers: [Int: Data] = [:]
    private var isCancelled = false
    private var isPaused = false

    // Speed sampling
    private var lastSampleBytes: Int64 = 0
    private var lastSampleTime: Date = Date()

    // MARK: - Init

    init(task: DownloadTask, segmentCount: Int = 8, bandwidthLimit: Double = 0) {
        self.task = task
        self.segmentCount = segmentCount
        self.bandwidthLimit = bandwidthLimit
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        // Forward cookies from the task
        if let cookieHeader = task.cookies {
            config.httpAdditionalHeaders = ["Cookie": cookieHeader]
        }
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func start() async {
        guard !isCancelled else { return }

        // 1. HEAD request to determine file size and Range support
        let (supportsRanges, fileSize, filename, mimeType, etag) = await probeServer()

        await MainActor.run {
            if fileSize > 0 { task.totalBytes = fileSize }
            if let fn = filename, !fn.isEmpty { task.filename = fn }
            task.mimeType = mimeType
            task.etag = etag
            if task.category == .other, let mime = mimeType {
                task.category = DownloadCategory.category(for: task.url, mimeType: mime)
            }
        }

        // 2. Resume existing segments or build new segment list
        let segments = buildSegments(fileSize: fileSize, supportsRanges: supportsRanges)
        await MainActor.run { task.segments = segments }

        // 3. Download each segment
        if supportsRanges && segments.count > 1 {
            await downloadParallel(segments: segments)
        } else {
            await downloadSingleThread()
        }

        guard !isCancelled, !isPaused else { return }

        // 4. Assemble segments into final file
        await MainActor.run { task.status = .assembling }
        do {
            try await assembleFile(segments: segments, fileSize: fileSize, supportsRanges: supportsRanges)
            await MainActor.run {
                task.status = .completed
                task.downloadedBytes = task.totalBytes
                task.speed = 0
            }
        } catch {
            await MainActor.run {
                task.status = .failed
                task.errorMessage = error.localizedDescription
            }
        }
    }

    func pause() {
        isPaused = true
        segmentTasks.values.forEach { $0.suspend() }
    }

    func cancel() {
        isCancelled = true
        segmentTasks.values.forEach { $0.cancel() }
        session.invalidateAndCancel()
    }

    func sampleSpeed() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleTime)
        guard elapsed >= 0.9 else { return }

        Task {
            let currentBytes = await MainActor.run { task.downloadedBytes }
            let delta = currentBytes - lastSampleBytes
            let speed = elapsed > 0 ? Double(delta) / elapsed : 0
            lastSampleBytes = currentBytes
            lastSampleTime = now
            await MainActor.run { task.updateSpeedHistory(max(0, speed)) }
        }
    }

    // MARK: - Server Probe

    private func probeServer() async -> (supportsRanges: Bool, fileSize: Int64, filename: String?, mimeType: String?, etag: String?) {
        var request = URLRequest(url: task.url)
        request.httpMethod = "HEAD"
        if let referrer = task.referrer {
            request.setValue(referrer, forHTTPHeaderField: "Referer")
        }
        request.setValue("SwiftGet/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (false, 0, nil, nil, nil)
            }
            let supportsRanges = http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"
            let contentLength = Int64(http.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
            let mimeType = http.mimeType
            let etag = http.value(forHTTPHeaderField: "ETag")

            // Try to derive filename from Content-Disposition
            var filename: String?
            if let disposition = http.value(forHTTPHeaderField: "Content-Disposition") {
                filename = parseFilename(from: disposition)
            }
            return (supportsRanges, contentLength, filename, mimeType, etag)
        } catch {
            return (false, 0, nil, nil, nil)
        }
    }

    private func parseFilename(from contentDisposition: String) -> String? {
        // e.g.: attachment; filename="file.zip" or filename*=UTF-8''file%20name.zip
        let parts = contentDisposition.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("filename=") {
                var name = String(trimmed.dropFirst("filename=".count))
                name = name.trimmingCharacters(in: .init(charactersIn: "\""))
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    // MARK: - Segment Building

    private func buildSegments(fileSize: Int64, supportsRanges: Bool) -> [DownloadSegment] {
        guard supportsRanges, fileSize > 0, segmentCount > 1 else {
            // Single segment covering the whole file
            return [DownloadSegment(id: 0, startByte: 0, endByte: max(0, fileSize - 1))]
        }

        // Check for existing partial segments (resume support)
        let existing = task.segments
        if !existing.isEmpty && existing.allSatisfy({ $0.endByte <= fileSize - 1 }) {
            return existing
        }

        let count = min(segmentCount, 32)
        let segmentSize = fileSize / Int64(count)
        var segments: [DownloadSegment] = []
        for i in 0..<count {
            let start = Int64(i) * segmentSize
            let end: Int64
            if i == count - 1 {
                end = fileSize - 1
            } else {
                end = start + segmentSize - 1
            }
            segments.append(DownloadSegment(id: i, startByte: start, endByte: end))
        }
        return segments
    }

    // MARK: - Parallel Download

    private func downloadParallel(segments: [DownloadSegment]) async {
        await withTaskGroup(of: Void.self) { group in
            for segment in segments where !segment.isComplete {
                group.addTask { [weak self] in
                    await self?.downloadSegment(segment)
                }
            }
        }
    }

    private func downloadSegment(_ segment: DownloadSegment) async {
        guard !isCancelled, !isPaused else { return }

        var request = URLRequest(url: task.url)
        let resumeOffset = segment.startByte + segment.downloadedBytes
        request.setValue("bytes=\(resumeOffset)-\(segment.endByte)", forHTTPHeaderField: "Range")
        if let referrer = task.referrer {
            request.setValue(referrer, forHTTPHeaderField: "Referer")
        }
        request.setValue("SwiftGet/1.0", forHTTPHeaderField: "User-Agent")

        let tempURL = segmentTempURL(for: segment.id)

        do {
            let (asyncBytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (http.statusCode == 200 || http.statusCode == 206) else {
                await MainActor.run {
                    task.status = .failed
                    task.errorMessage = "Server returned unexpected status code"
                }
                return
            }

            // Stream bytes to temp file
            let outputStream = OutputStream(url: tempURL, append: true)!
            outputStream.open()
            var buffer = [UInt8](repeating: 0, count: 65536)
            var bufferIndex = 0
            var bytesWritten: Int64 = 0

            for try await byte in asyncBytes {
                guard !isCancelled, !isPaused else {
                    outputStream.close()
                    return
                }
                buffer[bufferIndex] = byte
                bufferIndex += 1
                if bufferIndex == buffer.count {
                    outputStream.write(&buffer, maxLength: bufferIndex)
                    bufferIndex = 0
                }
                bytesWritten += 1

                // Update progress periodically
                if bytesWritten % 65536 == 0 {
                    await MainActor.run {
                        let idx = self.task.segments.firstIndex { $0.id == segment.id }
                        if let idx {
                            self.task.segments[idx].downloadedBytes = bytesWritten
                        }
                        self.task.downloadedBytes = self.task.segments
                            .map { $0.downloadedBytes }
                            .reduce(0, +)
                    }
                }
            }

            if bufferIndex > 0 {
                outputStream.write(&buffer, maxLength: bufferIndex)
            }
            outputStream.close()

            // Mark segment complete
            await MainActor.run {
                let idx = self.task.segments.firstIndex { $0.id == segment.id }
                if let idx {
                    self.task.segments[idx].downloadedBytes = bytesWritten
                    self.task.segments[idx].isComplete = true
                }
                self.task.downloadedBytes = self.task.segments
                    .map { $0.downloadedBytes }
                    .reduce(0, +)
            }
        } catch {
            guard !isCancelled, !isPaused else { return }
            await MainActor.run {
                task.status = .failed
                task.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Single Thread Download

    private func downloadSingleThread() async {
        var request = URLRequest(url: task.url)
        if let referrer = task.referrer {
            request.setValue(referrer, forHTTPHeaderField: "Referer")
        }
        request.setValue("SwiftGet/1.0", forHTTPHeaderField: "User-Agent")

        // Support resuming partial single-thread downloads
        let tempURL = segmentTempURL(for: 0)
        let existingSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }

        do {
            let (asyncBytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (http.statusCode == 200 || http.statusCode == 206) else { return }

            if task.totalBytes == 0, let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
               let size = Int64(contentLength) {
                await MainActor.run { task.totalBytes = size + existingSize }
            }

            let outputStream = OutputStream(url: tempURL, append: existingSize > 0)!
            outputStream.open()
            var buffer = [UInt8](repeating: 0, count: 65536)
            var bufferIndex = 0
            var bytesWritten: Int64 = existingSize

            for try await byte in asyncBytes {
                guard !isCancelled, !isPaused else {
                    outputStream.close()
                    return
                }
                buffer[bufferIndex] = byte
                bufferIndex += 1
                if bufferIndex == buffer.count {
                    outputStream.write(&buffer, maxLength: bufferIndex)
                    bufferIndex = 0
                    bytesWritten += Int64(buffer.count)
                    await MainActor.run { self.task.downloadedBytes = bytesWritten }
                }
            }
            if bufferIndex > 0 {
                outputStream.write(&buffer, maxLength: bufferIndex)
                bytesWritten += Int64(bufferIndex)
            }
            outputStream.close()
            await MainActor.run { task.downloadedBytes = bytesWritten }
        } catch {
            guard !isCancelled, !isPaused else { return }
            await MainActor.run {
                task.status = .failed
                task.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Assembly

    private func assembleFile(segments: [DownloadSegment], fileSize: Int64, supportsRanges: Bool) async throws {
        let destination = task.localFileURL
        let finalURL = uniqueFileURL(for: destination)

        // Ensure output directory exists
        try FileManager.default.createDirectory(
            at: finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if segments.count == 1 {
            // Single segment: move temp file to destination
            let tempURL = segmentTempURL(for: 0)
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.moveItem(at: tempURL, to: finalURL)
            }
        } else {
            // Multi-segment: concatenate all temp files in order
            if !FileManager.default.fileExists(atPath: finalURL.path) {
                FileManager.default.createFile(atPath: finalURL.path, contents: nil)
            }
            guard let output = FileHandle(forWritingAtPath: finalURL.path) else {
                throw DownloadError.assemblyFailed
            }
            for segment in segments.sorted(by: { $0.id < $1.id }) {
                let tempURL = segmentTempURL(for: segment.id)
                guard let data = try? Data(contentsOf: tempURL) else {
                    throw DownloadError.segmentMissing(segment.id)
                }
                output.write(data)
                try? FileManager.default.removeItem(at: tempURL)
            }
            try output.close()
        }

        // Update task with final filename (in case we de-duplicated)
        await MainActor.run {
            task.filename = finalURL.lastPathComponent
        }

        // Optional: verify checksum
        if let expectedMD5 = task.checksumMD5 {
            let actualMD5 = try md5(of: finalURL)
            if actualMD5 != expectedMD5 {
                try? FileManager.default.removeItem(at: finalURL)
                throw DownloadError.checksumMismatch
            }
        }
    }

    // MARK: - Helpers

    private func segmentTempURL(for segmentID: Int) -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let swiftgetCache = cacheDir.appendingPathComponent("SwiftGet/segments")
        try? FileManager.default.createDirectory(at: swiftgetCache, withIntermediateDirectories: true)
        return swiftgetCache.appendingPathComponent("\(task.id.uuidString)_seg\(segmentID).part")
    }

    private func uniqueFileURL(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var counter = 1
        while true {
            let candidate = dir
                .appendingPathComponent("\(name) (\(counter))")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private func md5(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - Errors

enum DownloadError: LocalizedError {
    case assemblyFailed
    case segmentMissing(Int)
    case checksumMismatch
    case serverRejectedRange

    var errorDescription: String? {
        switch self {
        case .assemblyFailed:         return "Failed to assemble download segments."
        case .segmentMissing(let i):  return "Segment \(i) is missing."
        case .checksumMismatch:       return "File integrity check failed (checksum mismatch)."
        case .serverRejectedRange:    return "Server does not support partial downloads."
        }
    }
}
