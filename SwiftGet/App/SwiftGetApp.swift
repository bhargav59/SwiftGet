import SwiftUI
import AppKit

@main
struct SwiftGetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("SwiftGet") {
            ContentView()
                .environmentObject(DownloadManager.shared)
                .environmentObject(SchedulerManager.shared)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add URL…") {
                    NotificationCenter.default.post(name: .showAddDownload, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }

        // Menu bar extra for quick access
        MenuBarExtra("SwiftGet", systemImage: "arrow.down.circle") {
            MenuBarView()
                .environmentObject(DownloadManager.shared)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(DownloadManager.shared)
                .environmentObject(SchedulerManager.shared)
        }
    }
}

extension Notification.Name {
    static let showAddDownload = Notification.Name("showAddDownload")
    static let downloadCompleted = Notification.Name("downloadCompleted")
    static let downloadFailed = Notification.Name("downloadFailed")
    static let nativeMessageReceived = Notification.Name("nativeMessageReceived")
}
