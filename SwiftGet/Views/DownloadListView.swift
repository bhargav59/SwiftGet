import SwiftUI

struct DownloadListView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    let category: DownloadCategory
    @Binding var selectedTaskID: UUID?
    let searchText: String

    var filteredTasks: [DownloadTask] {
        downloadManager.tasks(for: category, searchText: searchText)
    }

    var body: some View {
        Group {
            if filteredTasks.isEmpty {
                emptyState
            } else {
                List(filteredTasks, selection: $selectedTaskID) { task in
                    DownloadRowView(task: task)
                        .tag(task.id)
                        .contextMenu {
                            contextMenuItems(for: task)
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(category.rawValue)
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button(action: downloadManager.deleteCompleted) {
                    Label("Clear Completed", systemImage: "trash")
                }
                .help("Remove completed downloads from the list")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No Downloads Yet" : "No Results")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("Click + to add a URL, or install the Chrome extension\nto automatically capture downloads.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for task: DownloadTask) -> some View {
        if task.status.isActive {
            Button("Pause") { downloadManager.pause(task) }
        } else if task.status == .paused || task.status == .failed {
            Button("Resume") { downloadManager.resume(task) }
        }
        if task.status == .completed {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([task.localFileURL])
            }
            Button("Open") {
                NSWorkspace.shared.open(task.localFileURL)
            }
        }
        Divider()
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(task.url.absoluteString, forType: .string)
        }
        Divider()
        Button("Remove", role: .destructive) {
            downloadManager.remove(task)
        }
    }
}

import AppKit
