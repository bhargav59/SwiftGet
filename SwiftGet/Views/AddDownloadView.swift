import SwiftUI
import AppKit

struct AddDownloadView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @Binding var isPresented: Bool

    @State private var urlString: String = ""
    @State private var selectedFolder: URL? = nil
    @State private var priority: DownloadPriority = .normal
    @State private var scheduledDate: Date = Date()
    @State private var useSchedule: Bool = false
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showAuth: Bool = false
    @State private var isValidating: Bool = false
    @State private var videoInfo: VideoExtractor.VideoInfo? = nil
    @State private var selectedFormatID: String? = nil
    @State private var errorMessage: String? = nil

    private var effectiveURL: URL? {
        guard !urlString.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        // Try adding https://
        return URL(string: "https://" + trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Text("Add Download")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            Form {
                // URL field
                Section {
                    HStack {
                        TextField("https://example.com/file.zip", text: $urlString)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .onAppear {
                                // Auto-paste from clipboard if URL present
                                if let clipboard = NSPasteboard.general.string(forType: .string),
                                   let _ = URL(string: clipboard), clipboard.hasPrefix("http") {
                                    urlString = clipboard
                                }
                            }
                        if isValidating {
                            ProgressView().scaleEffect(0.7)
                        } else if effectiveURL != nil {
                            Button("Analyse") { analyseURL() }
                                .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("URL")
                }

                // Video format picker (if detected)
                if let info = videoInfo {
                    Section("Video: \(info.title)") {
                        Picker("Format", selection: $selectedFormatID) {
                            Text("Best Quality (auto)").tag(Optional<String>.none)
                            ForEach(info.formats) { fmt in
                                Text(fmt.displayLabel).tag(Optional(fmt.id))
                            }
                        }
                    }
                }

                // Destination folder
                Section("Save To") {
                    HStack {
                        Text(selectedFolder?.path ?? downloadManager.defaultDownloadFolder.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.canCreateDirectories = true
                            panel.prompt = "Select"
                            if panel.runModal() == .OK {
                                selectedFolder = panel.url
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Priority
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(DownloadPriority.allCases, id: \.rawValue) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Scheduler
                Section {
                    Toggle("Schedule download", isOn: $useSchedule)
                    if useSchedule {
                        DatePicker("Start at", selection: $scheduledDate)
                    }
                }

                // Auth
                Section {
                    DisclosureGroup("HTTP Authentication", isExpanded: $showAuth) {
                        TextField("Username", text: $username)
                        SecureField("Password", text: $password)
                    }
                }
            }
            .formStyle(.grouped)

            // Error
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Download") {
                    addDownload()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(effectiveURL == nil)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func analyseURL() {
        guard let url = effectiveURL else { return }
        isValidating = true
        errorMessage = nil
        Task {
            do {
                let info = try await VideoExtractor.shared.extractInfo(from: url)
                await MainActor.run {
                    videoInfo = info
                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    videoInfo = nil
                    isValidating = false
                    // Not a video URL — that's fine, just download directly
                }
            }
        }
    }

    private func addDownload() {
        guard let url = effectiveURL else { return }

        let folder = selectedFolder ?? downloadManager.defaultDownloadFolder
        let schedDate = useSchedule ? scheduledDate : nil

        // Build auth header if provided
        var cookies: String? = nil
        if !username.isEmpty {
            let creds = "\(username):\(password)"
            let encoded = Data(creds.utf8).base64EncodedString()
            cookies = "Authorization: Basic \(encoded)"
        }

        let task = DownloadTask(
            url: url,
            referrer: nil,
            cookies: cookies,
            destinationFolder: folder,
            priority: priority,
            scheduledAt: schedDate
        )

        if useSchedule {
            task.status = .scheduled
        }

        downloadManager.enqueue(task)
        isPresented = false
    }
}

