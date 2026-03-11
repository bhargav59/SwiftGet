import Foundation

/// Core multi-segment parallel download engine
class DownloadEngine: NSObject {
    
    private let item: DownloadItem
    private var segmentTasks: [URLSessionDataTask] = []
    private var session: URLSession!
    private var segmentBuffers: [Int: Data] = [:]
    private var lock = NSLock()
    private var speedTimer: Timer?
    private var lastBytesCount: Int64 = 0
    private var lastSpeedUpdate: Date = Date()
    
    weak var delegate: DownloadEngineDelegate?
    
    init(item: DownloadItem) {
        self.item = item
        super.init()
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "SwiftGet/1.0"]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    func start() {
        Task {
            await startDownload()
        }
    }
    
    func pause() {
        segmentTasks.forEach { $0.suspend() }
        speedTimer?.invalidate()
        DispatchQueue.main.async {
            self.item.status = .paused
        }
    }
    
    func resume() {
        segmentTasks.forEach { $0.resume() }
        startSpeedTimer()
        DispatchQueue.main.async {
            self.item.status = .downloading
        }
    }
    
    func cancel() {
        segmentTasks.forEach { $0.cancel() }
        speedTimer?.invalidate()
        DispatchQueue.main.async {
            self.item.status = .cancelled
        }
    }
    
    private func startDownload() async {
        DispatchQueue.main.async {
            self.item.status = .downloading
        }
        
        // First, probe server for content length and Range support
        guard let (contentLength, supportsRange) = await probeServer() else {
            await downloadSingleSegment()
            return
        }
        
        DispatchQueue.main.async {
            self.item.totalBytes = contentLength
        }
        
        if supportsRange && contentLength > 1_024_000 && item.segmentCount > 1 {
            await downloadMultiSegment(contentLength: contentLength)
        } else {
            await downloadSingleSegment()
        }
    }
    
