import SwiftUI
import AppKit

struct DownloadRowView: View {
    @ObservedObject var task: DownloadTask

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: task.category.systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            // Main content
            VStack(alignment: .leading, spacing: 4) {
                Text(task.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Progress bar
                if !task.status.isTerminal && task.status != .queued {
                    ProgressView(value: task.progress)
                        .progressViewStyle(.linear)
                        .tint(progressColor)
                }

                // Status line
                HStack(spacing: 6) {
                    statusBadge
                    if task.status.isActive {
                        if task.totalBytes > 0 {
                            Text("\(ByteCountFormatter.string(fromByteCount: task.downloadedBytes, countStyle: .file)) / \(task.formattedSize)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !task.formattedSpeed.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(task.formattedSpeed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !task.formattedETA.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("ETA \(task.formattedETA)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if task.status == .completed {
                        Text(task.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if task.status == .failed, let err = task.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                    Spacer()
                    // Segment indicators
                    if task.status.isActive && task.segments.count > 1 {
                        SegmentIndicatorView(segments: task.segments)
                    }
                }
            }

            Spacer(minLength: 0)

            // Action button
            actionButton
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sub-views

    private var progressColor: Color {
        switch task.status {
        case .downloading:  return .accentColor
        case .assembling:   return .orange
        default:            return .accentColor
        }
    }

    private var statusBadge: some View {
        Text(task.status.rawValue)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch task.status {
        case .queued:      return .secondary
        case .downloading: return .accentColor
        case .paused:      return .orange
        case .assembling:  return .orange
        case .completed:   return .green
        case .failed:      return .red
        case .scheduled:   return .purple
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if task.status.isActive {
            Button {
                DownloadManager.shared.pause(task)
            } label: {
                Image(systemName: "pause.fill")
            }
        } else if task.status == .paused || task.status == .failed {
            Button {
                DownloadManager.shared.resume(task)
            } label: {
                Image(systemName: "play.fill")
            }
        } else if task.status == .completed {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([task.localFileURL])
            } label: {
                Image(systemName: "folder")
            }
        }
    }
}

// MARK: - Segment Indicator

struct SegmentIndicatorView: View {
    let segments: [DownloadSegment]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { seg in
                RoundedRectangle(cornerRadius: 2)
                    .fill(seg.isComplete ? Color.green : Color.accentColor.opacity(0.3 + 0.7 * seg.progress))
                    .frame(width: 6, height: 14)
            }
        }
    }
}

