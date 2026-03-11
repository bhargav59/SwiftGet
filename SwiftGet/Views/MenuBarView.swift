import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var downloadManager: DownloadManager

    var activeTasks: [DownloadTask] {
        downloadManager.tasks.filter { $0.status.isActive }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.accentColor)
                Text("SwiftGet")
                    .font(.headline)
                Spacer()
                if downloadManager.totalActiveSpeed > 0 {
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(downloadManager.totalActiveSpeed),
                        countStyle: .file) + "/s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if activeTasks.isEmpty {
                Text("No active downloads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(activeTasks) { task in
                    menuBarTaskRow(task)
                }
            }

            Divider()

            // Quick actions
            Button(action: {
                NotificationCenter.default.post(name: .showAddDownload, object: nil)
                NSApp.activate(ignoringOtherApps: true)
            }) {
                Label("Add URL…", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
            }) {
                Label("Open SwiftGet", systemImage: "macwindow")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit SwiftGet", systemImage: "power")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .padding(.vertical, 4)
    }

    private func menuBarTaskRow(_ task: DownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(task.formattedSpeed)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: task.progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
