import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var schedulerManager: SchedulerManager

    private enum Tab: String, CaseIterable {
        case general   = "General"
        case downloads = "Downloads"
        case scheduler = "Scheduler"
        case extension_ = "Extension"
        case advanced  = "Advanced"
    }
    @State private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(Tab.general)

            DownloadSettingsTab()
                .environmentObject(downloadManager)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .tag(Tab.downloads)

            SchedulerSettingsTab()
                .environmentObject(schedulerManager)
                .tabItem { Label("Scheduler", systemImage: "calendar.clock") }
                .tag(Tab.scheduler)

            ExtensionSettingsTab()
                .tabItem { Label("Extension", systemImage: "puzzlepiece.extension") }
                .tag(Tab.extension_)

            AdvancedSettingsTab()
                .environmentObject(downloadManager)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
                .tag(Tab.advanced)
        }
        .frame(width: 520, height: 380)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch SwiftGet at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        LaunchAtLoginManager.setEnabled(enabled)
                    }
            }
            Section("Notifications") {
                Text("Notifications are configured via System Settings › Notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Downloads Tab

struct DownloadSettingsTab: View {
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        Form {
            Section("Concurrency") {
                Stepper("Max concurrent downloads: \(downloadManager.maxConcurrentDownloads)",
                        value: $downloadManager.maxConcurrentDownloads,
                        in: 1...10)
                Stepper("Segments per download: \(downloadManager.defaultSegmentCount)",
                        value: $downloadManager.defaultSegmentCount,
                        in: 1...32)
            }
            Section("Default Save Location") {
                HStack {
                    Text(downloadManager.defaultDownloadFolder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            downloadManager.defaultDownloadFolder = url
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Scheduler Tab

struct SchedulerSettingsTab: View {
    @EnvironmentObject var schedulerManager: SchedulerManager

    var body: some View {
        Form {
            Section("Download Window") {
                Toggle("Enable scheduled download window", isOn: $schedulerManager.schedulingEnabled)
                if schedulerManager.schedulingEnabled {
                    HStack {
                        Text("From")
                        Picker("", selection: $schedulerManager.scheduleStartHour) {
                            ForEach(0..<24) { h in Text(String(format: "%02d:00", h)).tag(h) }
                        }
                        .frame(width: 80)
                        Text("to")
                        Picker("", selection: $schedulerManager.scheduleEndHour) {
                            ForEach(0..<24) { h in Text(String(format: "%02d:00", h)).tag(h) }
                        }
                        .frame(width: 80)
                    }
                }
            }
            Section("Bandwidth Throttle") {
                Toggle("Limit download speed", isOn: $schedulerManager.bandwidthLimitEnabled)
                if schedulerManager.bandwidthLimitEnabled {
                    HStack {
                        Slider(
                            value: $schedulerManager.bandwidthLimitBytesPerSecond,
                            in: 102_400...104_857_600,
                            step: 102_400
                        )
                        Text(ByteCountFormatter.string(
                            fromByteCount: Int64(schedulerManager.bandwidthLimitBytesPerSecond),
                            countStyle: .file) + "/s")
                        .frame(width: 80, alignment: .trailing)
                        .font(.caption)
                    }
                }
            }
            Section("Post-Queue Action") {
                Toggle("Shut down Mac after queue completes", isOn: $schedulerManager.shutdownAfterQueueCompletion)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onDisappear { schedulerManager.saveSettings() }
    }
}

// MARK: - Extension Tab

struct ExtensionSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("SwiftGet Chrome Extension")
                .font(.headline)
            Text("Install the SwiftGet extension from the Chrome Web Store to automatically intercept downloads and detect video streams.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Open Chrome Web Store") {
                NSWorkspace.shared.open(URL(string: "https://chrome.google.com/webstore/search/SwiftGet")!)
            }
            .buttonStyle(.borderedProminent)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Native Messaging Host")
                    .font(.subheadline.weight(.medium))
                Text("The Native Messaging host manifest is automatically installed at:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.swiftget.nativehost.json")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Advanced Tab

struct AdvancedSettingsTab: View {
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        Form {
            Section("yt-dlp") {
                Button("Update yt-dlp Now") {
                    Task {
                        try? await VideoExtractor.shared.updateYtDlp()
                    }
                }
                Text("yt-dlp is used to extract video streams from 1000+ websites. It updates automatically in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Data") {
                Button("Clear Download History") {
                    downloadManager.deleteCompleted()
                }
                Button("Reset All Settings", role: .destructive) {
                    if let domain = Bundle.main.bundleIdentifier {
                        UserDefaults.standard.removePersistentDomain(forName: domain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Launch at Login

enum LaunchAtLoginManager {
    static func setEnabled(_ enabled: Bool) {
        // Uses SMAppService on macOS 13+; falls back to LaunchAgent plist on earlier versions
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if enabled {
                try? service.register()
            } else {
                try? service.unregister()
            }
        }
    }
}

