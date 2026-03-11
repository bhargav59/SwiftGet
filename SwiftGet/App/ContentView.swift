import SwiftUI

struct ContentView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var selectedCategory: DownloadCategory = .all
    @State private var selectedTaskID: UUID?
    @State private var showingAddDownload = false
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            CategorySidebarView(selectedCategory: $selectedCategory)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 240)
        } content: {
            DownloadListView(
                category: selectedCategory,
                selectedTaskID: $selectedTaskID,
                searchText: searchText
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 500)
            .searchable(text: $searchText, prompt: "Search downloads…")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { showingAddDownload = true }) {
                        Label("Add URL", systemImage: "plus")
                    }
                    .help("Add new download (⌘N)")

                    Button(action: downloadManager.resumeAll) {
                        Label("Resume All", systemImage: "play.fill")
                    }
                    .help("Resume all paused downloads")

                    Button(action: downloadManager.pauseAll) {
                        Label("Pause All", systemImage: "pause.fill")
                    }
                    .help("Pause all active downloads")
                }
            }
        } detail: {
            if let id = selectedTaskID,
               let task = downloadManager.task(for: id) {
                DetailPanelView(task: task)
            } else {
                EmptyDetailView()
            }
        }
        .sheet(isPresented: $showingAddDownload) {
            AddDownloadView(isPresented: $showingAddDownload)
                .environmentObject(downloadManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddDownload)) { _ in
            showingAddDownload = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nativeMessageReceived)) { note in
            guard let message = note.object as? NativeMessage,
                  message.action == "add",
                  let urlString = message.url,
                  let url = URL(string: urlString) else { return }
            let task = DownloadTask(
                url: url,
                suggestedFilename: message.filename,
                referrer: message.referrer,
                cookies: message.cookies
            )
            downloadManager.enqueue(task)
        }
    }
}

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No Download Selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Select a download to view details")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