    private func probeServer() async -> (Int64, Bool)? {
        var request = URLRequest(url: item.url)
        request.httpMethod = "HEAD"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            let contentLength = Int64(http.value(forHTTPHeaderField: "Content-Length") ?? "0") ?? 0
            let supportsRange = http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"
            return (contentLength, supportsRange)
        } catch {
            return nil
        }
    }
    
    private func downloadMultiSegment(contentLength: Int64) async {
        let segmentSize = contentLength / Int64(item.segmentCount)
        var segments: [DownloadSegment] = []
        
        for i in 0..<item.segmentCount {
            let start = Int64(i) * segmentSize
            let end = i == item.segmentCount - 1 ? contentLength - 1 : start + segmentSize - 1
            let segment = DownloadSegment(index: i, startByte: start, endByte: end)
            segments.append(segment)
        }
        
        DispatchQueue.main.async {
            self.item.segments = segments
        }
        
        startSpeedTimer()
        
        await withTaskGroup(of: Void.self) { group in
            for segment in segments {
                group.addTask {
                    await self.downloadSegment(segment)
                }
            }
        }
        
        speedTimer?.invalidate()
        
        // Assemble segments
        if segments.allSatisfy({ $0.isCompleted }) {
            assembleSegments(segments: segments, totalSize: contentLength)
        }
    }
    
    private func downloadSegment(_ segment: DownloadSegment) async {
        var request = URLRequest(url: item.url)
        request.setValue("bytes=\(segment.startByte)-\(segment.endByte)", forHTTPHeaderField: "Range")
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(item.id)_segment_\(segment.index).tmp")
        
        // Resume support: check if partial temp file exists
        let existingSize: Int64
        if FileManager.default.fileExists(atPath: tempURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
           let size = attrs[.size] as? Int64, size > 0 {
            existingSize = size
            request.setValue("bytes=\(segment.startByte + size)-\(segment.endByte)", forHTTPHeaderField: "Range")
        } else {
            existingSize = 0
        }
        
        // Reflect already-downloaded bytes so progress reporting is accurate on resume
        segment.downloadedBytes = existingSize
        
        do {
            let (asyncBytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return
            }
            
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: tempURL)
            fileHandle.seekToEndOfFile()
            
            var buffer = Data()
            var bytesInBuffer: Int64 = 0
            
            for try await byte in asyncBytes {
                buffer.append(byte)
                bytesInBuffer += 1
                
                if buffer.count >= 65536 { // 64KB buffer
                    fileHandle.write(buffer)
                    
                    // Apply bandwidth limiting
                    if item.bandwidthLimit > 0 {
                        let delay = Double(buffer.count) / item.bandwidthLimit
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    
                    lock.lock()
                    segment.downloadedBytes += Int64(buffer.count)
                    updateProgress()
                    lock.unlock()
                    
                    buffer = Data()
                }
            }
            
            if !buffer.isEmpty {
                fileHandle.write(buffer)
                lock.lock()
                segment.downloadedBytes += Int64(buffer.count)
                updateProgress()
                lock.unlock()
            }
            
            try fileHandle.close()
            segment.isCompleted = true
            
        } catch {
            print("Segment \(segment.index) download error: \(error)")
        }
    }
    
    private func downloadSingleSegment() async {
        var request = URLRequest(url: item.url)
        
        let destURL = item.savePath
        
        // Resume support
        if FileManager.default.fileExists(atPath: destURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path),
           let size = attrs[.size] as? Int64, size > 0 {
            request.setValue("bytes=\(size)-", forHTTPHeaderField: "Range")
            DispatchQueue.main.async { self.item.downloadedBytes = size }
        }
        
        startSpeedTimer()
        
        do {
            let (asyncBytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                DispatchQueue.main.async {
                    self.item.status = .failed
                    self.item.errorMessage = "Server returned error"
                }
                return
            }
            
            if let lengthStr = http.value(forHTTPHeaderField: "Content-Length"),
               let length = Int64(lengthStr) {
                DispatchQueue.main.async { self.item.totalBytes = length }
            }
            
            let fileURL = item.savePath
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()
            
            var buffer = Data()
            
            for try await byte in asyncBytes {
                buffer.append(byte)
                
                if buffer.count >= 65536 {
                    fileHandle.write(buffer)
                    lock.lock()
                    item.downloadedBytes += Int64(buffer.count)
                    updateProgress()
                    lock.unlock()
                    buffer = Data()
                }
            }
            
            if !buffer.isEmpty {
                fileHandle.write(buffer)
                lock.lock()
                item.downloadedBytes += Int64(buffer.count)
                lock.unlock()
            }
            
            try fileHandle.close()
            
            speedTimer?.invalidate()
            DispatchQueue.main.async {
                self.item.progress = 1.0
                self.item.status = .completed
                self.item.completedAt = Date()
                self.item.speed = 0
            }
            self.delegate?.downloadEngineDidComplete(self, item: self.item)
            
        } catch {
            speedTimer?.invalidate()
            DispatchQueue.main.async {
                self.item.status = .failed
                self.item.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func assembleSegments(segments: [DownloadSegment], totalSize: Int64) {
        let destURL = item.savePath
        FileManager.default.createFile(atPath: destURL.path, contents: nil)
        
        guard let fileHandle = try? FileHandle(forWritingTo: destURL) else {
            DispatchQueue.main.async { self.item.status = .failed }
            return
        }
        
        for segment in segments.sorted(by: { $0.index < $1.index }) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(item.id)_segment_\(segment.index).tmp")
            if let data = try? Data(contentsOf: tempURL) {
                fileHandle.write(data)
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        
        try? fileHandle.close()
        
        DispatchQueue.main.async {
            self.item.progress = 1.0
            self.item.status = .completed
            self.item.completedAt = Date()
            self.item.speed = 0
        }
        self.delegate?.downloadEngineDidComplete(self, item: self.item)
    }
    
    private func updateProgress() {
        let downloaded: Int64
        if item.segments.isEmpty {
            downloaded = item.downloadedBytes
        } else {
            downloaded = item.segments.reduce(0) { $0 + $1.downloadedBytes }
        }
        
        DispatchQueue.main.async {
            self.item.downloadedBytes = downloaded
            if self.item.totalBytes > 0 {
                self.item.progress = Double(downloaded) / Double(self.item.totalBytes)
            }
        }
    }
    
    private func startSpeedTimer() {
        lastBytesCount = item.downloadedBytes
        lastSpeedUpdate = Date()
        
        DispatchQueue.main.async {
            self.speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let now = Date()
                let elapsed = now.timeIntervalSince(self.lastSpeedUpdate)
                let current = self.item.downloadedBytes
                let bytesPerSec = Double(current - self.lastBytesCount) / elapsed
                
                self.item.speed = max(0, bytesPerSec)
                
                let remaining = self.item.totalBytes - current
                if bytesPerSec > 0 {
                    self.item.eta = Double(remaining) / bytesPerSec
                }
                
                self.lastBytesCount = current
                self.lastSpeedUpdate = now
                
                // Update Dock badge with global active download count
                let activeCount = DownloadManager.shared.downloads.filter { $0.status == .downloading }.count
                NSApp.dockTile.badgeLabel = activeCount > 0 ? "\(activeCount)" : nil
            }
        }
    }
}

extension DownloadEngine: URLSessionDelegate {}

protocol DownloadEngineDelegate: AnyObject {
    func downloadEngineDidComplete(_ engine: DownloadEngine, item: DownloadItem)
    func downloadEngineDidFail(_ engine: DownloadEngine, item: DownloadItem, error: Error)
}
