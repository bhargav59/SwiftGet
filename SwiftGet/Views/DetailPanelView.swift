import SwiftUI
import Charts
import AppKit

struct DetailPanelView: View {
    @ObservedObject var task: DownloadTask
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Progress
                if !task.status.isTerminal {
                    progressSection
                    Divider()
                }

                // Speed Graph
                if task.status.isActive {
                    speedGraphSection
                    Divider()
                }

                // Details
                detailsSection

                Divider()

                // Actions
                actionsSection
            }
            .padding(20)
        }
        .frame(minWidth: 260)
        .navigationTitle(task.displayName)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.category.systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.displayName)
                    .font(.headline)
                    .lineLimit(3)
                Text(task.url.host ?? task.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progress")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(task.progress * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: task.progress)
                .progressViewStyle(.linear)
                .tint(task.status == .assembling ? .orange : .accentColor)
            HStack {
                if task.totalBytes > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: task.downloadedBytes, countStyle: .file)) of \(task.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !task.formattedETA.isEmpty {
                    Text("ETA \(task.formattedETA)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !task.formattedSpeed.isEmpty {
                Label(task.formattedSpeed, systemImage: "arrow.down")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            // Segment progress bars
            if task.segments.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Segments")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    ForEach(task.segments) { seg in
                        HStack(spacing: 6) {
                            Text("\(seg.id + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, alignment: .trailing)
                            ProgressView(value: seg.progress)
                                .progressViewStyle(.linear)
                                .tint(seg.isComplete ? .green : .accentColor)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Speed Graph

    private var speedGraphSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed")
                .font(.subheadline.weight(.medium))
            Chart {
                ForEach(Array(task.speedHistory.enumerated()), id: \.offset) { index, speed in
                    LineMark(
                        x: .value("Time", index),
                        y: .value("Speed", speed)
                    )
                    .foregroundStyle(Color.accentColor)
                    AreaMark(
                        x: .value("Time", index),
                        y: .value("Speed", speed)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file) + "/s")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 80)
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.subheadline.weight(.medium))
            infoRow("URL", value: task.url.absoluteString)
            infoRow("Destination", value: task.destinationFolder.path)
            infoRow("File", value: task.filename)
            if let mime = task.mimeType {
                infoRow("Type", value: mime)
            }
            if task.totalBytes > 0 {
                infoRow("Size", value: task.formattedSize)
            }
            infoRow("Priority", value: task.priority.label)
            infoRow("Category", value: task.category.rawValue)
            if let scheduled = task.scheduledAt {
                infoRow("Scheduled", value: scheduled.formatted(date: .abbreviated, time: .shortened))
            }
            infoRow("Added", value: task.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let err = task.errorMessage {
                infoRow("Error", value: err, valueColor: .red)
            }
        }
    }

    private func infoRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.subheadline.weight(.medium))
            HStack {
                if task.status.isActive {
                    Button("Pause") { downloadManager.pause(task) }
                } else if task.status == .paused || task.status == .failed {
                    Button("Resume") { downloadManager.resume(task) }
                }
                if task.status == .completed {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([task.localFileURL])
                    }
                    Button("Open File") {
                        NSWorkspace.shared.open(task.localFileURL)
                    }
                }
                Spacer()
                Button("Remove", role: .destructive) {
                    downloadManager.remove(task)
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

