import SwiftUI

struct AddDownloadView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var downloadManager: DownloadManager
    
    @State private var urlString: String = ""
    @State private var savePath: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    @State private var segmentCount: Int = 8
    @State private var showFilePicker = false
    @State private var priority: DownloadPriority = .normal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Download")
                .font(.headline)
            
            // URL field
            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("https://example.com/file.zip", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                    Button("Paste") {
                        if let string = NSPasteboard.general.string(forType: .string) {
                            urlString = string
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // Save location
            VStack(alignment: .leading, spacing: 6) {
                Text("Save To")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    Text(savePath.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    Spacer()
                    Button("Choose...") {
                        showFilePicker = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // Segments
            HStack {
                Text("Segments")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Stepper("\(segmentCount)", value: $segmentCount, in: 1...32)
            }
            
            // Priority
            HStack {
                Text("Priority")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $priority) {
                    ForEach(DownloadPriority.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add Download") {
                    addDownload()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            // Auto-paste from clipboard
            if let string = NSPasteboard.general.string(forType: .string),
               string.hasPrefix("http") {
                urlString = string
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                savePath = url
            }
        }
    }
    
    private func addDownload() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else { return }
        let filename = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let fullSavePath = savePath.appendingPathComponent(filename)
        downloadManager.addDownload(url: url, savePath: fullSavePath, segmentCount: segmentCount)
        isPresented = false
    }
}
