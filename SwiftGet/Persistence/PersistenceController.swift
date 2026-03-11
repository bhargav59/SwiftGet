import Foundation

/// Lightweight JSON-based persistence for download tasks.
/// In a production build this would use Core Data, but JSON provides
/// a zero-dependency, portable approach for v1.0.
final class PersistenceController {

    static let shared = PersistenceController()

    // MARK: - Storage URL

    private var storeURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SwiftGet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("downloads.json")
    }

    // MARK: - Codable DTO

    private struct TaskDTO: Codable {
        var id: UUID
        var urlString: String
        var filename: String
        var suggestedFilename: String?
        var referrer: String?
        var destinationFolderPath: String
        var priorityRaw: Int
        var statusRaw: String
        var totalBytes: Int64
        var downloadedBytes: Int64
        var categoryRaw: String
        var scheduledAt: Date?
        var createdAt: Date
        var errorMessage: String?
        var segments: [SegmentDTO]

        struct SegmentDTO: Codable {
            var id: Int
            var startByte: Int64
            var endByte: Int64
            var downloadedBytes: Int64
            var isComplete: Bool
        }
    }

    // MARK: - Save

    @MainActor
    func save(_ task: DownloadTask) {
        var all = loadDTOs()
        let dto = makeDTO(from: task)
        if let idx = all.firstIndex(where: { $0.id == task.id }) {
            all[idx] = dto
        } else {
            all.append(dto)
        }
        writeDTOs(all)
    }

    @MainActor
    func delete(_ task: DownloadTask) {
        var all = loadDTOs()
        all.removeAll { $0.id == task.id }
        writeDTOs(all)
    }

    // MARK: - Load

    @MainActor
    func loadAll() -> [DownloadTask] {
        loadDTOs().compactMap { makeTask(from: $0) }
    }

    // MARK: - Private Helpers

    private func loadDTOs() -> [TaskDTO] {
        guard let data = try? Data(contentsOf: storeURL),
              let dtos = try? JSONDecoder().decode([TaskDTO].self, from: data) else {
            return []
        }
        return dtos
    }

    private func writeDTOs(_ dtos: [TaskDTO]) {
        guard let data = try? JSONEncoder().encode(dtos) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    @MainActor
    private func makeDTO(from task: DownloadTask) -> TaskDTO {
        TaskDTO(
            id: task.id,
            urlString: task.url.absoluteString,
            filename: task.filename,
            suggestedFilename: task.suggestedFilename,
            referrer: task.referrer,
            destinationFolderPath: task.destinationFolder.path,
            priorityRaw: task.priority.rawValue,
            statusRaw: task.status.rawValue,
            totalBytes: task.totalBytes,
            downloadedBytes: task.downloadedBytes,
            categoryRaw: task.category.rawValue,
            scheduledAt: task.scheduledAt,
            createdAt: task.createdAt,
            errorMessage: task.errorMessage,
            segments: task.segments.map {
                TaskDTO.SegmentDTO(
                    id: $0.id,
                    startByte: $0.startByte,
                    endByte: $0.endByte,
                    downloadedBytes: $0.downloadedBytes,
                    isComplete: $0.isComplete
                )
            }
        )
    }

    @MainActor
    private func makeTask(from dto: TaskDTO) -> DownloadTask? {
        guard let url = URL(string: dto.urlString) else { return nil }
        let task = DownloadTask(
            id: dto.id,
            url: url,
            suggestedFilename: dto.suggestedFilename,
            referrer: dto.referrer,
            destinationFolder: URL(fileURLWithPath: dto.destinationFolderPath),
            priority: DownloadPriority(rawValue: dto.priorityRaw) ?? .normal,
            scheduledAt: dto.scheduledAt
        )
        task.filename = dto.filename
        task.status = DownloadStatus(rawValue: dto.statusRaw) ?? .queued
        task.totalBytes = dto.totalBytes
        task.downloadedBytes = dto.downloadedBytes
        task.category = DownloadCategory(rawValue: dto.categoryRaw) ?? .other
        task.createdAt = dto.createdAt
        task.errorMessage = dto.errorMessage
        task.segments = dto.segments.map {
            DownloadSegment(
                id: $0.id,
                startByte: $0.startByte,
                endByte: $0.endByte,
                downloadedBytes: $0.downloadedBytes,
                isComplete: $0.isComplete
            )
        }
        return task
    }
}
