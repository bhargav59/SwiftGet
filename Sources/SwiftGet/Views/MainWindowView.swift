import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var selectedCategory: FileCategory? = nil
    @State private var selectedDownload: DownloadItem? = nil
    @State private var showAddDownload = false
    @State private var searchText = ""
    
    var filteredDownloads: [DownloadItem] {
        var items = downloadManager.downloads
        if let category = selectedCategory {
            items = items.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            items = items.filter {
                $0.filename.localizedCaseInsensitiveContains(searchText) ||
                $0.url.absoluteString.localizedCaseInsensitiveContains(searchText)
            }
        }
        return items
    }
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCategory: $selectedCategory)
        } content: {
            DownloadListView(
                downloads: filteredDownloads,
                selectedDownload: $selectedDownload,
                searchText: $searchText
            )
        } detail: {
            if let download = selectedDownload {
                DownloadDetailView(item: download)
            } else {
                Text("Select a download to see details")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("SwiftGet")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddDownload = true }) {
                    Label("Add Download", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button(action: { downloadManager.pauseAll() }) {
                    Label("Pause All", systemImage: "pause.fill")
                }
            }
            ToolbarItem {
                Button(action: { downloadManager.resumeAll() }) {
                    Label("Resume All", systemImage: "play.fill")
                }
            }
        }
        .sheet(isPresented: $showAddDownload) {
            AddDownloadView(isPresented: $showAddDownload)
                .environmentObject(downloadManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddDownload)) { _ in
            showAddDownload = true
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @Binding var selectedCategory: FileCategory?
    
    var body: some View {
        List(selection: $selectedCategory) {
            Section("Downloads") {
                Label("All Downloads", systemImage: "arrow.down.circle")
                    .tag(nil as FileCategory?)
            }
            
            Section("Categories") {
                ForEach(FileCategory.allCases, id: \.self) { category in
                    HStack {
                        Label(category.rawValue, systemImage: iconName(for: category))
                        Spacer()
                        let count = downloadManager.downloads(for: category).count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tag(category as FileCategory?)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }
    
    func iconName(for category: FileCategory) -> String {
        switch category {
        case .video: return "film"
        case .document: return "doc.text"
        case .music: return "music.note"
        case .archive: return "archivebox"
        case .other: return "folder"
        }
    }
}

struct DownloadListView: View {
    let downloads: [DownloadItem]
    @Binding var selectedDownload: DownloadItem?
    @Binding var searchText: String
    @EnvironmentObject var downloadManager: DownloadManager
    
    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            
            Divider()
            
            if downloads.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.circle.dotted")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No downloads")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Click + to add a download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(downloads, id: \.id, selection: $selectedDownload) { item in
                    DownloadRowView(item: item)
                        .contextMenu {
                            Button("Pause") { downloadManager.pauseDownload(item) }
                            Button("Resume") { downloadManager.resumeDownload(item) }
                            Button("Cancel") { downloadManager.cancelDownload(item) }
                            Divider()
                            Button("Show in Finder") { 
                                NSWorkspace.shared.selectFile(item.savePath.path, inFileViewerRootedAtPath: "")
                            }
                        }
                }
            }
        }
        .frame(minWidth: 300)
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search downloads...", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct DownloadRowView: View {
    @ObservedObject var item: DownloadItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .frame(width: 16)
                Text(item.filename)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                Spacer()
                Text(item.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if item.status == .downloading || item.status == .paused {
                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .tint(item.status == .paused ? .orange : .blue)
                
                HStack {
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !item.formattedSpeed.isEmpty {
                        Text(item.formattedSpeed)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if !item.formattedETA.isEmpty {
                        Text("ETA: \(item.formattedETA)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text(item.status.rawValue)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
        }
        .padding(.vertical, 4)
    }
    
    var statusIcon: String {
        switch item.status {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
    
    var statusColor: Color {
        switch item.status {
        case .queued: return .secondary
        case .downloading: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

struct DownloadDetailView: View {
    @ObservedObject var item: DownloadItem
    @EnvironmentObject var downloadManager: DownloadManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.filename)
                            .font(.headline)
                            .lineLimit(2)
                        Text(item.url.absoluteString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                
                Divider()
                
                // Progress
                if item.status == .downloading || item.status == .paused {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Progress")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(item.progress * 100))%")
                                .font(.subheadline)
                        }
                        ProgressView(value: item.progress)
                            .progressViewStyle(.linear)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Speed").font(.caption).foregroundColor(.secondary)
                                Text(item.formattedSpeed.isEmpty ? "—" : item.formattedSpeed).font(.caption)
                            }
                            Spacer()
                            VStack(alignment: .center) {
                                Text("ETA").font(.caption).foregroundColor(.secondary)
                                Text(item.formattedETA.isEmpty ? "—" : item.formattedETA).font(.caption)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Size").font(.caption).foregroundColor(.secondary)
                                Text(item.formattedSize).font(.caption)
                            }
                        }
                    }
                }
                
                // Segments visualization
                if !item.segments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Segments (\(item.segments.count))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack(spacing: 2) {
                            ForEach(item.segments) { seg in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(seg.isCompleted ? Color.green : Color.blue.opacity(0.3 + seg.progress * 0.7))
                                    .frame(height: 8)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Info
                InfoRow(label: "Status", value: item.status.rawValue)
                InfoRow(label: "Category", value: item.category.rawValue)
                InfoRow(label: "Priority", value: item.priority.rawValue)
                InfoRow(label: "Save Path", value: item.savePath.path)
                InfoRow(label: "Added", value: item.createdAt.formatted())
                
                Divider()
                
                // Actions
                HStack {
                    if item.status == .downloading {
                        Button("Pause") { downloadManager.pauseDownload(item) }
                    }
                    if item.status == .paused || item.status == .failed {
                        Button("Resume") { downloadManager.resumeDownload(item) }
                    }
                    if item.status == .completed {
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(item.savePath.path, inFileViewerRootedAtPath: "")
                        }
                    }
                    Button("Cancel", role: .destructive) {
                        downloadManager.cancelDownload(item)
                    }
                    
                    Spacer()
                    
                    Picker("Priority", selection: Binding(
                        get: { item.priority },
                        set: { item.priority = $0 }
                    )) {
                        ForEach(DownloadPriority.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(minWidth: 280)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
