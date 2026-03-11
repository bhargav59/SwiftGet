import Foundation
import Combine
import AppKit
import UserNotifications

public class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()
    
    @Published public var downloads: [DownloadItem] = []
    @Published public var maxConcurrentDownloads: Int = 3
    @Published public var globalBandwidthLimit: Double = 0 // 0 = unlimited
    
    private var engines: [UUID: DownloadEngine] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    public func addDownload(url: URL, savePath: URL? = nil, segmentCount: Int = 8) {
        let item = DownloadItem(url: url, savePath: savePath)
        item.segmentCount = segmentCount
        
        DispatchQueue.main.async {
            self.downloads.append(item)
            self.processQueue()
        }
    }
    
    public func pauseDownload(_ item: DownloadItem) {
        engines[item.id]?.pause()
    }
    
    public func resumeDownload(_ item: DownloadItem) {
        if engines[item.id] == nil {
            startEngine(for: item)
        } else {
            engines[item.id]?.resume()
        }
    }
    
    public func cancelDownload(_ item: DownloadItem) {
        engines[item.id]?.cancel()
        engines.removeValue(forKey: item.id)
        DispatchQueue.main.async {
            self.downloads.removeAll { $0.id == item.id }
        }
    }
    
    public func pauseAll() {
        downloads.filter { $0.status == .downloading }.forEach { pauseDownload($0) }
    }
    
    public func resumeAll() {
        downloads.filter { $0.status == .paused }.forEach { resumeDownload($0) }
    }
    
    public func removeCompleted() {
        DispatchQueue.main.async {
            self.downloads.removeAll { $0.status == .completed }
        }
    }
    
    public func downloads(for category: FileCategory) -> [DownloadItem] {
        downloads.filter { $0.category == category }
    }
    
    private func processQueue() {
        let active = downloads.filter { $0.status == .downloading }.count
        let queued = downloads.filter { $0.status == .queued }
        
        let canStart = maxConcurrentDownloads - active
        guard canStart > 0 else { return }
        
        // Prioritize: high > normal > low
        let sorted = queued.sorted { a, b in
            let order: [DownloadPriority] = [.high, .normal, .low]
            let ai = order.firstIndex(of: a.priority) ?? 1
            let bi = order.firstIndex(of: b.priority) ?? 1
            return ai < bi
        }
        
        for item in sorted.prefix(canStart) {
            startEngine(for: item)
        }
    }
    
    private func startEngine(for item: DownloadItem) {
        let engine = DownloadEngine(item: item)
        engine.delegate = self
        engines[item.id] = engine
        engine.start()
    }
    
    var totalProgress: Double {
        let active = downloads.filter { $0.status == .downloading || $0.status == .paused }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0.0) { $0 + $1.progress } / Double(active.count)
    }
}

extension DownloadManager: DownloadEngineDelegate {
    public func downloadEngineDidComplete(_ engine: DownloadEngine, item: DownloadItem) {
        engines.removeValue(forKey: item.id)
        
        // Send notification
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = item.filename
        content.sound = .default
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        
        // Update Dock badge
        DispatchQueue.main.async {
            let activeCount = self.downloads.filter { $0.status == .downloading }.count
            NSApp.dockTile.badgeLabel = activeCount > 0 ? "\(activeCount)" : nil
        }
        
        processQueue()
    }
    
    public func downloadEngineDidFail(_ engine: DownloadEngine, item: DownloadItem, error: Error) {
        engines.removeValue(forKey: item.id)
        processQueue()
    }
}
