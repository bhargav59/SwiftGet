import Foundation
import AppKit

/// Central coordinator for all download operations.
@MainActor
final class DownloadManager: ObservableObject {

    static let shared = DownloadManager()

    // MARK: - Published State

    @Published private(set) var tasks: [DownloadTask] = []
    @Published var maxConcurrentDownloads: Int = 3 {
        didSet { scheduleNext() }
    }
    @Published var globalBandwidthLimit: Double = 0   // 0 = unlimited, bytes/sec
    @Published var defaultDownloadFolder: URL = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }()
    @Published var defaultSegmentCount: Int = 8       // 1–32

    // MARK: - Private

    private var engines: [UUID: DownloadEngine] = [:]
    private var persistenceController = PersistenceController.shared
    private var dockProgressTimer: Timer?
    private var speedUpdateTimer: Timer?

    // MARK: - Init

    private init() {
        loadPersistedTasks()
        startDockProgressUpdates()
        startSpeedUpdates()
    }

    // MARK: - Queue Management

    func enqueue(_ task: DownloadTask) {
        tasks.append(task)
        persistenceController.save(task)
        scheduleNext()
    }

    func remove(_ task: DownloadTask) {
        task.status = .failed // Stop any engine
        engines[task.id]?.cancel()
        engines[task.id] = nil
        tasks.removeAll { $0.id == task.id }
        persistenceController.delete(task)
        scheduleNext()
    }

    func pause(_ task: DownloadTask) {
        guard task.status.isActive else { return }
        engines[task.id]?.pause()
        task.status = .paused
        persistenceController.save(task)
        scheduleNext()
    }

    func resume(_ task: DownloadTask) {
        guard task.status == .paused || task.status == .failed else { return }
        task.status = .queued
        task.errorMessage = nil
        scheduleNext()
    }

    func resumeAll() {
        tasks.forEach { task in
            if task.status == .paused || task.status == .failed {
                task.status = .queued
                task.errorMessage = nil
            }
        }
        scheduleNext()
    }

    func pauseAll() {
        tasks.forEach { pause($0) }
    }

    func pauseAllOnQuit() {
        tasks.forEach { task in
            if task.status.isActive { pause(task) }
        }
    }

    func cancelAll() {
        tasks.forEach { task in
            engines[task.id]?.cancel()
            engines[task.id] = nil
            task.status = .paused
        }
    }

    func deleteCompleted() {
        tasks.filter { $0.status == .completed }.forEach { remove($0) }
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        tasks.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func task(for id: UUID) -> DownloadTask? {
        tasks.first { $0.id == id }
    }

    // MARK: - Scheduling

    private func scheduleNext() {
        let active = tasks.filter { $0.status.isActive }.count
        guard active < maxConcurrentDownloads else { return }

        let available = maxConcurrentDownloads - active
        let queued = tasks
            .filter { $0.status == .queued && $0.scheduledAt == nil }
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
            .prefix(available)

        for task in queued {
            start(task)
        }
    }

    private func start(_ task: DownloadTask) {
        task.status = .downloading
        let engine = DownloadEngine(
            task: task,
            segmentCount: defaultSegmentCount,
            bandwidthLimit: globalBandwidthLimit,
            cookies: task.cookies
        )
        engines[task.id] = engine
        Task {
            await engine.start()
            handleEngineCompletion(for: task)
        }
    }

    private func handleEngineCompletion(for task: DownloadTask) {
        engines.removeValue(forKey: task.id)
        persistenceController.save(task)
        updateDockBadge()
        if task.status == .completed {
            NotificationCenter.default.post(name: .downloadCompleted, object: task)
        } else if task.status == .failed {
            NotificationCenter.default.post(name: .downloadFailed, object: task)
        }
        scheduleNext()
    }

    // MARK: - Dock Progress

    private func startDockProgressUpdates() {
        dockProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDockBadge()
            }
        }
    }

    private func updateDockBadge() {
        let active = tasks.filter { $0.status.isActive }
        if active.isEmpty {
            NSApp.dockTile.badgeLabel = nil
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.display()
            return
        }
        let totalProgress = active.map(\.progress).reduce(0, +) / Double(active.count)
        NSApp.dockTile.badgeLabel = "\(active.count)"

        // Draw aggregate progress in dock tile
        let dockView = DockProgressView(progress: totalProgress)
        let hostingView = DockProgressHostingView(rootView: dockView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 128, height: 128)
        NSApp.dockTile.contentView = hostingView
        NSApp.dockTile.display()
    }

    // MARK: - Speed Updates

    private func startSpeedUpdates() {
        speedUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.engines.values.forEach { $0.sampleSpeed() }
            }
        }
    }

    // MARK: - Persistence

    private func loadPersistedTasks() {
        tasks = persistenceController.loadAll()
        // Auto-queue incomplete tasks
        tasks.filter { $0.status == .downloading }.forEach { $0.status = .queued }
    }

    // MARK: - Filtering

    func tasks(for category: DownloadCategory, searchText: String) -> [DownloadTask] {
        tasks.filter { task in
            let matchesCategory = category == .all || task.category == category
            let matchesSearch = searchText.isEmpty ||
                task.displayName.localizedCaseInsensitiveContains(searchText) ||
                task.url.absoluteString.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var totalActiveSpeed: Double {
        tasks.filter { $0.status.isActive }.map(\.speed).reduce(0, +)
    }
}

// MARK: - Dock Progress View Helpers

import SwiftUI

struct DockProgressView: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(8)
    }
}

final class DockProgressHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize { .init(width: 128, height: 128) }
}
